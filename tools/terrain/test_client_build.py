"""Build-domain separation, exact source admission and liquid coverage."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import refresh_sources as refresh

HERE = pathlib.Path(__file__).resolve().parent


class BuildTests(unittest.TestCase):
    def inspect(self, build):
        env = dict(os.environ, RIKUI_TERRAIN_BUILD=build)
        code = ("import json,client_build as c,world_source as s,world_export_graph as g,world_liquid as l;"
                "print(json.dumps([c.BUILD,s.IDENTITY,g.RUNTIME_IDENTITY,c.SOURCE_HASHES,1344 in l.SWIMMABLE]))")
        return subprocess.run([sys.executable, "-B", "-c", code], cwd=HERE,
                              env=env, capture_output=True, text=True, timeout=30)

    def test_supported_domains(self):
        for build in ("1.60.1.69913", "1.60.1.70009"):
            result = self.inspect(build)
            self.assertEqual(result.returncode, 0, result.stderr)
            active, source, runtime, hashes, canal = json.loads(result.stdout)
            self.assertEqual((active, source["build"], runtime["build"]), (build,) * 3)
            self.assertEqual((source["product"], runtime["product"]), ("wow_classic_beta", "forever"))
            self.assertEqual(canal, build == "1.60.1.70009")
            self.assertEqual(len(hashes), 3)

    def test_unknown_build_fails(self):
        result = self.inspect("1.60.1.99999")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported terrain build", result.stderr)


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.files = self.root / "chunk-01" / "files"
        self.files.mkdir(parents=True)
        self.asset = self.files / "42.bin"
        self.asset.write_bytes(b"new")
        self.original = {"files": [{"fileDataID": 42, "sha256": refresh.sha(b"old")}]}
        self.report = {"changed": [{"fileDataID": 42, "new": refresh.sha(b"new")}]}

    def seeds(self):
        with patch.object(refresh, "WDT_PINS", {}):
            return refresh.seed_paths(self.report, self.original, self.root, self.root)

    def test_current_hash_admitted(self):
        self.assertEqual(self.seeds(), {42: self.asset})

    def test_modified_comparison_refused(self):
        self.asset.write_bytes(b"stale")
        with self.assertRaisesRegex(ValueError, "comparison asset changed"):
            self.seeds()

    def test_missing_asset_not_replaced_by_supplement(self):
        self.asset.unlink()
        (self.root / "42.bin").write_bytes(b"old")
        self.report["changed"][0]["new"] = None
        self.assertEqual(self.seeds(), {})

    def test_unreported_asset_refused(self):
        (self.files / "43.bin").write_bytes(b"unknown")
        with self.assertRaisesRegex(ValueError, "unreported comparison asset"):
            self.seeds()

    def test_topology_must_match(self):
        (self.root / "55.bin").write_bytes(b"changed")
        with patch.object(refresh, "WDT_PINS", {0: (55, refresh.sha(b"original"))}):
            with self.assertRaisesRegex(ValueError, "changed world topology"):
                refresh.seed_paths(self.report, self.original, self.root, self.root)


if __name__ == "__main__":
    unittest.main()

