"""Failure cases for the render gate, independent of a local game installation."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
from validate_capture import validate_capture, compare_images
from render import verify_client

class CaptureChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.image = Path(self.temp.name) / "capture.webp"
        Image.effect_noise((64, 40), 80).convert("RGB").save(self.image, lossless=True)
        self.case = {"id": "sample", "frame": "Demo", "crop": "64x40+0+0", "expectText": ["Ready"]}
        self.tree = ('=== Frame Tree ===\nDemo [Frame] (40x20) visible MEDIUM:1 x=12, y=10, alpha=1.00\n'
                     '  Label [FontString] (32x14) visible MEDIUM:2 x=16, y=12, alpha=1.00 text="Ready"')

    def test_valid_capture(self):
        self.assertEqual(validate_capture(self.case, self.image, self.tree)["visibleTextCount"], 1)

    def test_missing_expected_text(self):
        with self.assertRaisesRegex(RuntimeError, "missing visible text"):
            validate_capture(self.case, self.image, self.tree.replace("Ready", "Waiting"))

    def test_zero_height_text(self):
        with self.assertRaisesRegex(RuntimeError, "text has no area"):
            validate_capture(self.case, self.image, self.tree.replace("(32x14)", "(32x0)"))

    def test_clipped_root(self):
        with self.assertRaisesRegex(RuntimeError, "crop clips"):
            validate_capture(self.case, self.image, self.tree.replace("(40x20)", "(80x20)"))

    def test_hidden_root(self):
        with self.assertRaisesRegex(RuntimeError, "root missing or hidden"):
            validate_capture(self.case, self.image, self.tree.replace("visible", "hidden"))

    def test_blank_pixels(self):
        Image.new("RGB", (64, 40), "#0c1117").save(self.image, lossless=True)
        with self.assertRaisesRegex(RuntimeError, "blank"):
            validate_capture(self.case, self.image, self.tree)

    def test_pixel_changes_create_a_diff(self):
        other = self.image.with_name("other.webp")
        Image.new("RGB", (64, 40), "black").save(other, lossless=True)
        diff = self.image.with_name("diff.png")
        self.assertTrue(compare_images(self.image, other, diff)["changed"])
        self.assertTrue(diff.is_file())
        self.assertFalse(compare_images(self.image, self.image, diff)["changed"])

class ClientChecks(unittest.TestCase):
    def test_stale_source(self):
        with patch("render.checked", side_effect=["current refs/heads/forever", "stale"]):
            with self.assertRaisesRegex(RuntimeError, "checkout is stale"):
                verify_client(Path("unused"), Path("unused"))

    def test_modified_source(self):
        with patch("render.checked", side_effect=["current refs/heads/forever", "current", " M version.txt"]):
            with self.assertRaisesRegex(RuntimeError, "local edits"):
                verify_client(Path("unused"), Path("unused"))

    def test_mismatched_installed_client(self):
        with patch("render.checked", side_effect=["current refs/heads/forever", "current", "", "1.2.3.4", "1.2.3.5"]):
            with self.assertRaisesRegex(RuntimeError, "Client/source mismatch"):
                verify_client(Path("unused"), Path("unused"))

class EvidenceChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        (self.directory / "sample.webp").write_bytes(b"reviewed image")
        from check import digest, FIXTURES
        self.case = {"id": "sample", "page": "demo"}
        self.manifest = {"generation": "current", "client": {"foreverCommit": "current"}}
        self.capture = dict(self.case, generation="current", filename="sample.webp",
                            sha256=digest(self.directory / "sample.webp"),
                            client=self.manifest["client"], seedSha256=digest(FIXTURES / "seed.lua"),
                            diagnostics={"visibleTextCount": 1})
        self.capture["reviewedSha256"] = self.capture["sha256"]

    def errors(self):
        from check import verify_capture
        errors = []
        verify_capture(self.case, self.capture, self.manifest, self.directory, errors, {})
        return errors

    def test_reviewed_capture(self):
        self.assertEqual(self.errors(), [])

    def test_changed_pixels(self):
        (self.directory / "sample.webp").write_bytes(b"changed")
        self.assertTrue(any("changed image" in error for error in self.errors()))

    def test_unreviewed_image(self):
        self.capture.pop("reviewedSha256")
        self.assertTrue(any("visual review" in error for error in self.errors()))

    def test_mixed_generation(self):
        self.capture["generation"] = "previous"
        self.assertTrue(any("generation" in error for error in self.errors()))

    def test_changed_provenance(self):
        from check import verify_generation
        manifest = dict(addonFiles={}, fixtureFiles={"wow-ui-sim.patch": "patch"},
                        rendererBinarySha256="binary", rendererCommit="renderer",
                        rendererPatchSha256="patch", generation="incorrect",
                        client=dict(version="version", foreverCommit="source",
                                    executableSha256="executable", cache={}))
        errors = []
        verify_generation(manifest, errors)
        self.assertIn("Render provenance changed after capture", errors)

    def test_changed_scenario(self):
        self.case["title"] = "New state"
        self.assertTrue(any("Scenario changed" in error for error in self.errors()))

if __name__ == "__main__":
    unittest.main()

