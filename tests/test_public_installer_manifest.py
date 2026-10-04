"""Public boundary binds actual embedded bytes and refuses imported datasets."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import public_installer_manifest as public

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.base=self.root/"base.zip"
        public.bundle.write_payload("1.0.0-beta.15",self.base,
            {name:b"fixture" for name in ("RikUI/RikUI.toc","RikUI/LICENSE","RikUI/generated/index.xml")},["interface"])
        self.program=self.root/"setup.exe";self.program.write_bytes(b"owned program fixture")
        self.runtime=self.root/"runtime";self.runtime.mkdir()
        self.manifest=dict(format="rikui-local-runtime-v1",dependencies=[],files=[])
        self.add("tools/local_assembly.py",b"authored compiler fixture")
    def add(self,name,raw):
        path=self.runtime/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
        self.manifest["files"].append(dict(path=name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()))
        (self.runtime/"runtime.json").write_text(json.dumps(self.manifest))
    def proof(self,arguments,**_):
        value=dict(format="rikui-embedded-package-proof-v1",version="1.0.0-beta.15",
            programSHA256=hashlib.sha256(self.program.read_bytes()).hexdigest(),
            baseSHA256=hashlib.sha256(self.base.read_bytes()).hexdigest(),
            runtimeManifestSHA256=hashlib.sha256((self.runtime/"runtime.json").read_bytes()).hexdigest(),
            runtimeSHA256="a"*64,runtimeFiles=len(self.manifest["files"]))
        if getattr(self,"wrong",False):value["baseSHA256"]="b"*64
        Path(arguments[-1]).write_text(json.dumps(value))
    def create(self):
        return public.create("1.0.0-beta.15",self.program,self.base,self.runtime,self.root/"public")
    def test_report_binds_embedded_proof_and_published_checksum(self):
        with patch.object(public.subprocess,"run",side_effect=self.proof):result=self.create()
        self.assertFalse(result["importedDatasetsIncluded"]);self.assertFalse(result["clientGeometryIncluded"])
        self.assertEqual(result["embeddedRuntimeSHA256"],"a"*64)
        lines=(self.root/"public/RikUI-Setup-SHA256SUMS").read_text().splitlines()
        self.assertEqual(len(lines),3)
        for line in lines:
            expected,name=line.split("  ")
            path=self.program if name=="RikUI-Setup.exe" else self.root/"public"/name
            self.assertEqual(expected,hashlib.sha256(path.read_bytes()).hexdigest())
    def test_wrong_embedded_base_prevents_public_manifest(self):
        self.wrong=True
        with patch.object(public.subprocess,"run",side_effect=self.proof),self.assertRaisesRegex(ValueError,"embedded package"):
            self.create()
        self.assertFalse((self.root/"public").exists())
    def test_provider_or_geometry_files_fail_before_execution(self):
        self.add("tools/provider.csv",b"private input")
        with patch.object(public.subprocess,"run") as execute,self.assertRaisesRegex(ValueError,"Data file"):
            self.create()
        execute.assert_not_called()
    def test_licensed_numpy_test_fixture_is_not_mistaken_for_provider_data(self):
        self.add("python/site-packages/numpy/core/tests/data/fixture.csv",b"licensed dependency fixture")
        with patch.object(public.subprocess,"run",side_effect=self.proof):self.create()

if __name__=="__main__":unittest.main()
