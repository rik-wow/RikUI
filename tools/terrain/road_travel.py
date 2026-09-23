"""Attach travel stops (flight masters, docks, tram entrances) to a world's road
network and precompute walking costs between them.

Each stop joins the nearest network node within its kind's reach. A dock's
stop is the transport's berth, which sits off the pier, so docks reach
further. Walking costs are network costs (road-weighted yards) from one
stop's node to another's; the runtime adds the short straight leg from the
node to the stop itself.
"""
import heapq, math

REACH = dict(flight=80.0, dock=160.0, tram=80.0, elevator=40.0)


def attach(infos, stops):
    """Returns (attached, missing): attached rows {id, node, yards}; missing rows {id, nearestYards}."""
    points = [(info[1][0], info[1][2]) for info in infos]
    attached, missing = [], []
    for stop in stops:
        x, _, z = stop['point']
        best, node = math.inf, None
        for n, (px, pz) in enumerate(points):
            d = (px - x) ** 2 + (pz - z) ** 2
            if d < best:
                best, node = d, n
        yards = math.sqrt(best)
        if node is not None and yards <= REACH[stop['kind']]:
            attached.append(dict(id=stop['id'], node=node, yards=round(yards, 1)))
        else:
            missing.append(dict(id=stop['id'], nearestYards=None if node is None else round(yards, 1)))
    return attached, missing


def costs_from(args):
    """Dijkstra from one node; returns {target node: cost} for the given targets."""
    edges, source, targets = args
    wanted, found = set(targets), {}
    dist, heap = {source: 0.0}, [(0.0, source)]
    while heap and len(found) < len(wanted):
        d, n = heapq.heappop(heap)
        if d > dist[n]:
            continue
        if n in wanted:
            found[n] = d
        for m, cost, *_ in edges[n]:
            nd = d + cost
            if nd < dist.get(m, math.inf):
                dist[m] = nd
                heapq.heappush(heap, (nd, m))
    return found


def costs_batch(args):
    """costs_from for several sources, so a worker receives the edge list once."""
    edges, sources, targets = args
    return [costs_from((edges, n, targets)) for n in sources]


BATCHES = 32


def walks(edges, attached, mapper=map):
    """[i, j, cost] for every ordered pair of attached stops joined by the network."""
    nodes = sorted({row['node'] for row in attached})
    groups = [nodes[k::BATCHES] for k in range(BATCHES) if nodes[k::BATCHES]]
    results = {}
    for group, found in zip(groups, mapper(costs_batch, [(edges, g, nodes) for g in groups])):
        results.update(zip(group, found))
    rows = []
    for i, a in enumerate(attached):
        reach = results[a['node']]
        for j, b in enumerate(attached):
            if i != j and b['node'] in reach:
                rows.append([i, j, round(reach[b['node']], 1)])
    return rows


def section(infos, edges, stops, mapper=map):
    """Catalog section for one world's stops."""
    attached, missing = attach(infos, stops)
    return dict(stops=[dict(row, node=row['node'] + 1) for row in attached],  # 1-based nodes, like the streams
                walks=[[i + 1, j + 1, cost] for i, j, cost in walks(edges, attached, mapper)],
                missing=missing)
