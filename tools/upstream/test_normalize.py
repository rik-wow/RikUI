import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from normalize import normalize, quest, spawns, compare_baseline
from compare_provider import compare


def fixture():
    return {"quest_template": [{"entry": 42, "Title": "Fixture quest", "ReqCreatureOrGOId1": -15,
        "ReqCreatureOrGOCount1": 2, "ReqItemId2": 80, "ReqItemCount2": 3, "PrevQuestId": -40}],
        "item_template": [{"entry": 80, "name": "Fixture item", "startquest": 42}],
        "creature": [{"guid": 1, "id": 0, "map": 0, "position_x": "12.25",
                      "position_y": "-2", "position_z": "7"}],
        "creature_spawn_entry": [{"guid": 1, "entry": 7}, {"guid": 1, "entry": 8}],
        "creature_questrelation": [{"id": 7, "quest": 42}]}


class NormalizationTests(unittest.TestCase):
    def test_object_sign_count_prerequisite_and_relations(self):
        result = normalize(fixture())
        row = result["quests"]["42"]
        self.assertEqual(row["objectives"][0]["targetKind"], "object")
        self.assertEqual(row["objectives"][0]["targetID"], 15)
        self.assertEqual(row["objectives"][0]["count"], 2)
        self.assertEqual(row["objectives"][1]["count"], 3)
        self.assertEqual(row["links"]["PrevQuestId"], -40)
        self.assertEqual({r["kind"] for r in result["relations"]}, {"npc", "item"})

    def test_spawn_alternatives_and_unknown_forever_mapping(self):
        point = normalize(fixture())["spawns"][0]
        self.assertEqual(point["entityIDs"], [7, 8])
        self.assertEqual(point["position"], [12.25, -2.0, 7.0])
        self.assertIsNone(point["uiMapID"])
        self.assertFalse(point["foreverVerified"])

    def test_invalid_coordinates_and_duplicate_ids(self):
        rows = fixture()
        rows["creature"][0]["position_x"] = "nan"
        with self.assertRaisesRegex(ValueError, "Nonfinite"):
            spawns(rows)
        rows = fixture()
        rows["quest_template"].append(dict(rows["quest_template"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            normalize(rows)

    def test_spell_target_keeps_spell_identity(self):
        row = quest({"entry": 1, "ReqCreatureOrGOId1": 4, "ReqSpellCast1": 19})
        self.assertEqual(row["objectives"][0]["spellID"], 19)
        self.assertEqual(row["objectives"][0]["kind"], "spell")

    def test_comparison_distinguishes_targets_relations_and_empty_sets(self):
        provider = normalize(fixture())
        baseline = {"base": {"quests": {"42": {
            "objectives": {"2": [[15]], "3": [[80]]},
            "startedBy": {"1": [7], "3": [80]}}}}}
        report = compare(provider, baseline)
        self.assertEqual(report["metrics"]["basicObjectiveTargets"]["equalNonempty"], 1)
        self.assertEqual(report["metrics"]["declaredGiverAndTurnInRelations"]["equal"], 1)
        baseline["base"]["quests"]["42"]["objectives"]["2"] = [[16]]
        report = compare(provider, baseline)
        self.assertEqual(report["metrics"]["basicObjectiveTargets"]["differentQuestIDs"], [42])
        empty = compare({"quests": {"1": {"objectives": []}}, "relations": []},
                        {"base": {"quests": {"1": {}}}})
        self.assertEqual(empty["metrics"]["basicObjectiveTargets"]["equalNonempty"], 0)

    def test_baseline_only_compares_and_never_merges(self):
        provider = normalize(fixture())
        original = json.dumps(provider, sort_keys=True)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "baseline.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("audit/source-export.json", json.dumps({"base": {"quests": {"42": {}, "99": {}}}}))
                archive.writestr("catalog.json", json.dumps({"revision": "test"}))
            result = compare_baseline(provider, path)
        self.assertEqual(result["baselineOnlyQuestIDs"], [99])
        self.assertEqual(result["sharedQuestIDs"], 1)
        self.assertEqual(json.dumps(provider, sort_keys=True), original)


if __name__ == "__main__":
    unittest.main()
