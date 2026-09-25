"""Release archives contain exact runtime inputs and are deterministic."""
from pathlib import Path
import hashlib
import json
import os
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import package_addon


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.output = Path(self.temp.name) / "RikUI.zip"
        files = {
            "RikUI.toc": "## Version: 0.1.0\nsrc/core/core.lua\nsrc/ui/media.lua\n",
            "src/core/core.lua": "RikUI = {}\n",
            "src/ui/media.lua": 'local NAMES = { "close" }\n',
            "Bindings.xml": "<Bindings/>",
            "LICENSE": "MIT fixture",
            "media/LICENSES.md": "Media licenses",
            "media/OFL.txt": "Font license",
            "media/font.ttf": "font fixture",
            "media/statusbar.tga": "texture",
            "media/border.tga": "texture",
            "media/checked.tga": "texture",
            "media/highlight.tga": "texture",
            "media/icons/close.svg": "<svg/>",
            "media/icons/close.tga": "icon fixture",
            ".codex/config.toml": "private",
            "tools/private.py": "private",
            "tests/private.lua": "private",
            "RikUIRoads/private.lua": "proprietary",
            "media/build_icons.py": "development",
        }
        for name, text in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="")

    def test_deterministic_inventory_and_hashes(self):
        first = package_addon.build(self.root, self.output)
        original = self.output.read_bytes()
        os.utime(self.root / "src/core/core.lua", (1000000000, 1000000000))
        second = package_addon.build(self.root, self.output)
        self.assertEqual(original, self.output.read_bytes())
        self.assertEqual(first["sha256"], second["sha256"])
        with zipfile.ZipFile(self.output) as archive:
            names = archive.namelist()
            self.assertEqual(names, sorted(names))
            self.assertTrue(all(name.startswith("RikUI/") for name in names))
            self.assertIn("RikUI/media/OFL.txt", names)
            self.assertIn("RikUI/Bindings.xml", names)
            self.assertIn("RikUI/src/core/core.lua", names)
            self.assertNotIn("RikUI/media/icons/close.svg", names)
            self.assertFalse(any("private" in name or ".codex" in name or "build_icons" in name for name in names))
            manifest = json.loads(archive.read("RikUI/package-manifest.json"))
            self.assertEqual(manifest["version"], "0.1.0")
            self.assertEqual(set(names) - {"RikUI/package-manifest.json"}, {"RikUI/" + n for n in manifest["files"]})
            for name, entry in manifest["files"].items():
                data = archive.read("RikUI/" + name)
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry["sha256"])
                self.assertEqual(len(data), entry["bytes"])
        self.assertEqual(package_addon.verify(self.output)["files"], first["files"])

    def test_missing_runtime_preserves_old_archive(self):
        self.output.write_bytes(b"previous")
        (self.root / "src/core/core.lua").unlink()
        with self.assertRaises(ValueError):
            package_addon.build(self.root, self.output)
        self.assertEqual(self.output.read_bytes(), b"previous")

    def test_missing_asset_preserves_old_archive(self):
        self.output.write_bytes(b"previous")
        (self.root / "media/font.ttf").unlink()
        with self.assertRaises(ValueError):
            package_addon.build(self.root, self.output)
        self.assertEqual(self.output.read_bytes(), b"previous")

    def test_parent_traversal_is_rejected(self):
        with (self.root / "RikUI.toc").open("a") as stream:
            stream.write("../outside.lua\n")
        with self.assertRaises(ValueError):
            package_addon.build(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_symlink_asset_is_rejected(self):
        target = self.root / "media/font.ttf"
        target.unlink()
        outside = Path(self.temp.name) / "outside.ttf"
        outside.write_bytes(b"private")
        try:
            target.symlink_to(outside)
        except OSError as error:
            self.skipTest(str(error))
        with self.assertRaises(ValueError):
            package_addon.build(self.root, self.output)

    def test_modified_archive_fails_hash_verification(self):
        package_addon.build(self.root, self.output)
        with zipfile.ZipFile(self.output) as original:
            contents = {n: original.read(n) for n in original.namelist()}
        contents["RikUI/src/core/core.lua"] = b"changed"
        with zipfile.ZipFile(self.output, "w") as archive:
            for name, data in contents.items():
                archive.writestr(name, data)
        with self.assertRaises(ValueError):
            package_addon.verify(self.output)


if __name__ == "__main__":
    unittest.main()

