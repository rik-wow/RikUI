"""Road texture decoding: RLE alpha, layer blending, naming and raster lookup."""
import struct, tempfile, unittest
import numpy as np
import road_textures as r


def chunk(tag, body):
    return tag[::-1].encode() + struct.pack('<I', len(body)) + body


def tex0(textures, layers, mcal):
    mcly = b''.join(struct.pack('<IIIi', *layer, 0) for layer in layers)
    mcnk = chunk('MCNK', chunk('MCLY', mcly) + chunk('MCAL', mcal))
    return chunk('MVER', struct.pack('<I', 18)) + chunk('MDID', struct.pack('<%dI' % len(textures), *textures)) + mcnk * 256


class Tests(unittest.TestCase):
    def test_rle_fill_and_copy(self):
        data = bytes([0x80 | 100, 7, 3, 1, 2, 3]) + bytes([0x80 | 127, 9]) * 40
        out = r.decompress(data, 0).reshape(-1)
        self.assertEqual(list(out[:103]), [7] * 100 + [1, 2, 3])
        self.assertEqual(out[4095], 9)

    def test_truncated_rle_rejected(self):
        with self.assertRaisesRegex(ValueError, 'MCAL-truncated'):
            r.decompress(bytes([0x80 | 10, 1]), 0)

    def test_small_alpha_expands_nibbles(self):
        values = r.alpha(bytes([0xF0]) * 2048, dict(offset=0, flags=r.FLAG_USE_ALPHA), True, 2048)
        self.assertEqual(values[0, 0], 0)
        self.assertEqual(values[0, 1], 255)

    def test_sequential_blending_hides_lower_layers(self):
        full = bytes([255]) * 4096
        layers = [dict(texture=0, flags=0, offset=0), dict(texture=1, flags=r.FLAG_USE_ALPHA, offset=0)]
        w = r.weights(layers, full, True)
        self.assertAlmostEqual(float(w[0].max()), 0.0)
        self.assertAlmostEqual(float(w[1].min()), 1.0)

    def test_tile_raster_counts_only_road_layers(self):
        half = bytes([128]) * 4096
        data = tex0([100, 200], [(0, 0, 0), (1, r.FLAG_USE_ALPHA, 0)], half)
        road = r.tile_raster(data, {200})
        self.assertEqual(road.shape, (256, 256))
        self.assertTrue(126 <= int(road[10, 10]) <= 130)
        self.assertEqual(int(r.tile_raster(data, set()).max()), 0)

    def test_road_names(self):
        self.assertTrue(r.is_road('tileset/barrens/barrensroad01_s.blp'))
        self.assertTrue(r.is_road('tileset/ironforge/ironforgerock09browncracks_s.blp'))
        self.assertFalse(r.is_road('tileset/wetlands/wetlandsdirt01_s.blp'))
        self.assertFalse(r.is_road('tileset/duskwallow marsh/duskwallowbrickfloor_s.blp'))
        self.assertFalse(r.is_road(None))

    def test_lookup_matches_cell_centers(self):
        raster = np.zeros((256, 256), dtype=np.uint8)
        raster[17, 200] = 255
        with tempfile.TemporaryDirectory() as root:
            np.save(root + '/w0_33_42.npy', raster)
            lookup = r.RoadLookup(root, 0)
            x, z = r.cell_center(33, 42, 17, 200)
            self.assertEqual(lookup.fraction(x, z), 1.0)
            x, z = r.cell_center(33, 42, 18, 200)
            self.assertEqual(lookup.fraction(x, z), 0.0)
            self.assertEqual(lookup.fraction(100000 / 3, 0), 0.0)


if __name__ == '__main__':
    unittest.main()
