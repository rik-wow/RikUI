"""Road network cost model: roads are cheaper, swimming is dearer, IDs fit u32."""
import unittest
import road_network as net


class NoRoad:
    def fraction(self, x, z):
        return 0.0


class AllRoad:
    def fraction(self, x, z):
        return 1.0


POND = net.WaterLookup([dict(bounds=[[0, 10, 0], [100, 10, 100]])])


class Tests(unittest.TestCase):
    def test_surface_counts_as_water_but_the_bottom_does_not(self):
        self.assertTrue(POND.at(50, 10, 50))
        self.assertTrue(POND.at(50, 9.5, 50))
        self.assertFalse(POND.at(50, 2, 50))     # pond floor: walking, not swimming
        self.assertFalse(POND.at(150, 10, 50))   # outside the liquid rectangle

    def test_deep_floor_is_submerged(self):
        self.assertTrue(POND.submerged(50, 2, 50))
        self.assertFalse(POND.submerged(50, 9, 50))
        self.assertFalse(POND.submerged(150, 2, 50))

    def test_swimming_costs_more_than_walking(self):
        points = [(10, 10, 50), (90, 10, 50)]
        length, walk = net.weighted_length(points, NoRoad())
        _, swim = net.weighted_length(points, NoRoad(), POND)
        self.assertAlmostEqual(length, 80)
        self.assertAlmostEqual(walk, 80)
        self.assertAlmostEqual(swim, 80 * net.SWIM_COST)

    def test_road_is_cheaper_than_open_ground(self):
        _, cost = net.weighted_length([(0, 0, 0), (10, 0, 0)], AllRoad())
        self.assertAlmostEqual(cost, 10 * (1 - net.ROAD_BONUS))

    def test_polygon_ids_use_twelve_index_bits_and_fit_u32(self):
        self.assertEqual(net.polygon_id('w0:r0:0:0:p4095') - net.polygon_id('w0:r0:0:0:p0'), 4095)
        self.assertNotEqual(net.polygon_id('w0:r0:0:0:p4095'), net.polygon_id('w0:r0:1:0:p0'))
        self.assertLess(net.polygon_id('w0:r300:300:0:p4095'), 1 << 32)
        with self.assertRaises(Exception):
            net.polygon_id('w0:r0:0:0:p4096')


if __name__ == '__main__':
    unittest.main()
