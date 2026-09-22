"""Detailed mesh patches around every corpus quest spot.

Quest areas (NPC/object spawns, spawn clusters, objective bounds) from the
compiled Forever corpus become rectangles in navigation coordinates. Baked
polygons whose centers fall inside them are kept, grouped by road-network cell
(one patch per 128-yard cell), plus the polygons connecting each patch to its
cell's network nodes so the runtime can join mesh and network. Everything else
of the detailed mesh is dropped. Patches are modeled geometry, not verified.
"""
import collections, heapq, json, math, struct
import road_network as net
from world_source import need

SPAWN_RADIUS = 48.0      # yards around a single spawn or marker
CLUSTER_MARGIN = 24.0    # yards added around cluster/objective bounds
MAX_HALF = 160.0         # clip very large objective areas around their center
MAX_PATCH_POLYGONS = 8192


def quest_areas(semantic, views_by_map):
    """Yield (worldMapID, rect[x0, z0, x1, z1], area id) for every mapped corpus area."""
    seen = {}
    def collect(record):
        for key in ('starts', 'ends'):
            for target in record.get(key, []):
                for area in target.get('areas', []):
                    seen[(area['mapID'], area['id'])] = area
        for objective in record.get('objectives', []) + record.get('extraObjectives', []):
            for method in objective.get('methods', []):
                for area in method.get('areas', []):
                    seen[(area['mapID'], area['id'])] = area
    for quest in semantic.values():
        collect(quest['base'])
        for variant in (quest.get('variants') or {}).values():
            if isinstance(variant, dict):
                collect(variant)
    for (map_id, ident), area in sorted(seen.items(), key=lambda kv: (kv[0][0], kv[0][1])):
        view = pick_view(views_by_map.get(map_id, ()), area['x'], area['y'])
        if view is None:
            continue
        yield view['worldMapID'], area_rect(view, area), ident


def pick_view(views, x, y):
    for view in views:
        r = view['validUIRectangle']
        if r[0] <= x <= r[2] and r[1] <= y <= r[3]:
            return view
    return None


def to_nav(view, x, y):
    p = view['projection']
    return p['originY'] - x * p['width'], p['originX'] - y * p['height']


def area_rect(view, area):
    cx, cz = to_nav(view, area['x'], area['y'])
    b = area.get('bounds')
    if area.get('precision') == 'spawn' or not b:
        return [cx - SPAWN_RADIUS, cz - SPAWN_RADIUS, cx + SPAWN_RADIUS, cz + SPAWN_RADIUS]
    ax, az = to_nav(view, b['minX'], b['minY'])
    bx, bz = to_nav(view, b['maxX'], b['maxY'])
    x0, x1 = min(ax, bx) - CLUSTER_MARGIN, max(ax, bx) + CLUSTER_MARGIN
    z0, z1 = min(az, bz) - CLUSTER_MARGIN, max(az, bz) + CLUSTER_MARGIN
    return [max(x0, cx - MAX_HALF), max(z0, cz - MAX_HALF), min(x1, cx + MAX_HALF), min(z1, cz + MAX_HALF)]


def select(polys, rects):
    """Polygon indices whose center lies in any rectangle."""
    buckets = collections.defaultdict(list)
    for r in rects:
        for cx in range(math.floor(r[0] / net.CELL), math.floor(r[2] / net.CELL) + 1):
            for cz in range(math.floor(r[1] / net.CELL), math.floor(r[3] / net.CELL) + 1):
                buckets[(cx, cz)].append(r)
    chosen = set()
    for i, (x, _, z) in enumerate(polys.center):
        for r in buckets.get((math.floor(x / net.CELL), math.floor(z / net.CELL)), ()):
            if r[0] <= x <= r[2] and r[1] <= z <= r[3]:
                chosen.add(i); break
    return chosen


def connect_to_nodes(polys, chosen, reps):
    """Add, per patch cell, the in-cell polygons joining each chosen piece to a node."""
    cells = collections.defaultdict(set)
    for i in chosen:
        cells[polys.cell[i]].add(i)
    rep_cells = collections.defaultdict(list)
    for r in reps:
        rep_cells[polys.cell[r]].append(r)
    added = set()
    for cell, members in cells.items():
        for rep in rep_cells.get(cell, ()):
            dist, parent = net.confined_dijkstra(polys, rep, {cell})
            if not any(m in dist for m in members):
                continue
            added.add(rep)
            nearest = min((m for m in members if m in dist), key=lambda m: dist[m])
            for step in net.corridor(parent, nearest):
                added.add(step[0])
        # Reverse direction: paths from the piece back to the node, for exits.
    return chosen | added


PATCH_UNITS = 1024.0  # vertex units per yard; well inside the loader's .002 yd tolerances
MAX_PATCH_FILE = 131072
NL = chr(10)
TOC = ('## Interface: 16001' + NL + '## Title: RikUI Road Patches %d-%d' + NL + '## AllowLoadGameType: camelot' + NL
       + '## Dependencies: RikUI' + NL + '## LoadOnDemand: 1' + NL + NL)
PATCH_CALL = 'RikUI.QuestPlanner.Roads.Patch(%s,%d,%d,%d,%d,%d,[[%s]],[[%s]])' + NL


def pq(value):
    return int(round(value * PATCH_UNITS))


def encode_cell(polys, members, kept):
    """Binary patch for one cell: int32 vertices (x, z relative to the cell, y absolute),
    then polygons (id, vertex refs, portals to kept polygons with endpoint refs)."""
    any_member = next(iter(members))
    ox, oz = (c * net.CELL for c in polys.cell[any_member])
    vertex_index, vertices = {}, bytearray()
    def vertex(p):
        key = (pq(p[0] - ox), pq(p[2] - oz), pq(p[1]))
        if key not in vertex_index:
            vertex_index[key] = len(vertex_index)
            vertices.extend(struct.pack('<iii', *key))
        return vertex_index[key]
    records, portal_count = bytearray(), 0
    for i in sorted(members):
        points = polys.points[i]
        portals = [e for e in polys.edges[i] if e[0] in kept]
        need(3 <= len(points) <= 6 and len(portals) <= 32, 'patch polygon shape')
        gid = getattr(polys, 'gid', None)
        records.extend(struct.pack('<IB', gid[i] if gid else i + 1, len(points)))
        for p in points:
            records.extend(struct.pack('<H', vertex(p)))
        records.extend(struct.pack('<B', len(portals)))
        for target, left, right in portals:
            records.extend(struct.pack('<IHH', gid[target] if gid else target + 1, vertex(left), vertex(right)))
        portal_count += len(portals)
    need(len(vertex_index) <= 65535, 'patch vertex count')
    return dict(vertices=bytes(vertices), vertexCount=len(vertex_index), records=bytes(records),
                polygons=len(members), portals=portal_count, origin=[ox, oz])


def build_patches(polys, reps, rects):
    """Returns {cell: encoded patch} for every network cell touched by a quest area."""
    chosen = select(polys, rects)
    kept = connect_to_nodes(polys, chosen, reps)
    by_cell = collections.defaultdict(set)
    for i in kept:
        by_cell[polys.cell[i]].add(i)
    patches = {}
    for cell, members in by_cell.items():
        need(len(members) <= MAX_PATCH_POLYGONS, 'patch polygon bound')
        patches[cell] = encode_cell(polys, members, kept)
    return patches, len(chosen), len(kept)


def patch_files(world, revision, patches, lua, encode):
    """Group cell patches into LoadOnDemand addons; returns files and a cell index stream."""
    files, rows, addon, body, names = {}, [], 1, [], []
    def flush():
        nonlocal addon, body, names
        if not body:
            return
        name = 'RikUIQuestRoads_W%d_P%03d' % (world, addon)
        for number, text in enumerate(body, 1):
            file = 'patch-%03d.lua' % number; names.append(file)
            files[name + '/' + file] = text.encode()
        toc = TOC % (world, addon) + NL.join(names) + NL
        files[name + '/' + name + '.toc'] = toc.encode()
        addon, body, names = addon + 1, [], []
    size = 0
    for cell in sorted(patches):
        p = patches[cell]
        key = net.cell_key(*cell)
        text = PATCH_CALL % (
            lua(revision), key, p['vertexCount'], p['polygons'], p['portals'], len(p['records']),
            encode(p['vertices']), encode(p['records']))
        need(len(text) <= MAX_PATCH_FILE * 4, 'patch cell file bound')
        if body and size + len(text) > MAX_PATCH_FILE:
            flush(); size = 0
        body.append(text); size += len(text)
        rows.append((key, addon, p['polygons'], p['portals']))
    flush()
    stream = b''.join(struct.pack('<IHHH', k, a, min(n, 65535), min(m, 65535)) for k, a, n, m in rows)
    return files, (stream, 10, len(rows))
