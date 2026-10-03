"""Exercise the release gate against missing, altered and leaked payloads."""
from pathlib import Path
import sys
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import package_addon
import verify_release
import test_package_addon


class ReleaseTests(unittest.TestCase):
    setUp = test_package_addon.PackageTests.setUp

    def archive(self, mutate=lambda files: None):
        files = package_addon.payload(self.root, "0.0.1-beta.1")
        files.pop(package_addon.MANIFEST)
        files["RikUI/RikUI.toc"] = files["RikUI/RikUI.toc"].replace(
            b"0.0.1-beta.1", b"v0.0.1-beta.1")
        files["RikUI/CHANGELOG.md"] = b"# Release notes\n"
        mutate(files)
        with zipfile.ZipFile(self.output, "w") as archive:
            archive.writestr("RikUI/", b"")
            for name, data in files.items():
                archive.writestr(name, data)

    def verify(self):
        return verify_release.verify_release(self.root, self.output, "v0.0.1-beta.1")

    def test_complete_release(self):
        self.archive()
        self.assertEqual(self.verify()["version"], "v0.0.1-beta.1")

    def test_missing_runtime(self):
        self.archive(lambda files: files.pop("RikUI/src/core/core.lua"))
        with self.assertRaisesRegex(ValueError, "inventory"):
            self.verify()

    def test_development_file_leak(self):
        self.archive(lambda files: files.update({"RikUI/tests/private.lua": b"private"}))
        with self.assertRaisesRegex(ValueError, "inventory"):
            self.verify()

    def test_changed_runtime(self):
        self.archive(lambda files: files.update({"RikUI/src/core/core.lua": b"changed"}))
        with self.assertRaisesRegex(ValueError, "content mismatch"):
            self.verify()

    def test_wrong_tag_version(self):
        self.archive()
        with self.assertRaisesRegex(ValueError, "version"):
            verify_release.verify_release(self.root, self.output, "v0.0.2")

    def test_unexpected_root(self):
        self.archive(lambda files: files.update({"OtherAddon/private.lua": b"private"}))
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.verify()

    def test_packager_ignores_everything_that_is_not_runtime(self):
        """The BigWigs packager copies every tracked path .pkgmeta does not ignore, so a new
        development folder has to be listed there or the release gate stops the release."""
        import subprocess
        project = package_addon.PROJECT
        tracked = subprocess.run(["git", "ls-files"], cwd=project, check=True, capture_output=True,
                                 text=True).stdout.split("\n")
        # The packager skips dot files and dot folders by itself.
        tops = {name.split("/")[0] for name in tracked
                if name and not any(part.startswith(".") for part in name.split("/"))}
        paths, _ = package_addon.inventory(project)
        runtime = {name.split("/")[0] for name in paths} | {"CHANGELOG.md"}
        ignored = set()
        for line in (project / ".pkgmeta").read_text(encoding="utf-8").splitlines():
            entry = line.strip()
            if entry.startswith("- "):
                ignored.add(entry[2:].strip().strip('"').split("/")[0])
        self.assertEqual(sorted(tops - runtime - ignored), [])

    def test_manifest_rejects_packager_eof_loss(self):
        import check_manifest
        source = self.root / "src/core/core.lua"
        source.write_bytes(source.read_bytes().rstrip(b"\r\n") + b"\r")
        self.assertTrue(any("bare carriage return" in failure for failure in check_manifest.check_manifest(self.root)))

    def test_manifest_accepts_portable_eof(self):
        import check_manifest
        source = self.root / "src/core/core.lua"
        source.write_bytes(source.read_bytes().rstrip(b"\r\n") + b"\r\n")
        self.assertFalse(any("bare carriage return" in failure for failure in check_manifest.check_manifest(self.root)))

    def test_line_endings_are_portable(self):
        self.archive(lambda files: files.update({
            "RikUI/src/core/core.lua": files["RikUI/src/core/core.lua"].replace(b"\n", b"\r\n")}))
        self.verify()


if __name__ == "__main__":
    unittest.main()
