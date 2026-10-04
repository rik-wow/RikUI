"""Road cache integrity and changed raster input regression contracts."""
import json
from pathlib import Path
import tempfile
import unittest
import road_parallel as parallel
from world_source import sha


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)

    def test_cached_bytes_are_checked_before_reuse(self):
        name="w0_1_2.pkl"
        (self.root/name).write_bytes(b"verified local compact fixture")
        (self.root/"complete.json").write_text(json.dumps(dict(
            inputSHA256="a"*64,counts={"0_1_2":7},files={name:sha((self.root/name).read_bytes())})))
        self.assertTrue(parallel.verify_cache(self.root,"a"*64,[(0,1,2)]))
        (self.root/name).write_bytes(b"changed")
        self.assertFalse(parallel.verify_cache(self.root,"a"*64,[(0,1,2)]))

    def test_missing_wrong_generation_and_duplicate_coverage_rejected(self):
        self.assertFalse(parallel.verify_cache(self.root,"a"*64,[(0,1,2)]))
        (self.root/"complete.json").write_text(json.dumps(dict(inputSHA256="b"*64,counts={},files={})))
        self.assertFalse(parallel.verify_cache(self.root,"a"*64,[(0,1,2)]))

    def test_raster_byte_change_invalidates_model(self):
        path=self.root/"w0_1_2.npy";path.write_bytes(b"raster fixture one")
        before=parallel.raster_inventory(self.root)
        path.write_bytes(b"raster fixture two")
        self.assertNotEqual(before,parallel.raster_inventory(self.root))
        self.assertEqual(parallel.raster_inventory(self.root),parallel.raster_inventory(self.root))

    def test_empty_raster_directory_and_workers_are_bounded(self):
        with self.assertRaises(ValueError):parallel.raster_inventory(self.root)
        self.assertTrue(1<=parallel.default_workers()<=4)


if __name__=="__main__":unittest.main()
