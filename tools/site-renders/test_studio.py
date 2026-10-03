"""Studio fixture data and dependency boundaries."""
import subprocess
import unittest
from pathlib import Path
import render
from dependencies import addon_inputs
class StudioChecks(unittest.TestCase):
    def test_fixture_literal_is_data_even_with_quotes_control_and_utf8(self):
        value='quoted " and \\; café\n\x00 after'
        literal=render.lua_data(value)
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            script=Path(temp)/"literal.lua"
            script.write_text("local s="+literal+'; for i=1,#s do io.write(string.format("%02x",s:byte(i))) end',encoding="utf-8")
            result=subprocess.run(["luajit",str(script)],capture_output=True,check=True)
        self.assertEqual(result.stdout.decode(),value.encode().hex())
        with self.assertRaises((ValueError,RuntimeError)):
            render.lua_data(float("nan"))
    def test_studio_contract_does_not_expire_ordinary_component_pixels(self):
        files={"src/setup/setup-pack.lua":"before","src/setup/setup-studio.lua":"before","src/ui/skin.lua":"same"}
        changed={**files,"src/setup/setup-pack.lua":"after"}
        self.assertEqual(addon_inputs({"page":"unitframes"},files),addon_inputs({"page":"unitframes"},changed))
        for page in ("setup-studio","studio-gallery"):
            self.assertNotEqual(addon_inputs({"page":page},files),addon_inputs({"page":page},changed))
        for page in ("wizard","options","layout","sharing","overview","studio-atlas"):
            self.assertEqual(addon_inputs({"page":page},files),addon_inputs({"page":page},changed))
        self.assertNotEqual(addon_inputs({"page":"unitframes"},files),addon_inputs({"page":"unitframes"},{**files,"src/ui/skin.lua":"after"}))
    def test_atlas_keeps_native_inputs_without_uninvoked_studio_operations(self):
        files={"src/setup/setup-studio.lua":"journal","src/configuration/options/setup-studio-view.lua":"window","src/ui/skin.lua":"skin","src/modules/chat/chat-move.lua":"chat","src/setup/setup-pack.lua":"contract"}
        self.assertEqual(set(addon_inputs({"page":"studio-atlas"},files)),{"src/ui/skin.lua","src/modules/chat/chat-move.lua"})
        self.assertEqual(addon_inputs({"page":"studio-gallery"},files),files)
    def test_atlas_fixtures_do_not_invoke_excluded_pack_operations(self):
        import json
        directory=Path(__file__).parent
        cases=json.loads((directory/"scenarios.json").read_text())
        for case in cases:
            if case.get("page")=="studio-atlas":
                self.assertEqual(case.get("fixtures"),[])
                self.assertEqual(case.get("lua"),"")
                self.assertIn(case["sequence"]["apply"],("RikRenderStudioAtlas(VALUE)","RikRenderStudioExtra(VALUE)","RikRenderStudioModules(VALUE)","RikRenderStudioGrids(VALUE)"))
        # Review only invoked fixture bodies, not unused Studio functions in the same module.
        atlas=(directory/"fixtures/studio.lua").read_text().split("function RikRenderStudioAtlas",1)[1]
        extra=(directory/"fixtures/studio-components.lua").read_text().split("-- Assert positions",1)[0]
        for invoked in (atlas,extra):
            self.assertNotIn("RikUI.SetupPack",invoked)
            self.assertNotIn("RikUI.Studio",invoked)
    def test_module_variants_track_contract_and_hidden_banners_do_not_expire_components(self):
        files={"src/setup/setup-pack.lua":"pack","src/setup/setup-pack-library.lua":"recipes",
               "src/setup/setup-studio.lua":"window","src/ui/skin.lua":"skin","src/modules/banners/banners.lua":"banner"}
        case={"page":"studio-atlas","sequence":{"apply":"RikRenderStudioModules(VALUE)"}}
        inputs=addon_inputs(case,files)
        self.assertEqual(set(inputs),{"src/setup/setup-pack.lua","src/setup/setup-pack-library.lua","src/ui/skin.lua"})
        self.assertNotEqual(inputs,addon_inputs(case,{**files,"src/setup/setup-pack.lua":"changed"}))
        for page in ("studio-gallery","setup-studio","studio-atlas","wizard","options","layout","overview"):
            self.assertEqual(addon_inputs({"page":page},files),addon_inputs({"page":page},{**files,"src/modules/banners/banners.lua":"changed"}))
        for case in ({"page":"banners"},{"page":"studio-gallery","lua":'RikRenderObjectiveBanner("Quest")'}):
            self.assertNotEqual(addon_inputs(case,files),addon_inputs(case,{**files,"src/modules/banners/banners.lua":"changed"}))
    def test_component_gate_requires_identity_bounds_and_retains_ordinary_duplicate_checks(self):
        import tempfile
        from check import verify_frame
        from provenance import digest
        from PIL import Image
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);image=directory/"native.webp"
            Image.effect_noise((64,40),80).convert("RGB").save(image,lossless=True)
            sha=digest(image)
            frame={"filename":image.name,"sha256":sha,"reviewedSha256":sha,"width":64,"height":40,"diagnostics":{"visibleTextCount":0},"value":"bar4","components":{"bar4":{"x":12,"y":8,"width":20,"height":16}}}
            case={"id":"atlas","page":"studio-atlas","sequence":{"frames":{"bar4":"NativeBar4","bar5":"NativeBar5"}}}
            errors=[];hashes={}
            verify_frame(case,case,frame,directory,errors,hashes)
            second={**frame,"value":"bar5","components":{"bar5":frame["components"]["bar4"]}}
            verify_frame(case,case,second,directory,errors,hashes);self.assertEqual(errors,[])
            verify_frame(case,case,{**frame,"components":{}},directory,errors,{})
            self.assertTrue(any("component identity" in e for e in errors))
            errors=[]
            verify_frame(case,case,{**frame,"components":{"bar4":{**frame["components"]["bar4"],"width":80}}},directory,errors,{})
            self.assertTrue(any("component geometry" in e for e in errors))
            errors=[];hashes={};ordinary={"id":"a","page":"bars"}
            verify_frame(ordinary,ordinary,frame,directory,errors,hashes)
            verify_frame({**ordinary,"id":"b"},ordinary,second,directory,errors,hashes)
            self.assertTrue(any("Identical states" in e for e in errors))
    def test_grid_atlas_authenticates_every_native_root_and_rejects_mismatched_cells(self):
        from check import verify_components
        from copy import deepcopy
        case={"frame":"RikRenderStudioGrids","sequence":{"apply":"RikRenderStudioGrids(VALUE)"}}
        frame={"value":36,"width":700,"height":1400,"components":{}}
        top=8
        for key,count in (("main",12),("bar2",12),("bar3",12),("bar4",12),("bar5",12),("stance",3),("pet",10)):
            columns=min(4,count);rows=(count+3)//4
            width=columns*36+(columns-1)*6;height=rows*36+(rows-1)*6
            frame["components"][key]={"x":8,"y":1400-top-height,"width":width,"height":height};top+=height+16
        errors=[];verify_components(case,frame,"grids",errors);self.assertEqual(errors,[])
        missing=deepcopy(frame);del missing["components"]["pet"]
        errors=[];verify_components(case,missing,"missing",errors);self.assertTrue(any("identity" in e for e in errors))
        wrong=deepcopy(frame);wrong["components"]["main"]["width"]+=1
        errors=[];verify_components(case,wrong,"wrong",errors);self.assertTrue(any("grid cells" in e for e in errors))
        escaped=deepcopy(frame);escaped["components"]["pet"]["x"]=700
        errors=[];verify_components(case,escaped,"escaped",errors);self.assertTrue(any("geometry" in e for e in errors))
    def test_current_planner_uses_separate_verified_version_and_build(self):
        from fixtures import client_prelude,load_modules,scenario_script
        client="1.60.8.99999"
        self.assertIn('version = "1.60.8", build = "99999"',client_prelude(client))
        case={"id":"current","frame":"Native","fixtures":["RikRenderCurrentPlanner()"],"lua":""}
        script=scenario_script(case,load_modules(),client)
        self.assertIn("return RikRenderClient.version,RikRenderClient.build,date,16001",script)
if __name__=="__main__":unittest.main()
