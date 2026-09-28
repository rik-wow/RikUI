"""Quest patch geometry: area rectangles, selection, node joins and binary encoding."""
import pathlib, pickle, struct, tempfile, unittest
import road_parallel
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
        self.by_cell = {(0, 0): [0, 1], (1, 0): [2]}
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

    def test_patch_keeps_walkable_space_beyond_the_nearest_node(self):
        polys = Fake()
        # Spawn and gateway both lie in polygon 0; polygon 1 is a legitimate
        # shortcut/crossing in the same cell, not another quest target.
        self.assertEqual(qp.connect_to_nodes(polys, {0}, reps=[0]), {0, 1})
        # Expanding coverage never invents connectivity to an isolated surface.
        polys.edges[0] = []; polys.edges[1] = []
        self.assertEqual(qp.connect_to_nodes(polys, {0}, reps=[0]), {0})

    def test_patch_keeps_one_connected_approach_cell(self):
        polys = Fake()
        gate = ((64.0, 0.0, 0.0), (64.0, 0.0, 32.0))
        polys.edges[1].append((2, *gate))
        # A one-way portal still requires both surfaces; its direction is kept
        # when encoded. Coverage cannot flood through to a second ring.
        polys.cell.append((2, 0)); polys.by_cell[(2, 0)] = [3]
        polys.edges[2].append((3, *gate)); polys.edges.append([])
        self.assertEqual(qp.connect_to_nodes(polys, {0}, reps=[0]), {0, 1, 2})

    def test_parallel_patch_boundary_matches_serial(self):
        rows = []
        for cell in range(-2, 3):
            x = cell * net.CELL
            points = [(x, 0, 0), (x + 128, 0, 0), (x + 128, 0, 128), (x, 0, 128)]
            edges = []
            if cell > -2: edges.append((cell + 2, (x, 0, 0), (x, 0, 128)))
            if cell < 2: edges.append((cell + 4, (x + 128, 0, 128), (x + 128, 0, 0)))
            rows.append((cell + 3, (x + 64, 0, 64), points, 0, edges, (cell, 0), False))
        rects = [[-200, 50, -180, 80], [180, 50, 200, 80]]
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'batch.pkl'
            path.write_bytes(pickle.dumps(dict(rows=rows, liquids=[])))
            all_polys = road_parallel.load_region([path], -2, 3)
            serial, _, _ = qp.build_patches(all_polys, [], rects)
            parallel, _, _ = road_parallel._patches((0, 2, [path], set(), rects, (48, 24, 160)))
        self.assertEqual(parallel, {c: p for c, p in serial.items() if 0 <= c[0] < 2})
        self.assertEqual(parallel[(0, 0)]['portals'], 2)

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

    def test_compact_cell_returns_the_same_bytes(self):
        polys = Fake()
        cell = qp.encode_cell(polys, {0, 1}, {0, 1})
        raw = qp.compact_cell(cell)
        self.assertEqual(qp.expand_cell(raw, cell['vertexCount'], cell['polygons']), (cell['vertices'], cell['records']))
        lengths = dict(zip(qp.COMPACT_STREAMS, struct.unpack_from('<8I', raw, 0)))
        # The second polygon's portal is the twin of the first one's: an edge byte and no target.
        self.assertEqual((lengths['targets'], lengths['edges']), (1, 2))
        self.assertEqual(raw[-1], 3 + qp.EDGE_MIRROR + qp.EDGE_REVERSED)
        with self.assertRaises(Exception):
            qp.expand_cell(raw + b'\0', cell['vertexCount'], cell['polygons'])
        with self.assertRaises(Exception):
            qp.expand_cell(raw[:-1], cell['vertexCount'], cell['polygons'])

    def test_compact_cell_keeps_a_portal_that_is_not_a_polygon_edge(self):
        polys = Fake()
        polys.edges[0] = [(1, (32.0, 0.0, 32.0), (0.0, 0.0, 0.0))]  # a diagonal, and no twin on the other side
        polys.edges[1] = []
        cell = qp.encode_cell(polys, {0, 1}, {0, 1})
        raw = qp.compact_cell(cell)
        self.assertEqual(qp.expand_cell(raw, cell['vertexCount'], cell['polygons']), (cell['vertices'], cell['records']))

    def test_patch_text_is_deflate_in_base64(self):
        import base64, re, zlib
        polys = Fake()
        cell = qp.encode_cell(polys, {0, 1}, {0, 1})
        files, _ = qp.patch_files(0, 'a' * 64, {(0, 0): cell}, net.lua)
        text = files['RikUIQuestRoads_W0_P001/patch-001.lua'].decode()
        found = re.fullmatch(r'RikUI\.QuestPlanner\.Roads\.Patch2\("a{64}",(\d+),6,2,2,(\d+),\[\[(.*)\]\]\)\n', text)
        raw = zlib.decompress(base64.b64decode(found[3]), -15)
        self.assertEqual(len(raw), int(found[2]))
        self.assertEqual(raw, qp.compact_cell(cell))

    def test_patch_files_index_every_cell(self):
        polys = Fake()
        patches = {(0, 0): qp.encode_cell(polys, {0, 1}, {0, 1}), (1, 0): qp.encode_cell(polys, {2}, {2})}
        files, (stream, stride, count) = qp.patch_files(0, 'a' * 64, patches, net.lua, net.b85)
        self.assertEqual((stride, count), (10, 2))
        self.assertIn('RikUIQuestRoads_W0_P001/RikUIQuestRoads_W0_P001.toc', files)
        keys = [struct.unpack_from('<I', stream, k * 10)[0] for k in range(count)]
        self.assertEqual(keys, sorted(keys))
        self.assertIn(b'## LoadOnDemand: 1', files['RikUIQuestRoads_W0_P001/RikUIQuestRoads_W0_P001.toc'])

    def test_packs_split_only_at_the_size_cap(self):
        polys = Fake()
        cell = qp.encode_cell(polys, {0, 1}, {0, 1})
        patches = {(x, 0): cell for x in range(6)}
        original = qp.MAX_PATCH_ADDON
        try:
            qp.MAX_PATCH_ADDON = 16 * 1048576
            files, _ = qp.patch_files(0, 'a' * 64, patches, net.lua, net.b85)
            self.assertEqual({k.split('/')[0] for k in files}, {'RikUIQuestRoads_W0_P001'})
            qp.MAX_PATCH_ADDON = 1
            files, (stream, _, count) = qp.patch_files(0, 'a' * 64, patches, net.lua, net.b85)
            self.assertEqual(len({k.split('/')[0] for k in files}), 6)
            self.assertEqual([struct.unpack_from('<H', stream, k * 10 + 4)[0] for k in range(count)], [1, 2, 3, 4, 5, 6])
        finally:
            qp.MAX_PATCH_ADDON = original

    def test_embedded_network_files_and_include(self):
        catalog = dict(revision='b' * 64, format='rikui-road-network-v1')
        files = net.embedded_files(1, catalog, {'nodes': ['abc', 'def'], 'patches': ['']})
        self.assertEqual(set(files), {'generated/roads/w1-stream-nodes.lua', 'generated/roads/w1-catalog.lua'})
        self.assertEqual(files['generated/roads/w1-stream-nodes.lua'].count(b'Roads.Page('), 2)
        files.update({'generated/roads/index.lua': b'', 'RikUIQuestRoads_W1_P001/patch-001.lua': b''})
        include = net.include_files(files)['generated/roads/roads.xml'].decode()
        self.assertEqual(include.count('<Script file='), 3)
        self.assertLess(include.index('w1-catalog.lua'), include.index('index.lua'))
        self.assertNotIn('patch-001', include)


if __name__ == '__main__':
    unittest.main()
