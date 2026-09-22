"""Directed reachability/cost and witness tests for offline hierarchy comparison."""
import math
import unittest
import benchmark_backbone as backbone


class BackboneTests(unittest.TestCase):
    def fixture(self):
        # 1->2->3 crosses SCCs inside A; 3->4 is a one-way region seam.
        # 4<->5 share B; 5<->6 crosses B/C. 7/8 are isolated local floor IDs.
        rows = {1: [(2, 2, 1)], 2: [(3, 1, 2)], 3: [(4, 3, 3)],
                4: [(5, 2, 4)], 5: [(4, 2, 5), (6, 4, 6)],
                6: [(5, 4, 7)], 7: [(8, 0, 8)], 8: []}
        owners = {1: "A", 2: "A", 3: "A", 4: "B", 5: "B", 6: "C", 7: "D", 8: "D"}
        reverse = {node: [] for node in rows}
        for node, edges in rows.items():
            for target, weight, edge in edges:
                reverse[target].append((node, weight, edge))
        return rows, owners, reverse

    def test_every_pair_preserves_directed_cost_with_local_attachments(self):
        rows, owners, reverse = self.fixture()
        network, _, _, boundary, _, _ = backbone.contract(rows, owners)
        self.assertEqual(boundary, {3, 4, 5, 6})
        for start in rows:
            baseline, _, _ = backbone.dijkstra(rows, {start: 0})
            for goal in rows:
                actual, _ = backbone.attached_query(rows, reverse, network, owners, start, goal)
                self.assertEqual(actual, baseline.get(goal, math.inf), (start, goal))
                centers = {node: (0, 0, 0) for node in rows}
                endpoint, _ = backbone.endpoint_query(rows, reverse, network, owners, centers, start, goal)
                direct, _ = backbone.endpoint_search(rows, {start: 0}, goal)
                self.assertEqual(endpoint, actual, (start, goal))
                self.assertEqual(direct, actual, (start, goal))
        self.assertTrue(math.isinf(backbone.attached_query(rows, reverse, network, owners, 6, 1)[0]))
        self.assertEqual(backbone.attached_query(rows, reverse, network, owners, 7, 8)[0], 0)

    def test_witnesses_use_only_forward_local_edges_and_shared_trees(self):
        rows, owners, _ = self.fixture()
        network, trees, used, _, _, _ = backbone.contract(rows, owners)
        edges = {edge: (node, target, weight) for node, values in rows.items()
                 for target, weight, edge in values}
        for root, values in network.items():
            tree = {node: (parent, edge) for node, parent, edge in trees[root]}
            for target, expected, edge in values:
                if owners[root] != owners[target]:
                    self.assertEqual(edges[edge], (root, target, expected))
                    continue
                total, node, seen = 0, target, set()
                while node != root:
                    self.assertNotIn(node, seen)
                    seen.add(node)
                    parent, witness = tree[node]
                    self.assertEqual(edges[witness][:2], (parent, node))
                    self.assertEqual(owners[parent], owners[root])
                    self.assertIn(witness, used)
                    total += edges[witness][2]
                    node = parent
                self.assertEqual(total, expected)

    def test_endpoint_search_stops_without_visiting_the_entire_component(self):
        rows = {1: [(2, 1, 1)], 2: [(3, 1, 2)], 3: []}
        self.assertEqual(backbone.endpoint_search(rows, {1: 0}, 2), (1, 2))
        self.assertEqual(backbone.endpoint_search(rows, {1: 0}, -1, terminals={2: 3}), (4, 4))

    def test_local_path_may_cross_strong_component_boundary(self):
        rows = {1: [(2, 1, 1)], 2: [(3, 1, 2)], 3: [(4, 1, 3)], 4: []}
        owners = {1: "left", 2: "middle", 3: "middle", 4: "right"}
        network, _, _, _, _, _ = backbone.contract(rows, owners)
        self.assertIn((3, 1, None), network[2])
        self.assertNotIn((2, 1, None), network[3])


if __name__ == "__main__":
    unittest.main()
