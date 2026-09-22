"""Measure an exact coarse-graph gateway contraction; this is not a runtime route pack."""
import argparse
import gc
import heapq
import json
import math
from pathlib import Path
import random
import time
import zlib
import compile_quest_terrain as compiler
import terrain_partition as partition


def dijkstra(adjacency, starts, owners=None, region=None):
    distance = dict(starts)
    queue = [(cost, node) for node, cost in starts.items()]
    heapq.heapify(queue)
    parent, visits = {}, 0
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != distance[node]:
            continue
        visits += 1
        for target, weight, edge in adjacency.get(node, ()):
            if owners is not None and owners[target] != region:
                continue
            candidate = cost + weight
            if candidate < distance.get(target, math.inf):
                distance[target] = candidate
                parent[target] = (node, edge)
                heapq.heappush(queue, (candidate, target))
    return distance, parent, visits


def contract(adjacency, owners):
    boundary = set()
    network, local, trees, used_edges = {}, {}, {}, set()
    for node, edges in adjacency.items():
        local.setdefault(owners[node], set())
        for target, weight, edge in edges:
            if owners[node] != owners[target]:
                boundary.update((node, target))
                network.setdefault(node, []).append((target, weight, edge))
                used_edges.add(edge)
    for node in boundary:
        local[owners[node]].add(node)
        network.setdefault(node, [])
    shortcuts, work = 0, 0
    for root in sorted(boundary):
        distances, parents, visits = dijkstra(adjacency, {root: 0}, owners, owners[root])
        work += visits
        selected = {}
        for target in sorted(local[owners[root]] - {root}):
            if target not in distances:
                continue
            network[root].append((target, distances[target], None))
            shortcuts += 1
            cursor = target
            while cursor != root and cursor not in selected:
                prior, edge = parents[cursor]
                selected[cursor] = (prior, edge)
                used_edges.add(edge)
                cursor = prior
        trees[root] = [[node, *selected[node]] for node in sorted(selected)]
    return network, trees, used_edges, boundary, shortcuts, work


def endpoint_search(adjacency, starts, goal, heuristic=None, terminals=None):
    """Goal-terminated A*, optionally with directed edges to a virtual destination."""
    heuristic = heuristic or (lambda node: 0)
    distance = dict(starts)
    queue = [(cost + heuristic(node), cost, node) for node, cost in starts.items()]
    heapq.heapify(queue)
    visits = 0
    while queue:
        _, cost, node = heapq.heappop(queue)
        if cost != distance[node]:
            continue
        visits += 1
        if node == goal:
            return cost, visits
        edges = adjacency.get(node, ())
        if terminals is not None and node in terminals:
            edges = [*edges, (goal, terminals[node], None)]
        for target, weight, _ in edges:
            candidate = cost + weight
            if candidate < distance.get(target, math.inf):
                distance[target] = candidate
                heapq.heappush(queue, (candidate + heuristic(target), candidate, target))
    return math.inf, visits


def endpoint_query(adjacency, reverse, network, owners, centers, start, goal):
    outward, _, first = dijkstra(adjacency, {start: 0}, owners, owners[start])
    inward, _, last = dijkstra(reverse, {goal: 0}, owners, owners[goal])
    starts = {node: cost for node, cost in outward.items() if node in network}
    if goal in outward:
        starts[-1] = outward[goal]
    def heuristic(node):
        return 0 if node == -1 else math.dist(centers[node], centers[goal])
    cost, work = endpoint_search(network, starts, -1, heuristic, inward)
    return cost, first + last + work


def attached_query(adjacency, reverse, network, owners, start, goal):
    outward, _, first_work = dijkstra(adjacency, {start: 0}, owners, owners[start])
    inward, _, last_work = dijkstra(reverse, {goal: 0}, owners, owners[goal])
    starts = {node: cost for node, cost in outward.items() if node in network}
    long_distance, _, global_work = dijkstra(network, starts)
    best = outward.get(goal, math.inf)
    for node, cost in inward.items():
        best = min(best, cost + long_distance.get(node, math.inf))
    return best, first_work + last_work + global_work


def benchmark(manifest, expected, audit_path, output, samples=64):
    started = time.perf_counter()
    meta, shards, receipt = compiler.validate(manifest, expected, regional=True)
    nodes = partition.normalize([node for shard in shards for node in shard["polygons"]])
    del shards
    audit_raw = Path(audit_path).read_bytes()
    audit = json.loads(audit_raw)
    graph_hash = compiler.sha(partition.canonical(dict(metadata=meta, polygons=list(nodes.values()))).encode())
    if graph_hash != audit["graphSha256"]:
        raise ValueError("partition audit does not match the validated source graph")
    owners = {row["id"]: row["region"] for row in audit["polygonOwners"]}
    if set(owners) != set(nodes):
        raise ValueError("partition owner coverage")
    centers = {node: tuple(sum(point[axis] for point in row["points"]) / len(row["points"])
                          for axis in range(3)) for node, row in nodes.items()}
    adjacency, reverse, geometry = {}, {node: [] for node in nodes}, {}
    edge_id = 0
    for node, row in nodes.items():
        adjacency[node] = []
        for portal in row["portals"]:
            edge_id += 1
            target = portal["to"]
            midpoint = tuple((portal["left"][axis] + portal["right"][axis]) / 2 for axis in range(3))
            weight = math.dist(centers[node], midpoint) + math.dist(midpoint, centers[target])
            adjacency[node].append((target, weight, edge_id))
            reverse[target].append((node, weight, edge_id))
            geometry[edge_id] = (node, target, *midpoint)
    del nodes
    gc.collect()
    preparation = time.perf_counter() - started
    started = time.perf_counter()
    network, trees, used_edges, boundary, shortcuts, work = contract(adjacency, owners)
    preprocessing = time.perf_counter() - started
    vertex_ids = set(boundary)
    for edge in used_edges:
        vertex_ids.update(geometry[edge][:2])
    payload = dict(format="rikui-backbone-benchmark-v1", graphSHA256=graph_hash,
                   sourceManifestSHA256=expected, partitionAuditSHA256=compiler.sha(audit_raw),
                   metadata=meta, boundary=sorted(boundary),
                   network={node: [[target, cost] for target, cost, _ in rows]
                            for node, rows in sorted(network.items())},
                   trees=trees, geometry={edge: geometry[edge] for edge in sorted(used_edges)},
                   centers={node: centers[node] for node in sorted(vertex_ids)})
    raw = partition.canonical(payload).encode()
    packed = zlib.compress(raw, 9)
    chooser = random.Random(69913)
    all_ids = sorted(adjacency)
    boundary_ids = sorted(boundary)
    pairs = []
    for index in range(samples):
        pool = boundary_ids if index % 2 else all_ids
        start, goal = chooser.choice(pool), chooser.choice(pool)
        if index % 4 == 0:
            same = [node for node in all_ids if owners[node] == owners[start]]
            goal = chooser.choice(same)
        pairs.append((start, goal))
    comparisons = []
    for index, (start, goal) in enumerate(pairs):
        # The untimed exhaustive oracle also supplies genuinely connected samples.
        original, _, _ = dijkstra(adjacency, {start: 0})
        sample_kind = "random-or-same-region"
        if index % 2:
            goal = chooser.choice(sorted(original))
            sample_kind = "reachable"
        expected_cost = original.get(goal, math.inf)
        heuristic = lambda node: math.dist(centers[node], centers[goal])
        began = time.perf_counter()
        reference_cost, original_work = endpoint_search(adjacency, {start: 0}, goal, heuristic)
        original_seconds = time.perf_counter() - began
        if reference_cost != expected_cost and not math.isclose(reference_cost, expected_cost, rel_tol=1e-10):
            raise AssertionError("goal-terminated A* disagrees with exhaustive Dijkstra")
        began = time.perf_counter()
        actual_cost, actual_work = endpoint_query(adjacency, reverse, network, owners, centers, start, goal)
        elapsed = time.perf_counter() - began
        if math.isfinite(expected_cost) != math.isfinite(actual_cost):
            raise AssertionError(f"reachability changed: {start} -> {goal}")
        if math.isfinite(expected_cost) and abs(expected_cost-actual_cost) > 1e-7*max(1, expected_cost):
            raise AssertionError(f"coarse graph cost changed: {start} -> {goal}")
        comparisons.append(dict(start=start, goal=goal, sampleKind=sample_kind, reachable=math.isfinite(actual_cost),
                                cost=actual_cost if math.isfinite(actual_cost) else None,
                                originalVisits=original_work, backboneVisits=actual_work,
                                originalSeconds=original_seconds, backboneSeconds=elapsed))
    report = dict(format="rikui-backbone-comparison-v2", search="goal-terminated Euclidean A*; full local attachments",
                  sourceManifestSHA256=expected,
                  graphSHA256=graph_hash, polygonNodes=len(adjacency), gatewayNodes=len(boundary),
                  originalDirectedEdges=edge_id, directedBackboneEdges=sum(map(len, network.values())),
                  localShortcuts=shortcuts, retainedGeometryEdges=len(used_edges),
                  witnessTreeEntries=sum(map(len, trees.values())), witnessVertices=len(vertex_ids),
                  payloadJSONBytes=len(raw), experimentalZlibBytes=len(packed),
                  preparationSeconds=preparation, preprocessingSeconds=preprocessing,
                  preprocessingVisits=work, comparisons=comparisons,
                  limitations=["Coarse polygon-center/portal-midpoint costs; no road semantics or splines.",
                               "Exact graph contraction, with directed witness edges; geometry remains the original model.",
                               "Sampled endpoint queries are host tests, not complete native or arbitrary-position acceptance.",
                               "Zlib size is an offline experiment, not an implemented Lua storage or memory claim."])
    output = Path(output).absolute()
    compiler.output_ready(output)
    output.mkdir()
    (output/"backbone.json").write_bytes(raw)
    (output/"backbone.experimental-zlib").write_bytes(packed)
    (output/"report.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    summary = {key: value for key, value in report.items() if key not in ("comparisons", "limitations")}
    summary["queries"] = len(comparisons)
    summary["reachableQueries"] = sum(row["reachable"] for row in comparisons)
    summary["originalQuerySeconds"] = sum(row["originalSeconds"] for row in comparisons)
    summary["backboneQuerySeconds"] = sum(row["backboneSeconds"] for row in comparisons)
    print(json.dumps(summary, sort_keys=True), flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--partition-audit", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--samples", type=int, default=64)
    args = parser.parse_args()
    if not 1 <= args.samples <= 512:
        parser.error("--samples must be 1..512")
    benchmark(args.manifest, args.expected_sha256, args.partition_audit, args.output, args.samples)


if __name__ == "__main__":
    main()
