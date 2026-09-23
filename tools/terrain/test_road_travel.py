"""Stop attachment and stop-to-stop walking costs."""
import unittest
import road_travel as rt


def info(x, z):
    return (0, (x, 0.0, z), (0, 0), 0.0)


# Three nodes on a line, 100 yd apart, plus an island node far away.
INFOS = [info(0, 0), info(100, 0), info(200, 0), info(5000, 0)]
EDGES = [[(1, 100.0, 100.0, [])], [(0, 100.0, 100.0, []), (2, 60.0, 100.0, [])], [(1, 60.0, 100.0, [])], []]


def stop(ident, kind, x, z):
    return dict(id=ident, kind=kind, point=[x, 0.0, z])


class Tests(unittest.TestCase):
    def test_stops_join_the_nearest_node_within_reach(self):
        attached, missing = rt.attach(INFOS, [stop('flight:1', 'flight', 10, 30), stop('flight:2', 'flight', 600, 0)])
        self.assertEqual(attached, [dict(id='flight:1', node=0, yards=31.6)])
        self.assertEqual(missing, [dict(id='flight:2', nearestYards=400.0)])

    def test_docks_reach_further_than_flight_masters(self):
        attached, _ = rt.attach(INFOS, [stop('dock:1:0', 'dock', 200, 150)])
        self.assertEqual(attached[0]['node'], 2)

    def test_walks_follow_network_costs_and_skip_islands(self):
        stops = [stop('a', 'flight', 0, 0), stop('b', 'flight', 200, 0), stop('c', 'flight', 5000, 0)]
        section = rt.section(INFOS, EDGES, stops)
        self.assertEqual([s['node'] for s in section['stops']], [1, 3, 4])  # 1-based
        self.assertEqual(sorted(map(tuple, section['walks'])), [(1, 2, 160.0), (2, 1, 160.0)])


class Levels(unittest.TestCase):
    def test_lift_ends_join_nodes_at_their_own_height(self):
        infos = [info(0, 0), (0, (5.0, 60.0, 0.0), (0, 0), 0.0)]
        bottom = dict(id='lift:1:0:bottom', kind='elevator', point=[3.0, 1.0, 0.0])
        top = dict(id='lift:1:0:top', kind='elevator', point=[3.0, 59.0, 0.0])
        attached, _ = rt.attach(infos, [bottom, top])
        self.assertEqual([a['node'] for a in attached], [0, 1])


class Lifts(unittest.TestCase):
    def test_stacked_nodes_in_different_pieces_are_candidates(self):
        infos = [info(0, 0), (0, (5.0, 61.0, 0.0), (0, 0), 0.0), info(300, 0)]
        edges = [[(2, 300.0, 300.0, [])], [], [(0, 300.0, 300.0, [])]]
        rows = rt.lift_candidates(infos, edges, [61.2])
        self.assertEqual([(r['low'], r['high']) for r in rows], [(0, 1)])

    def test_connected_or_misaligned_nodes_are_not(self):
        infos = [info(0, 0), (0, (5.0, 61.0, 0.0), (0, 0), 0.0)]
        joined = [[(1, 10.0, 10.0, [])], [(0, 10.0, 10.0, [])]]
        self.assertEqual(rt.lift_candidates(infos, joined, [61.2]), [])
        self.assertEqual(rt.lift_candidates(infos, [[], []], [80.0]), [])


if __name__ == '__main__':
    unittest.main()
