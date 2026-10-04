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
    def inspect(self, overrides=None):
        env = dict(os.environ)
        env.pop("RIKUI_TERRAIN_BUILD", None)
        env.pop("RIKUI_CURRENT_INPUTS", None)
        env.update(overrides or {})
        return subprocess.run([sys.executable, "-B", "-c",
            "import client_build as c; c.require_current(); print(c.BUILD)"],
            cwd=HERE,env=env,capture_output=True,text=True,timeout=30)

    def test_no_historical_default(self):
        result=self.inspect()
        self.assertNotEqual(result.returncode,0)
        self.assertIn("Current acquisition receipt required",result.stderr)

    def test_historical_override_refused(self):
        result=self.inspect({"RIKUI_TERRAIN_BUILD":"1.99.1.12345"})
        self.assertNotEqual(result.returncode,0)
        self.assertIn("Historical build override removed",result.stderr)

    def test_dynamic_verified_receipt_and_changed_bytes(self):
        import forever_inputs as current
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)
            build="1.99.1.12345"
            identity=dict(product="wow_future",edition="Forever",build=build,
                          buildConfig="a"*32,cdnConfig="b"*32)
            sources={name:dict(repository=repo,branch=branch or "master",revision=str(n+1)*40)
                     for n,(name,(repo,branch)) in enumerate(current.SOURCES.items())}
            sources["ui"]["versionSHA256"]="c"*64
            inputs=dict(identity=identity,sources=sources,buildInfoSHA256="d"*64)
            resolution=dict(format="rikui-current-input-resolution-v1",inputs=inputs,
                            fingerprint=current.sha(current.canonical(inputs)),compatibility="not-yet-verified")
            hashes={}
            for name in ("Map","UiMap","UiMapAssignment","LiquidType","QuestV2"):
                raw=b"fixture-only"; (root/(name+"-"+build+".csv")).write_bytes(raw)
                hashes[name]=current.sha(raw)
            tile=b"fixture-tiles"; (root/"all-projected-world-tile-worklist.csv").write_bytes(tile)
            liquid=b'{"kinds":{"1":"water","3":"magma"}}'
            (root/"liquid-kinds.json").write_bytes(liquid)
            proof_raw=current.canonical(dict(format="rikui-current-m2-proof-v1",
                sourceProfileSHA256="f"*64,records=[dict(fileDataID=42,sha256="e"*64,bytes=240,vertices=0,triangles=0)]))
            (root/"m2-proof.json").write_bytes(proof_raw)
            receipt=dict(format="rikui-current-navigation-inputs-v1",resolution=resolution,
                         identity=dict(identity,locale="enUS"),sourceDirectory=str(root),
                         profileSHA256="f"*64,m2Proof=dict(path=str(root/"m2-proof.json"),sha256=current.sha(proof_raw)),
                         sourceHashes=hashes,tileWorklistSHA256=current.sha(tile),
                         liquidKindsSHA256=current.sha(liquid),topology={"7":[42,"e"*64]})
            path=root/"receipt.json";path.write_bytes(current.canonical(receipt))
            result=self.inspect({"RIKUI_CURRENT_INPUTS":str(path)})
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout.strip(),build)
            (root/("Map-"+build+".csv")).write_bytes(b"changed")
            result=self.inspect({"RIKUI_CURRENT_INPUTS":str(path)})
            self.assertNotEqual(result.returncode,0)
            self.assertIn("Current input hash mismatch",result.stderr)


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

