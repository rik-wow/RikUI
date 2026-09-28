"""Detailed mesh patches around every corpus quest spot.

Quest areas (NPC/object spawns, spawn clusters, objective bounds) from the
compiled Forever corpus become rectangles in navigation coordinates. Baked
polygons select connected pieces inside each road-network cell (one patch per
128-yard cell). Those pieces are retained in full, including their gateway
nodes, plus one ring of pieces joined by existing portals, so open crossings
and nearby approaches remain connected. Other cells and disconnected pieces
outside the quest areas are dropped. Patches are modeled geometry, not verified.
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
    """Keep each quest area's complete in-cell connected piece, including its gateway.

    Keeping only a thin path to a node leaves artificial holes through otherwise
    walkable ground (including frozen lakes). The existing portals still decide
    where movement is possible; one connected approach ring is included.
    """
    pieces = net.components(polys)
    owner = {i: n for n, piece in enumerate(pieces) for i in piece}
    touched = {owner[i] for i in chosen}
    kept = set(touched)
    # Include one connected approach cell so arriving just outside a quest's
    # cell does not force a road detour. Do not expand recursively.
    for i, edges in enumerate(polys.edges):
        for j, _, _ in edges:
            a, b = owner[i], owner[j]
            if a in touched: kept.add(b)
            if b in touched: kept.add(a)
    return {i for n in kept for i in pieces[n]}


PATCH_UNITS = 1024.0  # vertex units per yard; well inside the loader's .002 yd tolerances
MAX_PATCH_FILE = 131072      # soft size of one cell's file; a dense cell may reach 4x
# Cells per LoadOnDemand pack. Patches are the only data left outside the RikUI
# folder, so packs are large: about 16 folders for both continents, each a
# one-time synchronous load of roughly a third of a second (about 20 ms/MiB).
MAX_PATCH_ADDON = 16 * 1048576
NL = chr(10)
TOC = ('## Interface: 16001' + NL + '## Title: RikUI Road Patches %d-%d' + NL + '## AllowLoadGameType: camelot' + NL
       + '## Dependencies: RikUI' + NL + '## LoadOnDemand: 1' + NL + NL)
PATCH_CALL = 'RikUI.QuestPlanner.Roads.Patch2(%s,%d,%d,%d,%d,%d,[[%s]])' + NL
# Streams of the compact cell, in file order, after a header of their eight byte lengths.
COMPACT_STREAMS = ('x', 'z', 'y', 'ids', 'shapes', 'refs', 'targets', 'edges')
EDGE_MIRROR, EDGE_REVERSED, EDGE_FREE = 8, 16, 7


def pq(value):
    return int(round(value * PATCH_UNITS))


def _zigzag(value):
    return value * 2 if value >= 0 else -value * 2 - 1


def _varint(out, value):
    while value >= 128:
        out.append(value % 128 + 128); value //= 128
    out.append(value)


def _records(records, polygons):
    rows, at = [], 0
    for _ in range(polygons):
        ident, count = struct.unpack_from('<IB', records, at); at += 5
        own = struct.unpack_from('<%dH' % count, records, at); at += 2 * count
        portals = records[at]; at += 1
        rows.append((ident, own, [struct.unpack_from('<IHH', records, at + 8 * k) for k in range(portals)]))
        at += 8 * portals
    need(at == len(records), 'patch record length')
    return rows


def compact_cell(cell):
    """The same cell as encode_cell's vertices and records, in a form Deflate packs well.

    Vertex columns and polygon ids are deltas, vertex references count back from the newest
    vertex, and a portal names the polygon edge it lies on (in either direction), or its two
    vertices when it lies on none. A portal whose twin was already
    written by the polygon on the other side names only its edge; the reader finds the target
    from that twin. Nothing is rounded or dropped: expand_cell returns the original bytes.
    """
    count = cell['vertexCount']
    values = struct.unpack('<%di' % (3 * count), cell['vertices'])
    streams = {name: bytearray() for name in COMPACT_STREAMS}
    for column, name in enumerate(('x', 'z', 'y')):
        previous = 0
        for index in range(count):
            current = values[3 * index + column]
            _varint(streams[name], _zigzag(current - previous)); previous = current
    previous, newest, twins = 0, -1, {}
    for ident, own, portals in _records(cell['records'], cell['polygons']):
        need(ident > previous or previous == 0 and ident >= 0, 'patch polygon order')
        _varint(streams['ids'], ident - previous); previous = ident
        streams['shapes'] += bytes((len(own), len(portals)))
        for ref in own:
            if ref == newest + 1:
                streams['refs'].append(0); newest = ref
            else:
                need(ref <= newest, 'patch vertex order')
                _varint(streams['refs'], newest - ref + 1)
        for target, left, right in portals:
            edge = next((k for k in range(len(own)) if own[k] == left and own[(k + 1) % len(own)] == right), None)
            if edge is None:
                edge = next((k + EDGE_REVERSED for k in range(len(own))
                             if own[k] == right and own[(k + 1) % len(own)] == left), None)
            if edge is None:
                _varint(streams['targets'], _zigzag(target - ident))
                streams['edges'] += bytes((EDGE_FREE,)) + struct.pack('<HH', left, right)
                newest = max(newest, left, right)  # such a portal may be a vertex's first use
            elif twins.get((left, right)) == target:
                streams['edges'].append(edge + EDGE_MIRROR)
            else:
                _varint(streams['targets'], _zigzag(target - ident))
                streams['edges'].append(edge)
            twins[(right, left)] = ident
    body = b''.join(bytes(streams[name]) for name in COMPACT_STREAMS)
    return struct.pack('<8I', *(len(streams[name]) for name in COMPACT_STREAMS)) + body


def expand_cell(raw, vertex_count, polygons):
    """Reference reader for compact_cell: returns (vertices, records) as encode_cell wrote them."""
    lengths = struct.unpack_from('<8I', raw, 0)
    need(32 + sum(lengths) == len(raw), 'compact patch length')
    cursors, at = {}, 32
    for name, length in zip(COMPACT_STREAMS, lengths):
        cursors[name] = [at, at + length]; at += length
    def byte(name):
        cursor = cursors[name]
        need(cursor[0] < cursor[1], 'compact patch stream ' + name)
        cursor[0] += 1
        return raw[cursor[0] - 1]
    def varint(name):
        value, scale = 0, 1
        while True:
            part = byte(name)
            value += part % 128 * scale; scale *= 128
            if part < 128:
                return value
    def signed(name):
        value = varint(name)
        return value // 2 if value % 2 == 0 else -(value + 1) // 2
    columns = []
    for name in ('x', 'z', 'y'):
        previous, column = 0, []
        for _ in range(vertex_count):
            previous += signed(name); column.append(previous)
        columns.append(column)
    vertices = b''.join(struct.pack('<iii', *row) for row in zip(*columns))
    records, ident, newest, twins = bytearray(), 0, -1, {}
    for _ in range(polygons):
        ident += varint('ids')
        count, portals = byte('shapes'), byte('shapes')
        own = []
        for _ in range(count):
            back = varint('refs')
            if back == 0:
                newest += 1; own.append(newest)
            else:
                own.append(newest - back + 1)
        records += struct.pack('<IB', ident, count) + struct.pack('<%dH' % count, *own) + bytes((portals,))
        for _ in range(portals):
            edge = byte('edges')
            if edge == EDGE_FREE:
                target = ident + signed('targets')
                left, right = byte('edges') + byte('edges') * 256, byte('edges') + byte('edges') * 256
                newest = max(newest, left, right)
            else:
                reverse = edge >= EDGE_REVERSED
                edge -= EDGE_REVERSED if reverse else 0
                mirror = edge >= EDGE_MIRROR
                edge -= EDGE_MIRROR if mirror else 0
                need(edge < count, 'compact patch edge')
                left, right = own[edge], own[(edge + 1) % count]
                if reverse:
                    left, right = right, left
                target = twins.get((left, right)) if mirror else ident + signed('targets')
                need(target is not None, 'compact patch twin')
            records += struct.pack('<IHH', target, left, right)
            twins[(right, left)] = ident
    need(all(cursor[0] == cursor[1] for cursor in cursors.values()), 'compact patch trailing bytes')
    return vertices, bytes(records)


def deflate(raw):
    """A raw Deflate stream, what C_EncodingUtil's Deflate method and the addon's own reader take."""
    import zlib
    packer = zlib.compressobj(9, zlib.DEFLATED, -15)
    return packer.compress(raw) + packer.flush()


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


def patch_files(world, revision, patches, lua, encode=None):
    """Group cell patches into LoadOnDemand packs of at most MAX_PATCH_ADDON
    bytes; returns files and a cell index stream (cell key -> pack number).
    Each cell is its compact form, Deflate-packed and written as base64 (`encode`
    is the text encoder of the older two-string layout and is no longer used)."""
    import base64
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
        raw = compact_cell(p)
        need(expand_cell(raw, p['vertexCount'], p['polygons']) == (p['vertices'], p['records']), 'compact patch round trip')
        text = PATCH_CALL % (
            lua(revision), key, p['vertexCount'], p['polygons'], p['portals'], len(raw),
            base64.b64encode(deflate(raw)).decode('ascii'))
        need(len(text) <= MAX_PATCH_FILE * 4, 'patch cell file bound')
        if body and size + len(text) > MAX_PATCH_ADDON:
            flush(); size = 0
        body.append(text); size += len(text)
        rows.append((key, addon, p['polygons'], p['portals']))
    flush()
    stream = b''.join(struct.pack('<IHHH', k, a, min(n, 65535), min(m, 65535)) for k, a, n, m in rows)
    return files, (stream, 10, len(rows))
