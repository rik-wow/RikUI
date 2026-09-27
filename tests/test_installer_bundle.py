import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import build_installer_bundle as builder

class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = {"RikUI/RikUI.toc": b"version", "RikUI/LICENSE": b"MIT",
                     "RikUI/generated/index.xml": b"<Ui/>"}

    def build(self, output, **kwargs):
        with patch.object(builder.package_addon, "payload", return_value=dict(self.base)):
            return builder.build("0.1.0", output, **kwargs)

    def test_reproducible_hashes_and_explicit_components(self):
        first = self.build(self.root / "one.zip")
        second = self.build(self.root / "two.zip")
        self.assertEqual(first["sha256"], second["sha256"])
        self.assertEqual(first["components"], ["RikUI interface"])
        with zipfile.ZipFile(self.root / "one.zip") as archive:
            manifest = json.loads(archive.read("bundle.json"))
            self.assertEqual(set(manifest["files"]), set(self.base))

    def test_never_overwrites_existing_output(self):
        output = self.root / "keep.zip"
        output.write_bytes(b"keep")
        with self.assertRaisesRegex(ValueError, "Output exists"):
            self.build(output)
        self.assertEqual(output.read_bytes(), b"keep")

    def test_road_input_requires_companions_and_keeps_files(self):
        roads = self.root / "addons/RikUI/generated/roads"
        roads.mkdir(parents=True)
        (roads / "roads.xml").write_text("keep")
        with self.assertRaisesRegex(ValueError, "Missing road patch packs"):
            self.build(self.root / "out.zip", addons=self.root / "addons")
        pack = self.root / "addons/RikUIQuestRoads_W0_P001"
        pack.mkdir()
        (pack / "patch.lua").write_text("keep patch")
        self.build(self.root / "out.zip", addons=self.root / "addons")
        self.assertEqual((roads / "roads.xml").read_text(), "keep")
        self.assertEqual((pack / "patch.lua").read_text(), "keep patch")

    def test_bad_corpus_cannot_create_output(self):
        corpus = self.root / "corpus.zip"
        with zipfile.ZipFile(corpus, "w") as archive:
            archive.writestr("../escape.lua", "bad")
        with self.assertRaisesRegex(ValueError, "unsafe archive path"):
            self.build(self.root / "out.zip", corpus=corpus)
        self.assertFalse((self.root / "out.zip").exists())

if __name__ == "__main__":
    unittest.main()
