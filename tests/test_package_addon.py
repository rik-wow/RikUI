"""Release archives contain exact runtime inputs and are deterministic."""
from pathlib import Path
import hashlib
import json
import os
import sys
import subprocess
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

    def rewrite_archive(self, mutate, links=()):
        package_addon.build(self.root, self.output)
        with zipfile.ZipFile(self.output) as archive:
            contents = {name: archive.read(name) for name in archive.namelist() if name != package_addon.MANIFEST}
        mutate(contents)
        manifest = {"format": 1, "version": "0.1.0", "files": {
            name.removeprefix("RikUI/"): {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            for name, data in contents.items()
        }}
        contents[package_addon.MANIFEST] = json.dumps(manifest).encode()
        with zipfile.ZipFile(self.output, "w") as archive:
            for name, data in contents.items():
                info = zipfile.ZipInfo(name)
                info.create_system = 3
                info.external_attr = (0o120777 if name in links else 0o100644) << 16
                archive.writestr(info, data)

    def test_rejects_ambiguous_install_paths(self):
        for name in ("RikUI/media//extra.tga", "RikUI/media/./extra.tga",
                     "RikUI/media/extra.tga.", "RikUI/media/CON.tga", "RikUI/media/a|b.tga",
                     "RikUI/media/FONT.ttf"):
            with self.subTest(name=name):
                self.rewrite_archive(lambda files: files.update({name: b"extra"}))
                with self.assertRaises(ValueError):
                    package_addon.verify(self.output)

    def test_rejects_symlink_archive_members(self):
        name = "RikUI/media/font.ttf"
        self.rewrite_archive(lambda files: None, links=(name,))
        with self.assertRaises(ValueError):
            package_addon.verify(self.output)

    def test_requires_assets_and_toc_sources_even_with_matching_hashes(self):
        for name in ("RikUI/media/font.ttf", "RikUI/src/core/core.lua", "RikUI/RikUI.toc"):
            with self.subTest(name=name):
                self.rewrite_archive(lambda files: files.pop(name))
                with self.assertRaises(ValueError):
                    package_addon.verify(self.output)

    def test_rejects_unexpected_payload_even_with_matching_hashes(self):
        self.rewrite_archive(lambda files: files.update({"RikUI/private.txt": b"private"}))
        with self.assertRaises(ValueError):
            package_addon.verify(self.output)

    def test_rejects_duplicate_manifest_fields(self):
        package_addon.build(self.root, self.output)
        with zipfile.ZipFile(self.output) as archive:
            contents = {name: archive.read(name) for name in archive.namelist()}
        contents[package_addon.MANIFEST] = contents[package_addon.MANIFEST].replace(
            b'"format": 1', b'"format": 0, "format": 1')
        with zipfile.ZipFile(self.output, "w") as archive:
            for name, data in contents.items():
                archive.writestr(name, data)
        with self.assertRaises(ValueError):
            package_addon.verify(self.output)

    def test_explicit_version_is_reproducible_and_source_is_unchanged(self):
        toc = self.root / "RikUI.toc"
        toc.write_bytes(b"\xef\xbb\xbf" + toc.read_bytes().replace(b"\n", b"\r\n"))
        original = toc.read_bytes()
        first = package_addon.build(self.root, self.output, version="0.2.0-beta.1+fixture")
        archive_bytes = self.output.read_bytes()
        second = package_addon.build(self.root, self.output, version="0.2.0-beta.1+fixture")
        self.assertEqual(archive_bytes, self.output.read_bytes())
        self.assertEqual(first, second)
        self.assertEqual(toc.read_bytes(), original)
        self.assertEqual(first["version"], "0.2.0-beta.1+fixture")
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(archive.read("RikUI/RikUI.toc"),
                             original.replace(b"0.1.0", b"0.2.0-beta.1+fixture"))

    def test_invalid_version_preserves_existing_archive(self):
        for version in ("", "01.0.0", "1.2", "1.0.0-01", "1.0.0-.", "1.0.0\n## Title: changed", "x" * 65):
            with self.subTest(version=version):
                self.output.write_bytes(b"previous")
                with self.assertRaises(ValueError):
                    package_addon.build(self.root, self.output, version=version)
                self.assertEqual(self.output.read_bytes(), b"previous")

    def test_archive_version_must_match_toc(self):
        def change(files):
            files["RikUI/RikUI.toc"] = files["RikUI/RikUI.toc"].replace(b"0.1.0", b"0.9.0")
        self.rewrite_archive(change)
        with self.assertRaises(ValueError):
            package_addon.verify(self.output)

    def test_missing_or_duplicate_toc_version_preserves_archive(self):
        toc = self.root / "RikUI.toc"
        original = toc.read_bytes()
        for content in (original.replace(b"## Version: 0.1.0\n", b""),
                        original + b"## Version: 0.1.0\n"):
            with self.subTest(content=content):
                toc.write_bytes(content)
                self.output.write_bytes(b"previous")
                with self.assertRaises(ValueError):
                    package_addon.build(self.root, self.output, version="0.2.0")
                self.assertEqual(self.output.read_bytes(), b"previous")

    def test_verify_cli_rejects_version_override(self):
        package_addon.build(self.root, self.output)
        original = self.output.read_bytes()
        result = subprocess.run([sys.executable, str(Path(package_addon.__file__)),
            "--verify", str(self.output), "--version", "0.2.0"], text=True, capture_output=True, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be combined", result.stderr)
        self.assertEqual(self.output.read_bytes(), original)

    def test_version_cli_stamps_candidate(self):
        result = subprocess.run([sys.executable, str(Path(package_addon.__file__)),
            "--root", str(self.root), "--output", str(self.output), "--version", "0.2.0-rc.1"],
            text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["version"], "0.2.0-rc.1")
        self.assertEqual(package_addon.verify(self.output)["version"], "0.2.0-rc.1")

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

