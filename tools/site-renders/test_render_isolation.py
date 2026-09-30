"""Capture isolation excludes installed and bundled third-party addons."""
import tempfile
import unittest
from pathlib import Path
import render

class CaptureIsolationTest(unittest.TestCase):
    def test_discovered_addons_are_disabled_before_corpus_staging(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sim, wow = root / "sim", root / "wow"
            for name in ("RikUI", "A_RikUIPreview", "LocalProbe"):
                (sim / "addons" / name).mkdir(parents=True)
            for name in ("ForeverProbe", "RikProbe", "RikUIQuestRoads_W0_P001", "Blizzard_ActionBar"):
                (wow / "_classic_beta_/Interface/AddOns" / name).mkdir(parents=True)
            (sim / "source/Interface/AddOns/Admin").mkdir(parents=True)
            render.isolate_addons(sim, wow)
            states = dict(line.split(": ") for line in (sim / "AddOns.txt").read_text().splitlines())
            self.assertEqual(states["RikUI"], "enabled")
            self.assertEqual(states["A_RikUIPreview"], "enabled")
            for name in ("LocalProbe", "ForeverProbe", "RikProbe", "Admin", "RikUIQuestRoads_W0_P001"):
                self.assertEqual(states[name], "disabled")
            self.assertNotIn("Blizzard_ActionBar", states)
            render.set_addon_state(sim, ["RikUIQuestRoads_W0_P001"], True)
            states = dict(line.split(": ") for line in (sim / "AddOns.txt").read_text().splitlines())
            self.assertEqual(states["RikUIQuestRoads_W0_P001"], "enabled")
            self.assertEqual(states["ForeverProbe"], "disabled")

if __name__ == "__main__":
    unittest.main()
