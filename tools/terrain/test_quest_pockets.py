"""Quest patch geometry: area rectangles, selection, node joins and binary encoding."""
import struct, unittest
import quest_pockets as qp
import road_network as net

VIEW = dict(uiMapID=1426, worldMapID=0, validUIRectangle=[0, 0, 1, 1],
            projection=dict(originX=1000.0, originY=1000.0, width=1000.0, height=1000.0))


class Fake:
    """Two 64-yard polygons side by side in one network cell, plus one in the next cell."""
    def __init__(self):
        self.center = [(16.0, 0.0, 16.0), (48.0, 0.0, 16.0), (144.0, 0.0, 16.0)]
        self.points = [[(0.0, 0.0, 0.0), (32.0, 0.0, 0.0), (32.0, 0.0, 32.0), (0.0, 0.0, 32.0)],
                       [(32.0, 0.0, 0.0), (64.0, 0.0, 0.0), (64.0, 0.0, 32.0), (32.0, 0.0, 32.0)],
                       [(128.0, 0.0, 0.0), (160.0, 0.0, 0.0), (160.0, 0.0, 32.0), (128.0, 0.0, 32.0)]]
        self.cell = [(0, 0), (0, 0), (1, 0)]
        self.road = [0.0, 0.0, 0.0]
        self.edges = [[(1, (32.0, 0.0, 32.0), (32.0, 0.0, 0.0))], [(0, (32.0, 0.0, 0.0), (32.0, 0.0, 32.0))], []]
        self.kept = set()

    def step_cost(self, i, j, left, right):
        return 1.0


class Tests(unittest.TestCase):
    def test_spawn_rect_is_centered(self):
        r = qp.area_rect(VIEW, dict(x=.5, y=.5, precision='spawn'))
        self.assertEqual(r, [500 - 48, 500 - 48, 500 + 48, 500 + 48])

    def test_cluster_rect_uses_bounds_and_margin(self):
        area = dict(x=.5, y=.5, precision='cluster', bounds=dict(minX=.49, maxX=.51, minY=.49, maxY=.51))
        r = qp.area_rect(VIEW, area)
        self.assertAlmostEqual(r[0], 490 - 24); self.assertAlmostEqual(r[2], 510 + 24)

    def test_huge_cluster_is_clipped(self):
        area = dict(x=.5, y=.5, precision='cluster', bounds=dict(minX=.1, maxX=.9, minY=.1, maxY=.9))
        r = qp.area_rect(VIEW, area)
        self.assertEqual(r, [500 - qp.MAX_HALF, 500 - qp.MAX_HALF, 500 + qp.MAX_HALF, 500 + qp.MAX_HALF])

    def test_view_must_contain_point(self):
        self.assertIsNone(qp.pick_view([dict(VIEW, validUIRectangle=[0, 0, .2, .2])], .5, .5))

    def test_select_and_join_to_node(self):
        polys = Fake()
        chosen = qp.select(polys, [[0, 0, 20, 20]])
        self.assertEqual(chosen, {0})
        kept = qp.connect_to_nodes(polys, chosen, reps=[1, 2])
        self.assertEqual(kept, {0, 1})  # node polygon 1 is joined; the other cell is untouched

    def test_encode_round_trip(self):
        polys = Fake()
        cell = qp.encode_cell(polys, {0, 1}, {0, 1})
        self.assertEqual(cell['polygons'], 2); self.assertEqual(cell['portals'], 2)
        vertices = [struct.unpack_from('<iii', cell['vertices'], k * 12) for k in range(cell['vertexCount'])]
        self.assertEqual(len(vertices), 6)  # shared edge vertices are stored once
        ident, count = struct.unpack_from('<IB', cell['records'], 0)
        self.assertEqual((ident, count), (1, 4))
        first = struct.unpack_from('<H', cell['records'], 5)[0]
        self.assertEqual(tuple(v / qp.PATCH_UNITS for v in vertices[first]), (0.0, 0.0, 0.0))

    def test_patch_files_index_every_cell(self):
        polys = Fake()
        patches = {(0, 0): qp.encode_cell(polys, {0, 1}, {0, 1}), (1, 0): qp.encode_cell(polys, {2}, {2})}
        files, (stream, stride, count) = qp.patch_files(0, 'a' * 64, patches, net.lua, net.b85)
        self.assertEqual((stride, count), (10, 2))
        self.assertIn('RikUIQuestRoads_W0_P001/RikUIQuestRoads_W0_P001.toc', files)
        keys = [struct.unpack_from('<I', stream, k * 10)[0] for k in range(count)]
        self.assertEqual(keys, sorted(keys))


if __name__ == '__main__':
    unittest.main()
