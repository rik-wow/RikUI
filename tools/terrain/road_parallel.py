"""Multi-process build for road_network.py. The main process only coordinates.

1. validate: each worker loads one bake batch, checks its receipt and proves
   the seams to its +x/+z neighbours (small results come back).
2. compact: each worker reloads its batch, applies the proven seam endpoints,
   samples road coverage and writes a compact pickle to a cache directory.
   Both steps are skipped when the cache for this input already exists.
3. nodes: each worker loads the cached batches of one stripe of network
   cells (plus a one-cell halo), finds its nodes and edges, and returns only
   those. The main process sorts them into the same order a serial build uses.
4. patches: after island pruning, stripe workers build quest patches the
   same way.
Polygon IDs are derived from bake keys, so no global table is ever built.
"""
import collections, json, os, pathlib, pickle, time
import road_network as net
import road_textures as roads
import world_export_graph as graph
import world_stitch as stitch
from world_source import need

STRIPE_CELLS = 2       # core network-cell columns per stripe task
CELLS_PER_BATCH = 4    # a 512-yard bake batch spans four 128-yard cells


def default_workers():
    return os.cpu_count() or 1


def log(label, started):
    print(json.dumps(dict(phase=label, seconds=round(time.monotonic() - started, 1))), flush=True)


# ---------- 1 + 2: validate and cache ----------

def _validate(args):
    record, neighbours = args
    batch = stitch.load(record['directory'], record['manifestSHA256'])
    receipt = graph.validate_receipt(record, batch)
    links = []
    for other in neighbours:
        proof = stitch.admit(batch, stitch.load(other['directory'], other['manifestSHA256']))
        links.extend(((e['fromKey'], e['to']), (e['left'], e['right'])) for e in proof['directedLinks'])
    tools = receipt['input']
    return (json.dumps(tools['tools'], sort_keys=True), tools['sourceProfileSHA256'], tools['indexSHA256']), links


def _compact(args):
    record, links, present, road_dir, path = args
    batch = stitch.load(record['directory'], record['manifestSHA256'])
    ns = batch['namespace']
    lookup = roads.RoadLookup(road_dir, ns[0])
    liquids = batch['manifest'].get('liquids', [])
    water = net.WaterLookup(liquids)
    rows = []
    for key, row in sorted(batch['polygons'].items(), key=lambda kv: stitch.key(kv[0])):
        if water.submerged(*row['center']):
            continue  # lake and sea floor; routes swim on the surface above
        portals = []
        for edge in row['portals']:
            left, right = edge['left'], edge['right']
            if stitch.owner(edge['to']) != ns:
                link = links.get((key, edge['to']))
                if link is None:
                    need(stitch.owner(edge['to']) not in present, 'unproven cross-batch edge')
                    continue  # neighbour batch absent: coverage frontier, no edge
                left, right = link
            portals.append((net.polygon_id(edge['to']), tuple(map(float, left)), tuple(map(float, right))))
        samples = [row['center']] + row['points']
        road = sum(lookup.fraction(p[0], p[2]) for p in samples) / len(samples)
        rows.append((net.polygon_id(key), tuple(map(float, row['center'])), [tuple(map(float, p)) for p in row['points']],
                     road, portals, net.cell_of(key), water.at(*row['center'])))
    temp = pathlib.Path(str(path) + '.part')
    temp.write_bytes(pickle.dumps(dict(rows=rows, liquids=liquids), protocol=pickle.HIGHEST_PROTOCOL))
    temp.replace(path)
    return len(rows)


def prepare(input_path, expected, road_dir, cache_root, pool):
    """Validate and cache every batch once per input. Returns world -> {(bx, bz): cache file}, sources, polygon totals."""
    raw = graph.read(input_path, expected, 8 * 1024 * 1024)
    doc = json.loads(raw)
    need(doc.get('format') == 'rikui-world-export-input-v1' and doc.get('identity') == graph.RUNTIME_IDENTITY, 'world export identity')
    cache = pathlib.Path(cache_root) / ('input-' + expected[:16])
    by_ns = {}
    for record in doc['batches']:
        manifest = json.loads(pathlib.Path(record['directory'], 'manifest.json').read_bytes())
        ns = (manifest['worldMapID'], *manifest['job']['batchGrid'])
        need(ns not in by_ns, 'duplicate physical batch')
        by_ns[ns] = record
    done = cache / 'complete.json'
    started = time.monotonic()
    if not done.is_file():
        cache.mkdir(parents=True, exist_ok=True)
        tasks = [(record, [by_ns[n] for n in ((w, x + 1, z), (w, x, z + 1)) if n in by_ns])
                 for (w, x, z), record in sorted(by_ns.items())]
        links, generation = {}, None
        for current, pairs in pool.map(_validate, tasks, chunksize=2):
            need(generation in (None, current), 'mixed decoder/source/index generations')
            generation = current
            links.update(pairs)
        import world_bake
        need(json.loads(generation[0]) == world_bake.hashes(), 'bake tools changed; regenerate affected batches')
        log('validate-and-seams', started); started = time.monotonic()
        owned = collections.defaultdict(dict)
        for k, v in links.items():
            owned[stitch.owner(k[0])][k] = v
        present = set(by_ns)
        args = [(record, owned.get(ns, {}), present, road_dir, cache / ('w%d_%d_%d.pkl' % ns)) for ns, record in sorted(by_ns.items())]
        counts = dict(zip(['%d_%d_%d' % ns for ns in sorted(by_ns)], pool.map(_compact, args, chunksize=2)))
        done.write_text(json.dumps(dict(inputSHA256=expected, roadRasters=str(road_dir), counts=counts)))
        log('compact-cache', started)
    else:
        log('cache-reused', started)
    counts = json.loads(done.read_text())['counts']
    worlds, sources = collections.defaultdict(dict), collections.defaultdict(list)
    for ns, record in sorted(by_ns.items()):
        if counts['%d_%d_%d' % ns]:
            worlds[ns[0]][(ns[1], ns[2])] = str(cache / ('w%d_%d_%d.pkl' % ns))
            sources[ns[0]].append(dict(namespace=list(ns), manifestSHA256=record['manifestSHA256']))
    return worlds, sources


# ---------- stripe loading ----------

class Compact(net.Polygons):
    """Polygons built from cached rows instead of full batch dicts."""
    def __init__(self):  # pylint: disable=super-init-not-called
        self.center, self.cell, self.road, self.edges, self.points, self.gid, self.water = [], [], [], [], [], [], []
        self.kept = set()
        self.by_cell = collections.defaultdict(list)


def load_region(files, lo, hi):
    """Cached polygons whose cell column lies in [lo, hi), ordered by polygon ID."""
    rows, liquids = [], []
    for path in files:
        cached = pickle.loads(pathlib.Path(path).read_bytes())
        rows.extend(r for r in cached['rows'] if lo <= r[5][0] < hi)
        liquids.extend(cached['liquids'])
    rows.sort(key=lambda r: r[0])
    part = Compact()
    part.liquids = liquids
    local = {r[0]: i for i, r in enumerate(rows)}
    for i, (gid, center, points, road, portals, cell, water) in enumerate(rows):
        part.gid.append(gid); part.center.append(center); part.points.append(points); part.road.append(road)
        part.water.append(water)
        part.cell.append(cell); part.by_cell[cell].append(i)
        part.edges.append([(local[t], l, r) for t, l, r in portals if t in local])
    return part


def stripe_tasks(batches):
    """(core_lo, core_hi, cache files covering core plus halo) per stripe of cell columns."""
    columns = sorted({bx for bx, _ in batches})
    lo_cell, hi_cell = columns[0] * CELLS_PER_BATCH, (columns[-1] + 1) * CELLS_PER_BATCH
    tasks = []
    for a in range(lo_cell, hi_cell, STRIPE_CELLS):
        b = min(a + STRIPE_CELLS, hi_cell)
        first, last = (a - 1) // CELLS_PER_BATCH, b // CELLS_PER_BATCH
        files = [path for (bx, _), path in sorted(batches.items()) if first <= bx <= last]
        if files:
            tasks.append((a, b, files))
    return tasks


# ---------- 3: nodes and edges ----------

def _nodes(args):
    core_lo, core_hi, files, road_dir, world = args
    part = load_region(files, core_lo - 1, core_hi + 1)
    lookup = roads.RoadLookup(road_dir, world)
    water = net.WaterLookup(part.liquids)
    pieces = net.components(part)
    reps = [net.representative(part, p) for p in pieces]
    node_cells = collections.defaultdict(list)
    for n, r in enumerate(reps):
        node_cells[part.cell[r]].append(n)
    out = []
    for n, rep in enumerate(reps):
        cx, cz = part.cell[rep]
        if not core_lo <= cx < core_hi:
            continue
        allowed = {(cx + dx, cz + dz) for dx in (-1, 0, 1) for dz in (-1, 0, 1)}
        dist, parent = net.confined_dijkstra(part, rep, allowed)
        found = []
        for cell in allowed:
            for m in node_cells.get(cell, ()):
                target = reps[m]
                if m == n or target not in dist:
                    continue
                steps = net.corridor(parent, target)
                gates = [net.oriented(part, p, t, l, r) for p, t, l, r in steps]
                points = net.simplify(net.funnel(part.center[rep], part.center[target], gates))
                length, cost = net.weighted_length(points, lookup, water)
                found.append((part.gid[target], cost, length, points[1:-1]))
        info = (part.gid[rep], part.center[rep], part.cell[rep], part.road[rep])
        out.append((part.cell[rep], part.gid[min(pieces[n])], info, found))
    polygons = sum(1 for c in part.cell if core_lo <= c[0] < core_hi)
    return out, polygons


def build(batches, road_dir, world, pool):
    """Returns (node infos, edges, polygon count) in serial-build order."""
    tasks = [(a, b, files, road_dir, world) for a, b, files in stripe_tasks(batches)]
    rows, polygons = [], 0
    for chunk, count in pool.map(_nodes, tasks):
        rows.extend(chunk); polygons += count
    rows.sort(key=lambda r: (r[0], r[1]))
    infos = [r[2] for r in rows]
    node = {info[0]: n for n, info in enumerate(infos)}
    edges = [[(node[t], cost, length, corners) for t, cost, length, corners in r[3]] for r in rows]
    return infos, edges, polygons


# ---------- 4: quest patches ----------

def _patches(args):
    import quest_pockets as qp
    core_lo, core_hi, files, rep_ids, rects, policy = args
    qp.SPAWN_RADIUS, qp.CLUSTER_MARGIN, qp.MAX_HALF = policy
    part = load_region(files, core_lo - 1, core_hi + 1)
    reps = [i for i, g in enumerate(part.gid) if g in rep_ids]
    chosen = qp.select(part, rects)
    kept = qp.connect_to_nodes(part, chosen, reps)
    by_cell = collections.defaultdict(set)
    for i in kept:
        by_cell[part.cell[i]].add(i)
    out = {cell: qp.encode_cell(part, members, kept) for cell, members in by_cell.items() if core_lo <= cell[0] < core_hi}
    core = lambda i: core_lo <= part.cell[i][0] < core_hi
    return out, sum(1 for i in chosen if core(i)), sum(1 for i in kept if core(i))


def patches(batches, infos, rects, pool):
    import quest_pockets as qp
    if not rects:
        return {}, 0, 0
    policy = (qp.SPAWN_RADIUS, qp.CLUSTER_MARGIN, qp.MAX_HALF)
    reach = qp.MAX_HALF + qp.SPAWN_RADIUS + qp.CLUSTER_MARGIN
    tasks = []
    for a, b, files in stripe_tasks(batches):
        x0, x1 = (a - 1) * net.CELL - reach, (b + 1) * net.CELL + reach
        mine = [r for r in rects if r[2] >= x0 and r[0] <= x1]
        ids = {info[0] for info in infos if a - 1 <= info[2][0] < b + 1}
        tasks.append((a, b, files, ids, mine, policy))
    result, chosen, kept = {}, 0, 0
    for out, c, k in pool.map(_patches, tasks):
        result.update(out); chosen += c; kept += k
    return result, chosen, kept
