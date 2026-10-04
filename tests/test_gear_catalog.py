"""Small adversarial compiler inputs: no client installation needed."""
import copy
import importlib.util
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location("gear_catalog",Path(__file__).parents[1]/"tools/gear_catalog.py")
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)

class GearCatalogTests(unittest.TestCase):
    def setUp(self):
        self.provider={"provider":{"flavor":"Forever"},"base":{"items":{"100":{"name":"Reward","questRewards":{"1":1}},
            "101":{"name":"Drop","npcDrops":{"1":5}}},"quests":{"1":{"name":"Quest","preQuestGroup":{"1":2}},
            "2":{"name":"Prerequisite","preQuestSingle":{"1":1}}},"npcs":{"5":{"name":"Boss","zoneID":1581,"rank":3}}},
            "variants":[{"selector":{"faction":"Horde","classFile":"MAGE"},"quests":{"2":{"name":"Variant","preQuestSingle":{"1":3}},
                "3":{"name":"Extra"}},"questsRemoved":[]}]}
        self.items={str(i):{"ClassID":2,"SubclassID":7,"InventoryType":13,"IconFileDataID":1} for i in (100,101)}
        self.sparse={"100":{"Display_lang":"Client name","RequiredLevel":12,"ItemLevel":20}}
    def compile(self):return g.compile_catalog(self.provider,self.items,self.sparse,{"build":"1.60.1.70205"})
    def test_slots_sources_and_authority(self):
        c=self.compile()
        self.assertEqual(c["slots"][16],c["slots"][17])
        self.assertEqual(c["items"]["100"]["name"],"Client name")
        self.assertEqual(c["items"]["100"]["sources"][0]["authority"],"reference")
        self.assertEqual(c["items"]["101"]["metadataAuthority"],"reference")
    def test_persona_closure_and_cycles(self):
        c=self.compile()
        self.assertIn("3",c["variants"]["Horde/MAGE"]["quests"])
        self.assertEqual(len(c["quests"]),2)
    def test_non_equipment_is_excluded(self):
        self.items["100"]["InventoryType"]=0
        self.assertNotIn("100",self.compile()["items"])
    def test_world_drops_not_misrepresented_as_boss_loot(self):
        self.provider["base"]["items"]["101"]["npcDrops"]={str(i):5 for i in range(1,25)}
        # Duplicate IDs are one source, not an inflated provenance count.
        self.assertEqual(len(self.compile()["items"]["101"]["sources"]),1)
        self.provider["base"]["items"]["101"]["npcDrops"]={str(i):i for i in range(1,25)}
        self.assertNotIn("101",self.compile()["items"])
    def test_invalid_identity_and_source(self):
        with self.assertRaises(ValueError):g.compile_catalog(self.provider,self.items,self.sparse,{"build":"old"})
        self.provider["base"]["items"]["100"]["questRewards"]={"1":True}
        with self.assertRaises(ValueError):self.compile()
    def test_safe_literal_and_text(self):
        self.assertEqual(g.lua('"; os.execute("x")'),'"\\\"; os.execute(\\\"x\\\")"')
        with self.assertRaises(ValueError):g.clean("a\nprint(1)")
        self.assertEqual(g.clean("|cffffffffname"),"cffffffffname")
    def test_deterministic(self):
        self.assertEqual(g.lua(self.compile()),g.lua(self.compile()))

if __name__=="__main__":unittest.main()
