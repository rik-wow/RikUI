"""Packing invariants and repeatable byte verification, independent of native traversal."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
import compile_backbone as compiler


class CompactCompileTests(unittest.TestCase):
    def fixture(self):
        h = 'a' * 64
        centers = {str(i): [float(i - 1), 0., 0.] for i in range(1, 4)}
        backbone = dict(format='rikui-backbone-benchmark-v1', graphSHA256=h,
                        partitionAuditSHA256=h, sourceManifestSHA256=h,
                        metadata=dict(identity=dict(product='forever', build='1.60.1.69913', locale='enUS'),
                                      uiMapID=1426, worldMapID=0),
                        centers=centers, boundary=[1, 3],
                        geometry={'1': [1, 2, .5, 0, 0], '2': [2, 3, 1.5, 0, 0]},
                        network={'1': [[3, 2.]], '3': []},
                        trees={'1': [[2, 1, 1], [3, 2, 2]], '3': []})
        nodes = {}
        for i in range(1, 4):
            x = i - 1
            nodes[i] = dict(id=i, points=[[x-.5, 0, -.5], [x+.5, 0, -.5],
                                         [x+.5, 0, .5], [x-.5, 0, .5]], portals=[])
            if i < 3:
                nodes[i]['portals'] = [dict(to=i+1, left=[x+.5, 0, -.5], right=[x+.5, 0, .5])]
        return backbone, nodes

    def test_deterministic_exact_packing_and_directed_cost(self):
        b, nodes = self.fixture()
        surfaces = compiler.pack_surface_geometry(b, nodes, 'a'*64, 'a'*64)
        files, receipt = compiler.build_files(b, 'b'*64, surfaces)
        self.assertEqual((files, receipt), compiler.build_files(b, 'b'*64, surfaces))
        self.assertEqual(receipt['proof']['bitEqualWitnessCosts'], 1)
        self.assertEqual(receipt['catalog']['counts']['surfacePoints'], 12)
        self.assertEqual(receipt['proof']['maxWitnessCostAbsoluteError'], 0)
        self.assertTrue(all(len(raw) <= compiler.MAX_SOURCE_BYTES for name, raw in files.items() if name != 'manifest.json'))

    def test_bounded_load_groups_preserve_order_and_completion(self):
        b, nodes = self.fixture()
        surfaces = compiler.pack_surface_geometry(b, nodes, 'a'*64, 'a'*64)
        original_limit = compiler.MAX_LOAD_BYTES
        try:
            compiler.MAX_LOAD_BYTES = 1536
            files, receipt = compiler.build_files(b, 'b'*64, surfaces)
        finally:
            compiler.MAX_LOAD_BYTES = original_limit
        catalog = receipt['catalog']
        self.assertGreater(len(catalog['loadParts']), 1)
        names = []
        for index, part in enumerate(catalog['loadParts'], 1):
            addon = part['addon']
            self.assertEqual(addon, catalog['addonName'] + '_P%03d' % index)
            toc = files[addon + '/' + addon + '.toc'].decode()
            rows = [line for line in toc.splitlines() if line and not line.startswith('#')]
            self.assertEqual(rows[-1], 'complete.lua')
            self.assertLessEqual(part['bytes'], 1536)
            self.assertEqual(part['bytes'], sum(len(files[addon + '/' + name]) for name in rows))
            self.assertIn(('p.loadedParts[%d]=true' % index).encode(), files[addon + '/complete.lua'])
            names.extend(rows[:-1])
        self.assertEqual(len(names), len(set(names)))
        base = catalog['addonName']
        base_toc = files[base + '/' + base + '.toc'].decode().splitlines()
        self.assertEqual([line for line in base_toc if line and not line.startswith('#')], ['init.lua'])
        self.assertTrue(all(name.startswith(('array_', 'stream_', 'metadata_')) for name in names))

    def test_corrupt_topology_and_weights_rejected(self):
        b, _ = self.fixture()
        mutations = [
            lambda v: v['network']['1'].append([3, 2]),
            lambda v: v['network']['1'].__setitem__(0, [3, -2]),
            lambda v: v['network']['1'].__setitem__(0, [3, 2.000000001]),
            lambda v: v['network']['1'].__setitem__(0, [1, 0]),
            lambda v: v['network']['1'].__setitem__(0, [999, 1]),
            lambda v: v['trees']['1'].__setitem__(0, [2, 3, 1]),
            lambda v: v['trees']['1'].pop(0),
            lambda v: v['geometry']['1'].__setitem__(1, 999),
            lambda v: v['centers']['1'].__setitem__(0, float('nan')),
            lambda v: v['boundary'].reverse(),
            lambda v: v.__setitem__('format', 'unknown'),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(b)
            mutate(changed)
            with self.assertRaises((ValueError, KeyError)):
                compiler.validate_and_pack(changed)

    def test_surface_orientation_and_order_are_bound(self):
        b, nodes = self.fixture()
        with self.assertRaises(ValueError):
            compiler.pack_surface_geometry(b, nodes, 'c'*64, 'a'*64)
        changed = copy.deepcopy(nodes)
        changed[1]['points'][0][1] = 1
        with self.assertRaises(ValueError):
            compiler.pack_surface_geometry(b, changed, 'a'*64, 'a'*64)
        changed = copy.deepcopy(nodes)
        changed[1]['portals'][0]['to'] = 3
        with self.assertRaises(ValueError):
            compiler.pack_surface_geometry(b, changed, 'a'*64, 'a'*64)

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaises(ValueError):
            compiler.parse_json('{"format":1,"format":2}')

    def test_verification_checks_all_bytes_without_rewriting(self):
        files = {'A/a.lua': b'exact\n', 'manifest.json': b'{}\n'}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'pack'
            compiler.write_or_verify(files, root)
            compiler.write_or_verify(files, root, True)
            with self.assertRaises(ValueError):
                compiler.write_or_verify(files, root)
            (root/'A/a.lua').write_bytes(b'changed\n')
            with self.assertRaises(ValueError):
                compiler.write_or_verify(files, root, True)
            self.assertEqual((root/'A/a.lua').read_bytes(), b'changed\n')
            (root/'A/a.lua').write_bytes(files['A/a.lua'])
            (root/'extra.lua').write_bytes(b'extra')
            with self.assertRaises(ValueError):
                compiler.write_or_verify(files, root, True)


if __name__ == '__main__':
    unittest.main()
