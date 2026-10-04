"""Public setup update admission, no-op, tamper retention and channel boundaries."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import update_setup as updates
import forever_inputs as current

class Response(io.BytesIO):
    def __enter__(self):return self
    def __exit__(self,*_):self.close()

class Tests(unittest.TestCase):
    def setUp(self):
        self.raw=b"MZ-current-fixture"
        self.artifact=dict(filename="RikUI-Setup.exe",url="https://github.com/rik-wow/RikUI/releases/download/v1.0.0-beta.16/RikUI-Setup.exe",
                           sha256=hashlib.sha256(self.raw).hexdigest(),bytes=len(self.raw))
        self.manifest=dict(format="rikui-public-installer-v1",version="1.0.0-beta.16",artifact=self.artifact)
        self.release=dict(tag_name="v1.0.0-beta.16",draft=False,assets=[
            dict(name=updates.NAME,browser_download_url="https://github.com/rik-wow/RikUI/releases/download/v1.0.0-beta.16/"+updates.NAME),
            dict(name=self.artifact["filename"],browser_download_url=self.artifact["url"],size=len(self.raw),digest="sha256:"+self.artifact["sha256"])])
        self.fetch=lambda *_:current.canonical(self.manifest)
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)

    def test_changed_release_acquires_exact_verified_program(self):
        manifest=updates.select([self.release],"1.0.0-beta.15",self.fetch)
        with patch.object(updates,"opener") as op:
            op.return_value.open.return_value=Response(self.raw)
            result=updates.download_artifact(manifest["artifact"],self.root)
        self.assertEqual(result.read_bytes(),self.raw)

    def test_unchanged_version_performs_no_download(self):
        def unexpected(*_):raise AssertionError("Unchanged program must not download")
        self.assertIsNone(updates.select([self.release],"1.0.0-beta.16",unexpected))

    def test_same_version_published_bytes_are_verified_without_download(self):
        self.assertIsNone(updates.select([self.release],"1.0.0-beta.16",self.fetch,
                          current_sha=self.artifact["sha256"]))

    def test_same_version_replaced_bytes_are_rejected(self):
        with self.assertRaisesRegex(ValueError,"without a newer"):
            updates.select([self.release],"1.0.0-beta.16",self.fetch,current_sha="f"*64)

    def test_stable_does_not_downgrade_to_beta(self):
        self.assertIsNone(updates.select([self.release],"1.0.0",self.fetch))

    def test_existing_verified_download_is_reused(self):
        target=self.root/self.artifact["sha256"]/"RikUI-Setup.exe"
        target.parent.mkdir();target.write_bytes(self.raw)
        with patch.object(updates,"opener",side_effect=AssertionError("No download")):
            self.assertEqual(updates.download_artifact(self.artifact,self.root),target)

    def test_tampered_program_retained_and_replaced(self):
        target=self.root/self.artifact["sha256"]/"RikUI-Setup.exe"
        target.parent.mkdir();target.write_bytes(b"tampered")
        with patch.object(updates,"opener") as op:
            op.return_value.open.return_value=Response(self.raw)
            updates.download_artifact(self.artifact,self.root)
        self.assertEqual(target.read_bytes(),self.raw)
        self.assertEqual(next(target.parent.glob("*retained*")).read_bytes(),b"tampered")

    def test_incomplete_and_mismatched_bytes_never_become_program(self):
        for raw in (b"MZ",b"X"*len(self.raw)):
            with self.subTest(raw=raw),patch.object(updates,"opener") as op:
                op.return_value.open.return_value=Response(raw)
                with self.assertRaisesRegex(ValueError,"checksum"):updates.download_artifact(self.artifact,self.root)
        self.assertFalse((self.root/self.artifact["sha256"]/"RikUI-Setup.exe").exists())
        self.assertEqual(len(list(self.root.rglob("*.partial-*"))),2)

    def test_manifest_cannot_substitute_another_repository_or_asset(self):
        self.manifest["artifact"]=dict(self.artifact,url="https://github.com/another/project/releases/download/x/evil.exe")
        with self.assertRaisesRegex(ValueError,"publisher"):updates.select([self.release],"1.0.0-beta.15",self.fetch)

    def test_manifest_publisher_checksum_is_checked(self):
        self.release["assets"][0]["digest"]="sha256:"+"f"*64
        with self.assertRaisesRegex(ValueError,"manifest publisher checksum"):updates.select([self.release],"1.0.0-beta.15",self.fetch)

    def test_published_asset_bytes_must_match_manifest(self):
        self.release["assets"][1]["size"]+=1
        with self.assertRaisesRegex(ValueError,"published asset"):updates.select([self.release],"1.0.0-beta.15",self.fetch)

    def test_unknown_schema_cannot_be_launched(self):
        self.manifest["format"]="unsupported"
        with self.assertRaisesRegex(ValueError,"identity"):updates.select([self.release],"1.0.0-beta.15",self.fetch)

if __name__=="__main__":unittest.main()
