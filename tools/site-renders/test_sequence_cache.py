"""Sequence reuse must preserve provenance and reject affected or damaged pixels."""
import copy
import tempfile
import unittest
from pathlib import Path
from dependencies import compact_inventories, addon_inputs
from fixtures import scenario_script
from provenance import tree_inputs, environment_inputs, capture_key, digest, text_digest
from sequence_cache import reusable_frame, value_case
from check import expected_tree_inputs, verify_environment

class SequenceCacheChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.modules = {"core": "", "atlas": "function RikRenderStudioAtlas(value) end"}
        self.case = {"id":"atlas", "page":"studio-atlas", "frame":"RikUIBar_main",
                     "crop":"600x300+0+0", "fixtures":[], "lua":"",
                     "sequence":{"values":["nameplates","main"],"default":"main",
                                 "apply":"RikRenderStudioAtlas(VALUE)",
                                 "frames":{"nameplates":"RikRenderStudioPlates","main":"RikUIBar_main"}}}
        self.files = {"src/ui/skin.lua":"skin","src/modules/nameplates/nameplates.lua":"options",
                      "src/modules/nameplates/nameplates-skin.lua":"plate"}
        self.client = {"version":"1.60.1.70205","foreverCommit":"source","executableSha256":"exe"}
        self.inputs = {**tree_inputs(self.case,scenario_script(self.case,self.modules,self.client["version"]),self.files),
                       **environment_inputs({"binary":"renderer","patch":"patch"},self.client)}
        frames = []
        for value in self.case["sequence"]["values"]:
            path = self.directory / (value+".webp")
            path.write_bytes(value.encode())
            frames.append({"value":value,"filename":path.name,"sha256":digest(path),
                "fixtureSha256":text_digest(scenario_script(self.case,self.modules,self.client["version"],value))})
        self.previous = {**copy.deepcopy(self.case),"inputs":self.inputs,"key":capture_key(self.inputs),"frames":frames}
        self.manifest = {"renders":[self.previous]}
    def reuse(self,value,files=None):
        return reusable_frame(self.case,value,self.previous,self.manifest,self.modules,files or self.files,self.directory)
    def test_plate_change_reuses_only_unaffected_component_and_original_evidence(self):
        changed={**self.files,"src/modules/nameplates/nameplates-skin.lua":"changed"}
        self.assertIsNone(self.reuse("nameplates",changed))
        reused=self.reuse("main",changed)
        self.assertIsNotNone(reused)
        self.assertEqual(reused["inputs"],self.inputs)
        self.assertEqual(reused["key"],self.previous["key"])
        reused["inputs"]["client"]["version"]="mutated"
        self.assertEqual(self.inputs["client"]["version"],self.client["version"])
    def test_windows_fixture_bytes_reuse_without_relabeling_hash(self):
        frame=self.previous["frames"][1]
        script=scenario_script(self.case,self.modules,self.client["version"],"main")
        frame["fixtureSha256"]=text_digest(script.replace("\n","\r\n"))
        reused=self.reuse("main")
        self.assertIsNotNone(reused)
        self.assertEqual(reused["fixtureSha256"],frame["fixtureSha256"])
    def test_missing_environment_never_reuses_pixels(self):
        self.inputs["client"].pop("executableSha256")
        self.previous["key"]=capture_key(self.inputs)
        self.assertIsNone(self.reuse("main"))
        errors=[];verify_environment({"renders":[{"id":"missing"}]},errors)
        self.assertTrue(any("Missing render environment" in e for e in errors))
    def test_shared_source_fixture_seed_and_scenario_changes_expire_pixels(self):
        self.assertIsNone(self.reuse("main",{**self.files,"src/ui/skin.lua":"changed"}))
        old=self.inputs["seed"];self.inputs["seed"]="changed";self.previous["key"]=capture_key(self.inputs)
        self.assertIsNone(self.reuse("main"))
        self.inputs["seed"]=old;self.previous["key"]=capture_key(self.inputs)
        self.modules["atlas"] += "\n-- changed fixture"
        self.assertIsNone(self.reuse("main"))
        self.case["crop"]="500x300+0+0"
        self.assertIsNone(self.reuse("main"))
    def test_corrupt_pixels_geometry_script_or_inventory_are_never_reused(self):
        frame=self.previous["frames"][1]
        old=frame["fixtureSha256"];frame["fixtureSha256"]="bad"
        self.assertIsNone(self.reuse("main"));frame["fixtureSha256"]=old
        self.previous["key"]="bad"
        self.assertIsNone(self.reuse("main"));self.previous["key"]=capture_key(self.inputs)
        (self.directory/"main.webp").write_bytes(b"damaged")
        self.assertIsNone(self.reuse("main"))
    def test_compaction_and_gate_authenticate_original_frame_inventory(self):
        reused=self.reuse("main")
        self.previous["frames"][1]=reused
        compact_inventories(self.manifest)
        self.assertNotIn("addonFiles",reused["inputs"])
        errors=[];verify_environment(self.manifest,errors);self.assertEqual(errors,[])
        changed={**self.files,"src/modules/nameplates/nameplates-skin.lua":"changed"}
        expected=expected_tree_inputs(value_case(self.case,"main"),self.manifest,self.modules,changed,reused)
        self.assertEqual(expected["addon"],reused["inputs"]["addon"])
        reused["key"]="bad";verify_environment(self.manifest,errors)
        self.assertTrue(any("Changed capture provenance" in e for e in errors))
    def test_known_absent_plates_are_excluded_but_options_and_unknowns_remain(self):
        for page in ("wizard","layout","overview","setup-studio","studio-gallery"):
            self.assertNotIn("src/modules/nameplates/nameplates-skin.lua",addon_inputs({"page":page},self.files))
        self.assertIn("src/modules/nameplates/nameplates.lua",addon_inputs({"page":"options"},self.files))
        for case in ({"page":"future"},{"page":"nameplates"},{"page":"layout","lua":"RikRenderNameplates({})"}):
            self.assertIn("src/modules/nameplates/nameplates-skin.lua",addon_inputs(case,self.files))
