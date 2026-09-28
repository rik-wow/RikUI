"""Failure cases for the render gate, independent of a local game installation."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
from validate_capture import validate_capture, compare_images, composite_world
from render import verify_client, scenario_script

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

    def test_crop_outside_screen(self):
        with self.assertRaisesRegex(RuntimeError, "exceeds the screen"):
            validate_capture({**self.case, "screen": "60x40"}, self.image, self.tree)

    def test_transparent_layer_must_draw_something(self):
        Image.new("RGBA", (64, 40), (0, 0, 0, 0)).save(self.image, lossless=True)
        with self.assertRaisesRegex(RuntimeError, "blank"):
            validate_capture(self.case, self.image, self.tree)
        layer = Image.new("RGBA", (64, 40), (0, 0, 0, 0))
        layer.paste(Image.effect_noise((40, 20), 80).convert("RGBA"), (12, 10))
        layer.save(self.image, lossless=True)
        self.assertGreaterEqual(validate_capture(self.case, self.image, self.tree)["uniqueColors"], 30)

    def test_world_composite_keeps_the_plate_where_the_layer_is_clear(self):
        layer = Image.new("RGBA", (64, 40), (0, 0, 0, 0))
        layer.paste((255, 255, 255, 255), (0, 0, 32, 40))
        layer.save(self.image, lossless=True)
        plate = Path(self.temp.name) / "plate.jpg"
        Image.new("RGB", (128, 80), (0, 200, 0)).save(plate, quality=95)
        output = Path(self.temp.name) / "out.webp"
        result = composite_world(self.image, plate, {**self.case, "screen": "128x80"}, output)
        self.assertEqual(result.getpixel((8, 8)), (255, 255, 255))
        self.assertLess(abs(result.getpixel((56, 8))[1] - 200), 6)
        self.assertTrue(output.is_file())

    def test_pixel_changes_create_a_diff(self):
        other = self.image.with_name("other.webp")
        Image.new("RGB", (64, 40), "black").save(other, lossless=True)
        diff = self.image.with_name("diff.png")
        self.assertTrue(compare_images(self.image, other, diff)["changed"])
        self.assertTrue(diff.is_file())
        self.assertFalse(compare_images(self.image, self.image, diff)["changed"])

class ScriptChecks(unittest.TestCase):
    def test_fixtures_and_sequence_value_enter_the_script(self):
        case = {"id": "s", "frame": "Demo", "fixtures": ["RikRenderSpellbook()"], "lua": "Open()",
                "sequence": {"values": [0.8, True, "big"], "apply": "RikRenderSetOption('general','scale', VALUE)"}}
        script = scenario_script(case, "-- common", 0.8)
        self.assertIn("RikRenderSpellbook()\n", script)
        self.assertLess(script.index("scale', 0.8"), script.index("Open()"), "the setting applies before the scenario composes the frame")
        self.assertIn("scale', true)", scenario_script(case, "", True))
        self.assertIn('scale\', "big")', scenario_script(case, "", "big"))

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

    def test_world_plate_must_match_its_record(self):
        import check
        from check import digest
        plate = self.directory / "field.jpg"
        plate.write_bytes(b"plate pixels")
        record = {"file": "field.jpg", "sha256": digest(plate)}
        (self.directory / "field.json").write_text(json.dumps(record))
        self.case["world"] = self.capture["world"] = {"plate": "field"}
        self.capture["plate"] = {"plate": "field", "sha256": record["sha256"]}
        with patch.object(check, "WORLDS", self.directory):
            self.assertEqual(self.errors(), [])
            plate.write_bytes(b"other pixels")
            self.assertTrue(any("World plate does not match" in error for error in self.errors()))
            self.capture["plate"]["plate"] = "meadow"
            self.assertTrue(any("World plate changed" in error for error in self.errors()))

    def test_sequence_frames_are_each_reviewed_and_distinct(self):
        frame = lambda value: {**{k: self.capture[k] for k in ("filename", "sha256", "reviewedSha256", "diagnostics")}, "value": value}
        self.case["sequence"] = {"values": [0.8, 1.2], "apply": "x"}
        self.capture["sequence"] = self.case["sequence"]
        self.capture["frames"] = [frame(0.8), frame(1.2)]
        errors = self.errors()
        self.assertTrue(any("Identical states: sample@0.8 and sample@1.2" in error for error in errors))
        (self.directory / "other.webp").write_bytes(b"second frame")
        from check import digest
        self.capture["frames"][1].update(filename="other.webp", sha256=digest(self.directory / "other.webp"))
        self.assertTrue(any("visual review: sample@1.2" in error for error in self.errors()))
        self.capture["frames"][1]["reviewedSha256"] = self.capture["frames"][1]["sha256"]
        self.assertEqual(self.errors(), [])
        self.capture["frames"].pop()
        self.assertTrue(any("Sequence values changed" in error for error in self.errors()))

if __name__ == "__main__":
    unittest.main()
