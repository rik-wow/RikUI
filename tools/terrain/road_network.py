"""Compile a sparse, road-preferring walk network from admitted world batches.

Every walkable 64-yard cell piece (a connected polygon component inside one
bake grid cell) becomes one node. Nodes in neighbouring cells are joined by the
shortest directed polygon path confined to the 3x3 cells around the source,
string-pulled through its portals. Only the pulled corners ship, never polygon
witnesses, so the network stays a few MB per continent. Road texture coverage
discounts cost so routes follow roads where they exist; it never adds or removes
walkable connections. Output is modeled, not native-verified.
"""
import argparse, base64, collections, concurrent.futures, heapq, json, math, pathlib, random, struct, time
import road_textures as roads
import world_export_graph as graph
import world_projection as projection
import world_stitch as stitch
from world_source import canonical, sha, need

FORMAT = 'rikui-road-network-v1'
CELL_FACTOR = 2  # bake grid cells (64 yd) per network cell
CELL = 64.0 * CELL_FACTOR
QUARTER = 4.0  # stored units per yard
ROAD_BONUS = 0.4  # cost multiplier on fully road terrain is 1 - ROAD_BONUS
ROAD_NODE = 0.5  # polygons at or above this road fraction are preferred as nodes
CHUNK_CHARS = 32000
MAX_NODES = 1 << 22
MIN_GROUP_NODES = 16  # smaller disconnected node groups are dropped as unusable islands
MAX_POINT_OFFSET = 32767
SIMPLIFY_YARDS = 1.5  # polyline corners closer than this to the straight line are dropped
REDUNDANT_SLACK = 1.02  # an edge is redundant if a two-hop path costs at most 2% more


def cell_of(key):
    _, gx, gz, _, _ = stitch.key(key)
    return gx // CELL_FACTOR, gz // CELL_FACTOR


def polygon_id(key):
    """Stable 1-based polygon ID from its bake key (64-yd grid cell and index)."""
    _, gx, gz, layer, poly = stitch.key(key)
    need(layer == 0 and poly < 1024 and -512 <= gx < 512 and -512 <= gz < 512, 'polygon key range')
    return ((gx + 512) * 1024 + (gz + 512)) * 1024 + poly + 1


class Polygons:
    """Compact owned-polygon graph for one world."""
    def __init__(self, batches, world, lookup):
        rows = {k: p for b in batches for k, p in b['polygons'].items()}
        self.keys = sorted(rows, key=stitch.key)
        index = {k: i for i, k in enumerate(self.keys)}
        self.center, self.cell, self.road, self.edges, self.points, self.gid = [], [], [], [], [], []
        self.kept = set()
        for key in self.keys:
            row = rows[key]
            self.center.append(tuple(float(v) for v in row['center']))
            self.points.append([tuple(map(float, p)) for p in row['points']])
            self.cell.append(cell_of(key))
            self.gid.append(polygon_id(key))
            samples = [row['center']] + row['points']
            self.road.append(sum(lookup.fraction(p[0], p[2]) for p in samples) / len(samples))
            self.edges.append([(index[e['to']], tuple(map(float, e['left'])), tuple(map(float, e['right'])))
                               for e in row['portals'] if e['to'] in index])
        self.by_cell = collections.defaultdict(list)
        for i, c in enumerate(self.cell):
            self.by_cell[c].append(i)

    def step_cost(self, i, j, left, right):
        mid = tuple((a + b) / 2 for a, b in zip(left, right))
        length = math.dist(self.center[i], mid) + math.dist(mid, self.center[j])
        road = (self.road[i] + self.road[j]) / 2
        return length * (1 - ROAD_BONUS * road)


def components(polys):
    """Undirected connected pieces of each cell; returns list of polygon lists."""
    reverse = collections.defaultdict(list)
    for i, edges in enumerate(polys.edges):
        for j, _, _ in edges:
            reverse[j].append(i)
    seen, pieces = set(), []
    for cell in sorted(polys.by_cell):
        for start in polys.by_cell[cell]:
            if start in seen:
                continue
            piece, stack = [], [start]
            seen.add(start)
            while stack:
                i = stack.pop(); piece.append(i)
                for j in [e[0] for e in polys.edges[i]] + reverse[i]:
                    if j not in seen and polys.cell[j] == cell:
                        seen.add(j); stack.append(j)
            pieces.append(sorted(piece))
    return pieces


def representative(polys, piece):
    cx = sum(polys.center[i][0] for i in piece) / len(piece)
    cz = sum(polys.center[i][2] for i in piece) / len(piece)
    def score(i):
        on_road = polys.road[i] >= ROAD_NODE
        return (not on_road, math.hypot(polys.center[i][0] - cx, polys.center[i][2] - cz), i)
    return min(piece, key=score)


def confined_dijkstra(polys, source, allowed):
    dist, parent, heap = {source: 0.0}, {source: None}, [(0.0, source)]
    while heap:
        d, i = heapq.heappop(heap)
        if d > dist[i]:
            continue
        for j, left, right in polys.edges[i]:
            if polys.cell[j] not in allowed:
                continue
            nd = d + polys.step_cost(i, j, left, right)
            if nd < dist.get(j, math.inf):
                dist[j], parent[j] = nd, (i, left, right)
                heapq.heappush(heap, (nd, j))
    return dist, parent


def corridor(parent, target):
    steps = []
    while parent[target] is not None:
        prior, left, right = parent[target]
        steps.append((prior, target, left, right)); target = prior
    return list(reversed(steps))


def oriented(polys, prior, target, left, right):
    """Return (left, right) as seen when walking from prior into target."""
    a, b = polys.center[prior], polys.center[target]
    dx, dz = b[0] - a[0], b[2] - a[2]
    mx, mz = (left[0] + right[0]) / 2, (left[2] + right[2]) / 2
    side = dx * (left[2] - mz) - dz * (left[0] - mx)
    return (left, right) if side > 0 else (right, left)


def area(a, b, c):
    """Mononen's triarea2 on the XZ plane."""
    ax, az = b[0] - a[0], b[2] - a[2]
    bx, bz = c[0] - a[0], c[2] - a[2]
    return bx * az - ax * bz


def same(a, b):
    return (a[0] - b[0]) ** 2 + (a[2] - b[2]) ** 2 < 1e-12


def funnel(start, goal, portals):
    """Simple stupid funnel (Mononen) over oriented (left, right) portals."""
    gates = [(start, start)] + portals + [(goal, goal)]
    path = [start]
    apex = left = right = start
    ai = li = ri = 0
    i = 1
    while i < len(gates):
        pl, pr = gates[i]
        if area(apex, right, pr) <= 0:
            if same(apex, right) or area(apex, left, pr) > 0:
                right, ri = pr, i
            else:
                path.append(left); apex, ai = left, li
                right, ri = apex, ai
                i = ai + 1; continue
        if area(apex, left, pl) >= 0:
            if same(apex, left) or area(apex, right, pl) < 0:
                left, li = pl, i
            else:
                path.append(right); apex, ai = right, ri
                left, li = apex, ai
                i = ai + 1; continue
        i += 1
    if not same(path[-1], goal):
        path.append(goal)
    return path


def simplify(points, tolerance=SIMPLIFY_YARDS):
    """Douglas-Peucker on XZ; endpoints kept. Guidance-only tolerance."""
    if len(points) <= 2:
        return list(points)
    a, b = points[0], points[-1]
    dx, dz = b[0] - a[0], b[2] - a[2]
    norm = math.hypot(dx, dz)
    def gap(p):
        if norm < 1e-9:
            return math.hypot(p[0] - a[0], p[2] - a[2])
        return abs(dx * (p[2] - a[2]) - dz * (p[0] - a[0])) / norm
    index, worst = max(((i, gap(p)) for i, p in enumerate(points[1:-1], 1)), key=lambda t: t[1])
    if worst <= tolerance:
        return [a, b]
    return simplify(points[:index + 1], tolerance)[:-1] + simplify(points[index:], tolerance)


def prune_redundant(edges, slack=REDUNDANT_SLACK):
    """Drop u->v when some u->w->v costs at most slack times as much."""
    costs = [{m: cost for m, cost, *_ in es} for es in edges]
    pruned = []
    for n, es in enumerate(edges):
        keep = []
        for m, cost, length, corners in es:
            detour = any(w != m and m in costs[w] and c + costs[w][m] <= cost * slack for w, c in costs[n].items())
            if not detour:
                keep.append((m, cost, length, corners))
        pruned.append(keep)
    return pruned


def weighted_length(points, lookup):
    length = cost = 0.0
    for a, b in zip(points, points[1:]):
        segment = math.dist(a, b)
        samples = [tuple(a[k] + (b[k] - a[k]) * q for k in range(3)) for q in (.25, .5, .75)]
        road = sum(lookup.fraction(p[0], p[2]) for p in samples) / 3
        length += segment; cost += segment * (1 - ROAD_BONUS * road)
    return length, cost


def build(polys, lookup, log=print):
    pieces = components(polys)
    reps = [representative(polys, piece) for piece in pieces]
    node_of = {r: n for n, r in enumerate(reps)}
    node_cells = collections.defaultdict(list)
    for n, r in enumerate(reps):
        node_cells[polys.cell[r]].append(n)
    edges = [[] for _ in reps]
    started = time.monotonic()
    for n, rep in enumerate(reps):
        cx, cz = polys.cell[rep]
        allowed = {(cx + dx, cz + dz) for dx in (-1, 0, 1) for dz in (-1, 0, 1)}
        dist, parent = confined_dijkstra(polys, rep, allowed)
        for cell in allowed:
            for m in node_cells.get(cell, ()):
                target = reps[m]
                if m == n or target not in dist:
                    continue
                steps = corridor(parent, target)
                if any(node_of.get(s[1]) is not None and s[1] != target for s in steps):
                    continue  # passes through another node; that pair of edges covers it
                gates = [oriented(polys, p, t, l, r) for p, t, l, r in steps]
                points = simplify(funnel(polys.center[rep], polys.center[target], gates))
                length, cost = weighted_length(points, lookup)
                edges[n].append((m, cost, length, points[1:-1]))
        if n % 20000 == 0 and n:
            log('nodes %d/%d %.0fs' % (n, len(reps), time.monotonic() - started))
    return reps, edges


def prune_islands(reps, edges, minimum, keep=frozenset()):
    """Drop node groups smaller than minimum unless they hold a required node.

    Tiny disconnected pieces (rock tops, roofs, water-cut slivers) can never be
    part of a useful route. Returns remapped (reps, edges, kept old indices).
    """
    adj = collections.defaultdict(set)
    for n, es in enumerate(edges):
        for m, *_ in es:
            adj[n].add(m); adj[m].add(n)
    seen, kept = set(), []
    for start in range(len(reps)):
        if start in seen:
            continue
        group, stack = [], [start]
        seen.add(start)
        while stack:
            n = stack.pop(); group.append(n)
            for m in adj[n]:
                if m not in seen:
                    seen.add(m); stack.append(m)
        if len(group) >= minimum or keep.intersection(group):
            kept.extend(group)
    kept.sort()
    remap = {old: new for new, old in enumerate(kept)}
    new_edges = [[(remap[m], *rest) for m, *rest in edges[old]] for old in kept]
    return [reps[old] for old in kept], new_edges, kept


def q(value):
    return int(round(value * QUARTER))


def node_info(polys, reps):
    """(polygon ID, center, cell, road) per node: everything packing needs."""
    return [(polys.gid[r], polys.center[r], polys.cell[r], polys.road[r]) for r in reps]


def pack(infos, edges):
    """Streams: nodes 13 B, offsets 4 B, edges 8 B (target, cost, length, corner count), points 4 B (dx, dz)."""
    nodes, offsets, rows, points, cells = bytearray(), bytearray(), bytearray(), bytearray(), []
    for n, (_, center, cell, road) in enumerate(infos):
        x, y, z = center
        nodes += struct.pack('<iiiB', q(x), q(z), q(y), min(255, int(round(road * 255))))
        cells.append((cell_key(*cell), n + 1))
    count = 0
    for n, info in enumerate(infos):
        offsets += struct.pack('<I', count)
        origin = info[1]
        for m, cost, length, corners in sorted(edges[n], key=lambda e: e[0]):
            need(q(cost) <= 65535 and q(length) <= 65535 and len(corners) <= 255, 'road edge bound')
            need(m + 1 < 1 << 24, 'road node index bound')
            rows += struct.pack('<I', m + 1)[:3] + struct.pack('<HHB', q(cost), q(length), len(corners))
            for p in corners:
                d = (q(p[0] - origin[0]), q(p[2] - origin[2]))
                need(all(abs(v) <= MAX_POINT_OFFSET for v in d), 'road polyline offset bound')
                points += struct.pack('<hh', *d)
            count += 1
    offsets += struct.pack('<I', count)
    cells.sort()
    cell_bytes = b''.join(struct.pack('<II', k, n) for k, n in cells)
    rep_bytes = b''.join(struct.pack('<I', info[0]) for info in infos)
    return dict(nodes=(bytes(nodes), 13, len(infos)), offsets=(bytes(offsets), 4, len(infos) + 1),
                edges=(bytes(rows), 8, count), points=(bytes(points), 4, len(points) // 4),
                cells=(cell_bytes, 8, len(cells)), reps=(rep_bytes, 4, len(infos)))


def cell_key(cx, cz):
    need(-2048 <= cx < 2048 and -2048 <= cz < 2048, 'road cell range')
    return (cx + 2048) * 4096 + (cz + 2048)


def lua(value):
    import compile_backbone
    return compile_backbone.lua(value)


def encode_streams(streams):
    encoded, specs = {}, {}
    for name, (raw, stride, count) in sorted(streams.items()):
        need(len(raw) == stride * count, 'road stream layout')
        text = base64.b85encode(raw + b'\0' * ((-len(raw)) % 4)).decode('ascii')
        need(']' not in text, 'road stream literal')
        pages = [text[i:i + CHUNK_CHARS] for i in range(0, len(text), CHUNK_CHARS)] or ['']
        specs[name] = dict(bytes=len(raw), stride=stride, count=count, chunkChars=CHUNK_CHARS, parts=len(pages),
                           rawSHA256=sha(raw), encodedSHA256=sha(text.encode('ascii')))
        encoded[name] = pages
    return encoded, specs


def addon_files(world, catalog, encoded):
    addon = 'RikUIQuestRoads_W%d' % world
    files, names = {}, []
    for name, pages in sorted(encoded.items()):
        for number, page in enumerate(pages, 1):
            if not page:
                continue
            file = 'stream-%s-%03d.lua' % (name, number); names.append(file)
            body = 'RikUI.QuestPlanner.Roads.Page(%s,%s,%d,[[%s]])\n' % (lua(catalog['revision']), lua(name), number, page)
            files[addon + '/' + file] = body.encode()
    files[addon + '/catalog.lua'] = ('RikUI.QuestPlanner.Roads.Install(' + lua(catalog) + ')\n').encode()
    toc = ('## Interface: 16001\n## Title: RikUI Roads %d\n## AllowLoadGameType: camelot\n## Dependencies: RikUI\n'
           '## LoadOnDemand: 1\n\ncatalog.lua\n' % world) + '\n'.join(names) + '\n'
    files[addon + '/' + addon + '.toc'] = toc.encode()
    return files


def index_files(worlds, source_directory):
    """Always-loaded index: which LoadOnDemand addon serves which map views."""
    rows = [dict(worldMapID=w['worldMapID'], revision=w['revision'], addon='RikUIQuestRoads_W%d' % w['worldMapID'],
                 views=[dict(uiMapID=v['uiMapID'], projection=v['projection'], validUIRectangle=v['validUIRectangle'])
                        for v in views(source_directory, w['worldMapID'])]) for w in worlds]
    index = dict(format='rikui-road-index-v1', identity=graph.RUNTIME_IDENTITY, worlds=rows)
    toc = '## Interface: 16001\n## Title: RikUI Roads\n## AllowLoadGameType: camelot\n## Dependencies: RikUI\n\nindex.lua\n'
    return {'RikUIQuestRoads/index.lua': ('RikUI.QuestPlanner.Roads.InstallIndex(' + lua(index) + ')\n').encode(),
            'RikUIQuestRoads/RikUIQuestRoads.toc': toc.encode()}


def views(source_directory, world):
    catalog = projection.Catalog(source_directory)
    rows = [graph.view_record(a) for a in catalog.assignments if a.world_map_id == world and a.supported]
    return sorted(rows, key=lambda r: r['assignmentID'])


def b85(raw):
    text = base64.b85encode(raw + b'\0' * ((-len(raw)) % 4)).decode('ascii')
    need(']' not in text, 'road stream literal')
    return text


def compile_world(admitted, world, lookup, source_directory, rects=(), log=print, minimum=MIN_GROUP_NODES):
    """Single-process path, kept for small inputs and tests."""
    import quest_pockets
    batches = [b for ns, b in sorted(admitted['batches'].items()) if ns[0] == world and b['polygons']]
    if not batches:
        return None  # every baked batch of this world is empty or failed
    polys = Polygons(batches, world, lookup)
    sources = [dict(namespace=list(b['namespace']), manifestSHA256=b['sha256']) for b in batches]
    def builder():
        reps, edges = build(polys, lookup, log)
        return node_info(polys, reps), edges, len(polys.keys)
    def patcher(infos):
        if not rects:
            return {}, 0, 0
        local = {g: i for i, g in enumerate(polys.gid)}
        return quest_pockets.build_patches(polys, [local[info[0]] for info in infos], rects)
    return finish_world(sources, world, source_directory, admitted['inputSHA256'], len(rects), builder, patcher, log, minimum)


def finish_world(sources, world, source_directory, input_sha, quests, builder, patcher, log=print, minimum=MIN_GROUP_NODES):
    """builder() -> (node infos, edges, polygon count); patcher(infos) -> (patches, chosen, kept)."""
    import quest_pockets
    started = time.monotonic()
    reps, edges, polygon_count = builder()
    log('world %d polygons %d' % (world, polygon_count))
    log('world %d network search %.0fs' % (world, time.monotonic() - started))
    edges = prune_redundant(edges)
    before = len(reps)
    reps, edges, _ = prune_islands(reps, edges, minimum)
    log('world %d nodes %d kept of %d' % (world, len(reps), before))
    if not reps:
        return None  # nothing routable survives island pruning
    need(len(reps) <= MAX_NODES, 'road node bound')
    streams = pack(reps, edges)
    started = time.monotonic()
    patches, chosen, kept = patcher(reps)
    log('world %d patches %d cells, %d quest polygons, %d kept, %.0fs' % (world, len(patches), chosen, kept, time.monotonic() - started))
    placeholder_files, patch_stream = quest_pockets.patch_files(world, '0' * 64, patches, lua, b85)
    streams['patches'] = patch_stream
    encoded, specs = encode_streams(streams)
    catalog = dict(format=FORMAT, identity=graph.RUNTIME_IDENTITY, worldMapID=world, cellYards=CELL,
                   unitsPerYard=QUARTER, roadBonus=ROAD_BONUS, patchUnitsPerYard=quest_pockets.PATCH_UNITS,
                   counts=dict(nodes=len(reps), edges=sum(map(len, edges)), points=streams['points'][2],
                               polygons=polygon_count, patchCells=len(patches), patchPolygons=kept),
                   streams=specs, views=views(source_directory, world), sourceSHA256=sha(canonical(sources)),
                   inputSHA256=input_sha, quests=quests, nativeVerified=False)
    catalog['revision'] = sha(canonical(catalog))
    patch_addons, _ = quest_pockets.patch_files(world, catalog['revision'], patches, lua, b85)
    need(len(patch_addons) == len(placeholder_files), 'patch addon layout changed with revision')
    files = addon_files(world, catalog, encoded)
    files.update(patch_addons)
    return reps, edges, catalog, files


def quest_rects(path, expected, source_directory, policy=None):
    import quest_pockets
    if policy:
        quest_pockets.SPAWN_RADIUS, quest_pockets.CLUSTER_MARGIN, quest_pockets.MAX_HALF = policy
    raw = pathlib.Path(path).read_bytes()
    need(expected and sha(raw) == expected, 'semantic quest corpus hash')
    catalog = projection.Catalog(source_directory)
    by_map = collections.defaultdict(list)
    for assignment in catalog.assignments:
        if assignment.supported:
            view = graph.view_record(assignment)
            by_map[view['uiMapID']].append(view)
    rects = collections.defaultdict(list)
    for world, rect, _ in quest_pockets.quest_areas(json.loads(raw), by_map):
        rects[world].append(rect)
    return rects


def road_parallel_workers():
    import os
    return os.cpu_count() or 1


def run_directories(paths):
    """Bake run directories: each path is a run, or a root holding runs."""
    runs = []
    for path in map(pathlib.Path, paths):
        if (path / 'plan.json').is_file():
            runs.append(str(path))
        else:
            runs.extend(str(child) for child in sorted(path.iterdir()) if (child / 'plan.json').is_file())
    need(runs, 'no bake runs found')
    return runs


def capture(paths, output):
    raw = canonical(graph.capture(run_directories(paths)))
    with pathlib.Path(output).open('xb') as handle:
        handle.write(raw)
    print(json.dumps(dict(input=output, sha256=sha(raw))))


def compile_serial(args):
    rects = quest_rects(args.semantic_quests, args.semantic_sha256, args.source_directory) if args.semantic_quests else {}
    admitted = graph.load_input(args.input, args.expected_sha256, args.source_directory)
    for world in args.world:
        started = time.monotonic()
        yield world, started, compile_world(admitted, world, roads.RoadLookup(args.road_rasters, world),
                                            args.source_directory, rects.get(world, ()))


def compile_parallel(args, workers):
    """Every heavy step runs in worker processes; see road_parallel.py."""
    import road_parallel
    started = time.monotonic()
    with concurrent.futures.ProcessPoolExecutor(max_workers=workers) as pool:
        rect_job = pool.submit(quest_rects, args.semantic_quests, args.semantic_sha256, args.source_directory,
                               patch_policy()) if args.semantic_quests else None
        cache_root = pathlib.Path(args.output).parent / 'road-network-cache'
        batches, sources = road_parallel.prepare(args.input, args.expected_sha256, args.road_rasters, cache_root, pool)
        rects = rect_job.result() if rect_job else {}
        road_parallel.log('prepare', started)
        for world in args.world:
            started = time.monotonic()
            if world not in batches:
                yield world, started, None
                continue
            world_rects = rects.get(world, ())
            builder = lambda w=world: road_parallel.build(batches[w], args.road_rasters, w, pool)
            patcher = lambda infos, w=world, r=world_rects: road_parallel.patches(batches[w], infos, r, pool)
            yield world, started, finish_world(sources[world], world, args.source_directory, args.expected_sha256,
                                               len(world_rects), builder, patcher)


def patch_policy():
    import quest_pockets
    return (quest_pockets.SPAWN_RADIUS, quest_pockets.CLUSTER_MARGIN, quest_pockets.MAX_HALF)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capture', nargs='+', help='bake runs or roots of runs; writes --output as network input')
    p.add_argument('--input')
    p.add_argument('--expected-sha256')
    p.add_argument('--source-directory')
    p.add_argument('--road-rasters')
    p.add_argument('--world', type=int, action='append')
    p.add_argument('--output', required=True)
    p.add_argument('--semantic-quests', help='corpus audit/semantic-quests.json; enables quest patches')
    p.add_argument('--semantic-sha256')
    p.add_argument('--workers', type=int, help='processes for loading and searching (default: all logical cores; 1 = serial)')
    p.add_argument('--patch-spawn-radius', type=float)
    p.add_argument('--patch-margin', type=float)
    p.add_argument('--patch-max-half', type=float)
    args = p.parse_args()
    if args.capture:
        return capture(args.capture, args.output)
    need(args.input and args.expected_sha256 and args.source_directory and args.road_rasters and args.world,
         'network compile arguments')
    output = pathlib.Path(args.output)
    need(not output.exists(), 'road network output must be new')
    import quest_pockets
    for name, attr in (('patch_spawn_radius', 'SPAWN_RADIUS'), ('patch_margin', 'CLUSTER_MARGIN'), ('patch_max_half', 'MAX_HALF')):
        if getattr(args, name) is not None:
            setattr(quest_pockets, attr, getattr(args, name))
    workers = args.workers or road_parallel_workers()
    policy = dict(spawnRadius=quest_pockets.SPAWN_RADIUS, clusterMargin=quest_pockets.CLUSTER_MARGIN, maxHalf=quest_pockets.MAX_HALF)
    files, report = {}, dict(format='rikui-road-network-receipt-v1', inputSHA256=args.expected_sha256,
                             semanticSHA256=args.semantic_sha256, patchPolicy=policy,
                             compilerSHA256=sha(pathlib.Path(__file__).read_bytes()), worlds=[], nativeVerified=False)
    if workers > 1:
        compiled = compile_parallel(args, workers)
    else:
        compiled = compile_serial(args)
    for world, started, result in compiled:
        if result is None:
            report.setdefault('skipped', []).append(dict(worldMapID=world, reason='no routable node group'))
            print(json.dumps(report['skipped'][-1]), flush=True)
            continue
        _, _, catalog, world_files = result
        files.update(world_files)
        report['worlds'].append(dict(worldMapID=world, revision=catalog['revision'], counts=catalog['counts'],
                                     addonBytes=sum(len(v) for v in world_files.values()),
                                     rawBytes=sum(s['bytes'] for s in catalog['streams'].values()),
                                     seconds=round(time.monotonic() - started, 1)))
        print(json.dumps(report['worlds'][-1]), flush=True)
    files.update(index_files(report['worlds'], args.source_directory))
    report['files'] = [dict(path=k, bytes=len(v), sha256=sha(v)) for k, v in sorted(files.items())]
    output.mkdir(parents=True)
    for name, data in files.items():
        target = output / name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    (output / 'road-network-receipt.json').write_bytes(canonical(report))
    print(json.dumps(dict(output=str(output), worlds=[w['worldMapID'] for w in report['worlds']],
                          receiptSHA256=sha((output / 'road-network-receipt.json').read_bytes()))))


if __name__ == '__main__':
    main()
