"""MH2O liquid becomes swim surfaces; magma and unknown liquids stay excluded."""
import struct, unittest
from unittest import mock
import terrain_probe as t
import world_liquid as liquid


def mh2o(instances_by_chunk):
    """instances_by_chunk: {chunk index: [(type, fmt, min, max, x, y, w, h, bitmap bytes or None, heights or None)]}."""
    header, body = bytearray(3072), bytearray()
    def at():
        return 3072 + len(body)
    for index, rows in sorted(instances_by_chunk.items()):
        start = at()
        body.extend(bytes(24 * len(rows)))
        packed = []
        for kind, fmt, low, high, x, y, w, h, bitmap, heights in rows:
            bitmap_at = 0
            if bitmap is not None:
                bitmap_at = at(); body.extend(bitmap)
            vertex_at = 0
            if heights is not None:
                vertex_at = at(); body.extend(struct.pack('<%df' % len(heights), *heights))
            packed.append(struct.pack('<HHffBBBBII', kind, fmt, low, high, x, y, w, h, bitmap_at, vertex_at))
        body[start - 3072:start - 3072 + 24 * len(rows)] = b''.join(packed)
        struct.pack_into('<III', header, index * 12, start, len(rows), 0)
    return bytes(header + body)


def records():
    return [dict(x=i % 16, y=i // 16, position=[1000.0 - (i // 16) * t.CHUNK, 2000.0 - (i % 16) * t.CHUNK, 0.0], subchunks=[])
            for i in range(256)]


def run(data, keep=None):
    with mock.patch.object(liquid, 'SWIMMABLE', {1, 5, 1250, 1288, 1325}), \
         mock.patch.object(liquid.t, 'chunks', return_value=[('MH2O', 0, len(data))]):
        return liquid.liquid(data, records(), [32, 32], keep)


def normal_y(v, tri):
    a, b, c = (v[i * 3:i * 3 + 3] for i in tri)
    e1, e2 = [b[k] - a[k] for k in range(3)], [c[k] - a[k] for k in range(3)]
    return e1[2] * e2[0] - e1[0] * e2[2]


class Tests(unittest.TestCase):
    def test_full_water_chunk_is_a_flat_upward_surface(self):
        v, tris, excluded, _ = run(mh2o({0: [(1, 2, 5.0, 5.0, 0, 0, 8, 8, None, None)]}))
        self.assertEqual(excluded, [])
        self.assertEqual(len(tris) // 3, 128)
        self.assertEqual(set(v[1::3]), {5.0})
        self.assertTrue(all(normal_y(v, tris[i:i + 3]) > 0 for i in range(0, len(tris), 3)))
        self.assertAlmostEqual(max(v[0::3]) - min(v[0::3]), t.CHUNK)

    def test_partial_instance_follows_bitmap_and_heights(self):
        heights = [1.0, 1.5, 2.0, 1.0, 1.5, 2.0]  # 2x1 subcells -> 3x2 vertices
        v, tris, _, areas = run(mh2o({17: [(5, 0, 1.0, 2.0, 3, 4, 2, 1, bytes([0b01]), heights)]}))
        self.assertEqual(len(tris) // 3, 2)  # only the first subcell exists
        self.assertEqual(sorted(set(v[1::3])), [1.0, 1.5, 2.0])
        self.assertAlmostEqual(max(v[0::3]), 2000.0 - t.CHUNK - 3 * t.UNIT)
        (lo, hi), = [a['bounds'] for a in areas]
        self.assertAlmostEqual(hi[0], max(v[0::3])); self.assertAlmostEqual(lo[0], max(v[0::3]) - t.UNIT)
        self.assertAlmostEqual(hi[2], max(v[2::3])); self.assertAlmostEqual(lo[2], min(v[2::3]))
        self.assertEqual((lo[1], hi[1]), (1.0, 1.5))

    def test_water_cost_mask_preserves_holes_and_empty_instances(self):
        import road_network
        _, _, _, areas = run(mh2o({0: [(1, 2, 5., 5., 0, 0, 3, 1, bytes([0b101]), None)]}))
        water = road_network.WaterLookup(areas)
        self.assertTrue(water.at(2000 - .5 * t.UNIT, 5, 1000 - .5 * t.UNIT))
        self.assertFalse(water.at(2000 - 1.5 * t.UNIT, 5, 1000 - .5 * t.UNIT))
        self.assertFalse(water.submerged(2000 - 1.5 * t.UNIT, 0, 1000 - .5 * t.UNIT))
        self.assertTrue(water.at(2000 - 2.5 * t.UNIT, 5, 1000 - .5 * t.UNIT))
        _, tris, _, areas = run(mh2o({0: [(1, 2, 5., 5., 0, 0, 3, 1, bytes([0]), None)]}))
        self.assertEqual((tris, areas), ([], []))

    def test_modern_water_ids_are_swimmable(self):
        for kind in (1250, 1288, 1325):  # PBR ocean, river, lake
            _, tris, excluded, _ = run(mh2o({0: [(kind, 2, 5.0, 5.0, 0, 0, 8, 8, None, None)]}))
            self.assertEqual(excluded, []); self.assertEqual(len(tris) // 3, 128)

    def test_magma_excludes_only_its_cells_below_the_surface(self):
        # A one-subcell-wide lava stream down column 4, eight rows long.
        v, tris, excluded, _ = run(mh2o({0: [(3, 2, 5.0, 5.0, 4, 0, 1, 8, bytes([0xFF]), None)]}))
        self.assertEqual(tris, [])
        self.assertEqual(len(excluded), 8)
        box = excluded[0]
        self.assertEqual((box['reason'], box['liquidType'], box['belowSurface']), ('unswimmable-liquid', 3, True))
        (x0, y0, _), (x1, y1, _) = box['bounds']
        self.assertAlmostEqual(x1 - x0, t.UNIT)          # one subcell wide, not the whole chunk
        self.assertEqual((y0, y1), (-100000, 5.0 + liquid.ABOVE_SURFACE))

    def test_mixed_chunk_keeps_its_water(self):
        _, tris, excluded, _ = run(mh2o({0: [(3, 2, 5.0, 5.0, 0, 0, 1, 1, None, None), (1, 2, 5.0, 5.0, 2, 2, 2, 2, None, None)]}))
        self.assertEqual(len(tris) // 3, 8)
        self.assertEqual(len(excluded), 1)

    def test_keep_limits_emitted_chunks(self):
        data = mh2o({0: [(1, 2, 5.0, 5.0, 0, 0, 8, 8, None, None)], 1: [(1, 2, 5.0, 5.0, 0, 0, 8, 8, None, None)]})
        _, tris, _, _ = run(data, keep={(1, 0)})
        self.assertEqual(len(tris) // 3, 128)

    def test_instance_outside_chunk_fails(self):
        with self.assertRaisesRegex(ValueError, 'world-MH2O-instance-extent'):
            run(mh2o({0: [(1, 2, 5.0, 5.0, 4, 0, 8, 8, None, None)]}))


if __name__ == '__main__':
    unittest.main()
