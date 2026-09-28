"""Failure cases for the render gate, independent of a local game installation."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
from validate_capture import validate_capture
from composite import composite_world
from compare import compare_images
from render import verify_client
import fixtures
from fixtures import scenario_script, resolve
from provenance import tree_inputs, stale_reasons, text_digest

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

MODULES = {
    "core": "-- core\nfunction RikRenderCheck(root) end\nfunction RikRenderCenter(frame) end",
    "character": "function RikRenderSpellbook(class) end\nfunction RikRenderPlayer(class) RikRenderSpellbook(class) end",
    "hud": "function RikRenderHUDState(class) RikRenderPlayer(class) end",
    "questing": "local QUESTS = {}\nRikRenderElwynnQuests = QUESTS\nfunction RikRenderQuestLog() end",
}

class ScriptChecks(unittest.TestCase):
    def test_fixtures_and_sequence_value_enter_the_script(self):
        case = {"id": "s", "frame": "Demo", "fixtures": ["RikRenderSpellbook()"], "lua": "Open()",
                "sequence": {"values": [0.8, True, "big"], "apply": "RikRenderSetOption('general','scale', VALUE)"}}
        modules = {**MODULES, "core": MODULES["core"] + "\nfunction RikRenderSetOption() end"}
        script = scenario_script(case, modules, "1.60.1.70009", 0.8)
        self.assertIn("RikRenderSpellbook()\n", script)
        self.assertIn('RikRenderClient = { version = "1.60.1", build = "70009" }', script)
        self.assertLess(script.index("scale', 0.8"), script.index("Open()"), "the setting applies before the scenario composes the frame")
        self.assertIn("scale', true)", scenario_script(case, modules, None, True))
        self.assertIn('scale\', "big")', scenario_script(case, modules, None, "big"))

    def test_only_the_modules_a_scenario_reaches_join_its_script(self):
        self.assertEqual(resolve({"id": "a", "lua": "RikRenderCenter(Demo)"}, MODULES), ["core"])
        self.assertEqual(resolve({"id": "b", "fixtures": ["RikRenderHUDState('ROGUE')"]}, MODULES), ["core", "character", "hud"])
        self.assertEqual(resolve({"id": "c", "lua": "local q = RikRenderElwynnQuests"}, MODULES), ["core", "questing"])
        script = scenario_script({"id": "c", "frame": "Demo", "lua": "RikRenderQuestLog()"}, MODULES, None)
        self.assertNotIn("RikRenderSpellbook", script)

    def test_unknown_fixture_names_fail_before_a_render(self):
        with self.assertRaisesRegex(RuntimeError, "unknown fixture RikRenderMissing"):
            resolve({"id": "x", "lua": "RikRenderMissing()"}, MODULES)
        with self.assertRaisesRegex(RuntimeError, "defined in both"):
            resolve({"id": "x", "lua": ""}, {**MODULES, "extra": "function RikRenderCheck() end"})

    def test_prelude_globals_are_not_fixtures(self):
        self.assertEqual(resolve({"id": "w", "lua": "if RikRenderWorld then RikRenderClient = nil end"}, MODULES), ["core"])

    def test_holder_names_in_strings_and_comments_are_not_fixtures(self):
        case = {"id": "h", "lua": 'CreateFrame("Frame", "RikRenderHUD", UIParent) -- RikRenderMissing\nlocal s = \'RikRenderNope\''}
        self.assertEqual(resolve(case, MODULES), ["core"])

    def test_apostrophes_in_comments_do_not_hide_references(self):
        modules = {**MODULES, "windows": "-- A vendor's goods: the bag fixture's items, priced.\nfunction RikRenderVendor() RikRenderQuestLog() end\n-- it's [[not]] a string\nlocal s = [[RikRenderLong]]"}
        self.assertEqual(resolve({"id": "v", "lua": "RikRenderVendor()"}, modules), ["core", "questing", "windows"])
        from fixtures import scan_lua, holders
        code, strings = scan_lua('a("x\\"y") -- don\'t\nb(\'z\') --[[ RikRenderNo ]] c([[w]])')
        self.assertEqual(strings, ['x\\"y', "z", "w"])
        self.assertNotIn("RikRenderNo", code)
        self.assertEqual(holders("f('RikRenderHold') -- RikRenderComment"), {"RikRenderHold"})

    def test_holder_frames_reached_as_globals_resolve_to_their_creator(self):
        # A scenario that names a holder and then uses it, and one that uses a holder a module creates.
        case = {"id": "g", "lua": 'RikRenderGroup("RikRenderBars", {}, 0, 0, 1, 1)\nRikRenderResize(RikRenderBars)'}
        modules = {**MODULES, "core": MODULES["core"] + "\nfunction RikRenderGroup() end\nfunction RikRenderResize() end"}
        self.assertEqual(resolve(case, modules), ["core"])
        modules["questing"] += '\nfunction RikRenderPlannerArrow() CreateFrame("Frame", "RikRenderArrow") end'
        self.assertEqual(resolve({"id": "a", "lua": "RikRenderArrow:Show()"}, modules), ["core", "questing"])

class ProvenanceChecks(unittest.TestCase):
    def setUp(self):
        self.case = {"id": "s", "page": "demo", "frame": "Demo", "crop": "8x8+0+0", "lua": "RikRenderQuestLog()"}
        self.addon = {"src/a.lua": "1"}
        self.inputs = tree_inputs(self.case, scenario_script(self.case, MODULES, None), self.addon)
        self.capture = {**self.case, "inputs": {**self.inputs, "renderer": {"binary": "b"}}}
        self.current = {**self.inputs, "renderer": {"binary": "b"}}

    def test_an_unchanged_capture_is_current(self):
        self.assertEqual(stale_reasons(self.case, self.capture, self.current), [])
        self.assertEqual(stale_reasons(self.case, None, self.current), ["missing"])

    def test_editing_an_unused_module_leaves_the_capture_current(self):
        modules = {**MODULES, "hud": MODULES["hud"] + "\n-- changed"}
        inputs = tree_inputs(self.case, scenario_script(self.case, modules, None), self.addon)
        self.assertEqual(inputs["script"], self.inputs["script"])

    def test_editing_a_used_module_or_the_addon_marks_the_capture_stale(self):
        modules = {**MODULES, "questing": MODULES["questing"] + "\n-- changed"}
        inputs = tree_inputs(self.case, scenario_script(self.case, modules, None), self.addon)
        self.assertEqual(stale_reasons(self.case, self.capture, {**self.current, "script": inputs["script"]}), ["script"])
        other = tree_inputs(self.case, scenario_script(self.case, MODULES, None), {"src/a.lua": "2"})
        self.assertEqual(stale_reasons(self.case, self.capture, {**self.current, "addon": other["addon"]}), ["addon"])

    def test_environment_and_scenario_changes_mark_the_capture_stale(self):
        self.assertEqual(stale_reasons(self.case, self.capture, {**self.current, "renderer": {"binary": "c"}}), ["renderer"])
        self.assertEqual(stale_reasons({**self.case, "crop": "9x9+0+0"}, self.capture, self.current), ["scenario"])
        self.assertEqual(stale_reasons(self.case, {**self.capture, "corpus": True}, self.current), ["scenario"])

    def test_the_script_digest_is_the_text_digest(self):
        script = scenario_script(self.case, MODULES, None)
        self.assertEqual(self.inputs["script"], text_digest(script))

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
        from check import digest
        self.case = {"id": "sample", "page": "demo", "frame": "Demo", "lua": "RikRenderCheck(Demo)"}
        self.expected = tree_inputs(self.case, scenario_script(self.case, MODULES, None), {})
        self.capture = dict(self.case, filename="sample.webp", sha256=digest(self.directory / "sample.webp"),
                            inputs=dict(self.expected, renderer={}, client={}), diagnostics={"visibleTextCount": 1})
        self.capture["reviewedSha256"] = self.capture["sha256"]

    def errors(self):
        from check import verify_capture
        errors = []
        verify_capture(self.case, self.capture, self.expected, self.directory, errors, {})
        return errors

    def test_reviewed_capture(self):
        self.assertEqual(self.errors(), [])

    def test_changed_pixels(self):
        (self.directory / "sample.webp").write_bytes(b"changed")
        self.assertTrue(any("changed image" in error for error in self.errors()))

    def test_unreviewed_image(self):
        self.capture.pop("reviewedSha256")
        self.assertTrue(any("visual review" in error for error in self.errors()))

    def test_stale_inputs_name_the_input(self):
        self.capture["inputs"]["script"] = "previous"
        self.assertIn("Stale capture sample: script", self.errors())
        self.capture["inputs"]["seed"] = "previous"
        self.assertIn("Stale capture sample: script, seed", self.errors())

    def test_changed_scenario(self):
        self.case["title"] = "New state"
        self.assertTrue(any("Stale capture sample: scenario" in error for error in self.errors()))

    def test_mixed_environment(self):
        from check import verify_environment
        manifest = {"renderer": {"binary": "b", "patch": "p"}, "client": {"version": "v", "foreverCommit": "c", "executableSha256": "e"},
                    "renders": [{"id": "one", "inputs": {"renderer": {"binary": "b", "patch": "p"}, "client": {"version": "v", "foreverCommit": "c", "executableSha256": "e"}}},
                                {"id": "two", "inputs": {"renderer": {"binary": "old", "patch": "p"}, "client": {"version": "v", "foreverCommit": "c", "executableSha256": "e"}}}]}
        errors = []
        with patch("check.digest", return_value="p"):
            verify_environment(manifest, errors)
        self.assertEqual(errors, ["Mixed render environment: two"])

    def test_world_plate_must_match_its_record(self):
        import check
        from check import digest
        plate = self.directory / "field.jpg"
        plate.write_bytes(b"plate pixels")
        record = {"file": "field.jpg", "sha256": digest(plate)}
        (self.directory / "field.json").write_text(json.dumps(record))
        self.case["world"] = self.capture["world"] = {"plate": "field"}
        self.capture["plate"] = {"plate": "field", "sha256": record["sha256"]}
        with patch.object(check, "WORLDS", self.directory), patch("provenance.WORLDS", self.directory):
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
        self.assertEqual([e for e in self.errors() if "Stale" not in e], [])
        self.capture["frames"].pop()
        self.assertTrue(any("Sequence values changed" in error for error in self.errors()))

class ModuleChecks(unittest.TestCase):
    def test_real_modules_resolve_every_catalogued_scenario(self):
        modules = fixtures.load_modules()
        cases = json.loads((fixtures.FIXTURES / "scenarios.json").read_text(encoding="utf-8"))
        used = set()
        for case in cases:
            used.update(resolve(case, modules))
        self.assertEqual(sorted(used), sorted(modules), "every fixture module is used by some scenario")

if __name__ == "__main__":
    unittest.main()
