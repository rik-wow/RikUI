"""Updater trust boundaries, changing sources, no-op refresh and publication failure."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import export_forever
import quest_corpus
import quest_data_refresh as refresh
import quest_data_release as release
import update_quest_data as updater


class RefreshTests(unittest.TestCase):
    def test_current_version_requires_full_forever_version(self):
        self.assertEqual(refresh.client_version(b"1.60.1.70009\n"), "1.60.1.70009")
        for value in (b"11.2.0.12345", b"1.60.1", b"<html>blocked</html>"):
            with self.assertRaises(ValueError):
                refresh.client_version(value)

    def test_probe_skips_only_identical_sources_and_builder(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            responses = [b"1.60.1.70009", b"ID,UniqueBitFlag,UiQuestDetailsThemeID\n1,1,0\n"]
            previous = root / "latest.json"
            with mock.patch.object(refresh, "resolve_head", return_value="a" * 40), \
                    mock.patch.object(refresh, "builder_hash", return_value="b" * 64), \
                    mock.patch.object(refresh, "download", side_effect=responses * 3), \
                    mock.patch.dict(os.environ, {}, clear=True), mock.patch("builtins.print"):
                self.assertTrue(refresh.probe(root, previous))
                previous.write_bytes((root / "resolution.json").read_bytes())
                self.assertFalse(refresh.probe(root, previous))
                self.assertTrue(refresh.probe(root, previous, force=True))

    def test_export_accepts_only_resolved_clean_revision(self):
        with mock.patch.object(export_forever, "git", side_effect=["a" * 40, ""]):
            export_forever.verify_checkout(Path("."), "a" * 40)
        with mock.patch.object(export_forever, "git", return_value="b" * 40):
            with self.assertRaises(ValueError):
                export_forever.verify_checkout(Path("."), "a" * 40)

    def test_dynamic_provider_provenance_is_retained(self):
        data = {"schemaVersion": 1, "provider": {"revision": "a" * 40, "flavor": "Forever"},
                "base": {key: {} for key in quest_corpus.KINDS}, "variants": []}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "provider.json"
            path.write_text(json.dumps(data))
            self.assertEqual(quest_corpus.load_export(path)[0]["provider"]["revision"], "a" * 40)

    def test_coverage_loss_preserves_previous_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            previous = Path(temporary) / "latest.json"
            previous.write_text('{"coverage":{"quests":100,"mappedObjectives":100,"spawns":100}}')
            before = previous.read_bytes()
            with self.assertRaisesRegex(ValueError, "Coverage fell"):
                refresh.check_regression({"counts": {"quests":90}},
                    {"questCoverage":{"objectivesWithAreas":100},"waypointCoverage":{"exactSpawns":100}}, previous)
            self.assertEqual(previous.read_bytes(), before)

    def test_archive_is_reproducible_and_extracts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder = root / "source"
            folder.mkdir()
            (folder / "example.lua").write_text("return {}")
            refresh.package(folder, root / "one.zip")
            refresh.package(folder, root / "two.zip")
            self.assertEqual((root / "one.zip").read_bytes(), (root / "two.zip").read_bytes())
            updater.unpack(root / "one.zip", root / "out")
            self.assertEqual((root / "out/example.lua").read_text(), "return {}")

    def test_archive_rejects_traversal(self):
        for name in ("../escape", "/absolute", "C:/outside", "../nested/escape"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary)
                with zipfile.ZipFile(path / "bad.zip", "w") as archive:
                    archive.writestr(name, "bad")
                with self.assertRaises(ValueError):
                    updater.unpack(path / "bad.zip", path / "out")

    def test_failed_publication_never_advances_checkpoint(self):
        receipt = {"tag": "quest-data-" + "a" * 24}
        with mock.patch.object(release, "output", side_effect=["true", "b" * 40]), \
                mock.patch.object(release, "validate", return_value=receipt), \
                mock.patch.object(release, "release_exists", return_value=None), \
                mock.patch.object(release, "run", side_effect=RuntimeError("upload unavailable")), \
                mock.patch.object(release, "checkpoint") as checkpoint:
            with self.assertRaises(RuntimeError):
                release.publish("rik-wow/quest-data", Path("dist"))
            checkpoint.assert_not_called()

    def test_public_repo_never_publishes(self):
        with mock.patch.object(release, "output", return_value="false"), mock.patch.object(release, "run") as run:
            with self.assertRaisesRegex(ValueError, "private"):
                release.publish("rik-wow/quest-data", Path("missing"))
            run.assert_not_called()

    def test_release_checksums_reject_tampering(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "latest.json").write_text(json.dumps({"tag":"quest-data-" + "a"*24,"archiveSHA256":"b"*64}))
            (root / "quest-data.zip").write_bytes(b"tampered")
            (root / "SHA256SUMS").write_text("b"*64 + "  quest-data.zip\n")
            with self.assertRaisesRegex(ValueError, "checksum"):
                release.validate(root)


if __name__ == "__main__":
    unittest.main()
