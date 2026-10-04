"""Synthetic fixtures only: generated upstream content remains outside the repo."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("quest_corpus", Path(__file__).resolve().parents[1] / "tools" / "quest_corpus.py")
corpus = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(corpus)


def rikui_folder(addons):
    """A minimal installed RikUI folder: the installer requires the committed include."""
    rikui = addons / "RikUI"
    (rikui / "generated").mkdir(parents=True)
    (rikui / "RikUI.toc").write_text("## Title: RikUI\n")
    (rikui / "generated" / "index.xml").write_text("<Ui/>\n")
    return rikui


def fixture():
    return {
        "schemaVersion": 1, "provider": {"revision": "a"*40, "flavor": "Forever"},
        "maps": {"areaToMap": {"12": 1429, "40": 1436}, "areaMapOverride": {"718": 279}},
        "base": {
            "quests": {"1": {"name": "Collect samples", "zoneOrSort": 12,
                "objectives": {"1": {"1": {"1": 10, "3": 3}}, "3": {"1": {"1": 30, "3": 2}}},
                "startedBy": {"1": {"1": 10}}, "finishedBy": {"2": {"1": 20}},
                "requiredRaces": 1, "preQuestGroup": {"1": -9},
                "triggerEnd": {"1": "Explore", "2": {"12": {"1": {"1": 30, "2": 40}}}},
                "extraObjectives": {"1": {"2": 1, "3": "Use relic", "4": 1, "5": {"1": {"1": "object", "2": 20}}}},
                "unsupportedFutureField": {"proof": 7}}},
            "npcs": {"10": {"name": "Crab", "spawns": {"12": {"1": {"1": 30, "2": 40}, "2": {"1": 31, "2": 40}, "3": {"1": 90, "2": 90}}, "40": {"1": {"1": 10, "2": 20}}}, "questStarts": {"1": 1}},
                     "11": {"name": "Vendor", "spawns": {"12": {"1": {"1": 50, "2": 50, "3": 2}}}}},
            "objects": {"20": {"name": "Crate", "spawns": {"718": {"1": {"1": 40, "2": 40}}, "12": {"1": {"1": -1, "2": -1}}}}},
            "items": {"30": {"name": "Shell", "npcDrops": {"1": 10}, "objectDrops": {"1": 20}, "vendors": {"1": 11}}},
        },
        "variants": [{"selector": {"faction": "Horde", "classFile": "MAGE"}, "npcs": {"10": {"name": "Crab", "spawns": {"12": {"1": {"1": 80, "2": 10}}}}}}],
    }


class CorpusTests(unittest.TestCase):
    def compile(self, data=None):
        compiler = corpus.Compiler(data or fixture(), "test")
        records = compiler.compile()
        return compiler, records

    def test_exact_spawn_waypoints_survive_clustering(self):
        compiler, records = self.compile()
        method = records[1]["base"]["objectives"][0]["methods"][0]
        points = {(area["mapID"], x, y) for area in method["areas"] for x, y in area["spawns"]}
        self.assertEqual(points, {(1429, .30, .40), (1429, .31, .40),
                                  (1429, .90, .90), (1436, .10, .20)})
        for area in method["areas"]:
            self.assertEqual(len(area["spawns"]), area["spawnCount"])
            self.assertIn([area["x"], area["y"]], area["spawns"])
        self.assertGreater(compiler.report["waypointCoverage"]["exactSpawns"], 0)
        self.assertTrue(any(row["code"] == "floor-map-unknown" for row in compiler.report["unknowns"]))

    def test_current_client_membership_records_acquired_build_without_inventing_details(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "QuestV2.csv"
            raw = b"ID,UniqueBitFlag,UiQuestDetailsThemeID\n99001,1,0\n"
            path.write_bytes(raw)
            rows, _ = corpus.load_client_index(path, corpus.sha(raw))
            records, report = {}, {"counts": {}}
            corpus.add_client_records(records, rows, report, "1.60.1.99999")
            quest = records[99001]["base"]
            self.assertEqual(quest["provenance"]["build"], "1.60.1.99999")
            self.assertFalse(quest["known"]["semanticRecord"])
            self.assertEqual(quest["objectives"], [])
            with self.assertRaises(ValueError):
                corpus.load_client_index(path, "0" * 64)

    def test_event_memberships_cover_ordinary_categories_and_all_personas(self):
        _, records = self.compile()
        variant = copy.deepcopy(records[1]["base"])
        records[1]["variants"]["Horde:MAGE"] = variant
        events = {"revision": "b"*40, "quests": {
            1: {"key": "ExampleEvent", "source": "pinned.lua", "line": 7}}}
        self.assertEqual(corpus.apply_event_memberships(records, events), 1)
        for quest in (records[1]["base"], variant):
            self.assertEqual(quest["zoneOrSort"], 12)
            self.assertEqual(quest["planning"]["seasonalEvent"], "ExampleEvent")
            self.assertEqual(quest["planning"]["seasonalProvenance"]["revision"], "b"*40)
        inputs = ("source", "compiler", None, None, corpus.IDENTITY, 128)
        self.assertNotEqual(corpus.corpus_revision(*inputs, client_build="1.60.1.1"),
                            corpus.corpus_revision(*inputs, client_build="1.60.1.2"))
        self.assertNotEqual(corpus.corpus_revision(*inputs), corpus.corpus_revision(*inputs, event_hash="holiday-input"))
        self.assertNotEqual(corpus.corpus_revision(*inputs, event_hash="one"), corpus.corpus_revision(*inputs, event_hash="two"))

    def test_seasonal_categories_do_not_confuse_script_or_profession_requirements(self):
        for category in corpus.SEASONAL_SORTS:
            plan = corpus.planning_rules({"zoneOrSort": category}, {})
            self.assertEqual(plan["seasonalCategory"], category)
        for category in (-284, -161, -81, 1537):
            plan = corpus.planning_rules({"zoneOrSort": category, "specialFlags": 2}, {})
            self.assertIsNone(plan["seasonalCategory"])

    def test_typed_planner_rules_preserve_optional_and_exclusive_semantics(self):
        data = fixture()
        row = data["base"]["quests"]["1"]
        row.update(preQuestGroup={"1": 8, "2": -9}, exclusiveTo={"1": 7},
                   breadcrumbForQuestId=12, parentQuest=5, availableStartingWith=6)
        data["base"]["quests"]["8"] = {"name": "Either route", "exclusiveTo": {"1": 18}}
        _, records = self.compile(data)
        plan = records[1]["base"]["planning"]
        self.assertEqual(plan["version"], 1)
        clauses = plan["requirements"]["args"]
        self.assertIn({"op": "any", "args": [{"op": "completed", "questID": 8}, {"op": "completed", "questID": 18}]}, clauses)
        self.assertIn({"op": "completed", "questID": 9}, clauses)
        self.assertIn(7, plan["blockedBy"])
        self.assertIn(12, plan["blockedBy"])
        self.assertEqual(plan["breadcrumbFor"], 12)
        self.assertEqual(plan["exclusiveWith"], [7])
        self.assertNotIn({"op": "completed", "questID": 12}, clauses)

    def test_planner_single_precedence_xp_and_unknown_counts(self):
        data = fixture()
        row = data["base"]["quests"]["1"]
        row.update(preQuestSingle={"1": 3, "2": 4}, requiredLevel=5, requiredClasses=1)
        data["decodedSupport"] = {"QuestXP": {"db": {"1": {"1": 9, "2": 780}}}}
        _, records = self.compile(data)
        quest = records[1]["base"]
        self.assertEqual(quest["reward"]["baseXP"], 780)
        self.assertEqual(quest["reward"]["level"], 9)
        self.assertEqual(quest["reward"]["source"], "QuestieDB.Forever.QuestXP")
        self.assertNotIn({"op": "completed", "questID": 9}, quest["planning"]["requirements"]["args"])
        self.assertTrue(all("required" not in o for o in quest["objectives"]))
        self.assertEqual(quest["planning"]["countStatus"], "live-required")

    def test_future_index_includes_all_personas_and_chain_links(self):
        _, records = self.compile()
        index = corpus.planning_index(records)
        self.assertEqual(index["version"], 1)
        self.assertIn(1, index["maps"][1429])
        self.assertIn(1, index["maps"][1436])
        self.assertIn(9, index["links"][1])
        self.assertEqual(index["quests"][1]["semantic"], True)
        corpus.add_client_records(records, {99: {"ID": 99}}, {"counts": {}})
        self.assertFalse(corpus.planning_index(records)["quests"][99]["semantic"])

    def test_drop_estimates_keep_zero_precedence_and_source_identity(self):
        data = fixture()
        data["decodedSupport"] = {
            "QuestieClassicItemDrops": {"wowheadData": {"30": {"10": 25}}, "cmangosData": {"30": {"10": 40}}},
            "QuestieItemDropCorrections": {"Era": {"30": {"10": 0}}}}
        _, records = self.compile(data)
        item = next(o for o in records[1]["base"]["objectives"] if o["type"] == "item")
        drop = next(m for m in item["methods"] if m["kind"] == "drop")
        self.assertEqual(drop["dropEstimate"]["probability"], 0)
        self.assertEqual(drop["dropEstimate"]["source"], "correction")
        data["decodedSupport"]["QuestieItemDropCorrections"]["Era"]["30"]["10"] = -1
        _, records = self.compile(data)
        item = next(o for o in records[1]["base"]["objectives"] if o["type"] == "item")
        self.assertEqual(next(m for m in item["methods"] if m["kind"] == "drop")["dropEstimate"]["probability"], .25)

    def test_pickup_blockers_keep_distinct_active_and_completed_scopes(self):
        data = fixture()
        data["base"]["quests"]["1"].update(availableUntilCompleted=8, disabledByQuest=9, breadcrumbs={"1": 10})
        _, records = self.compile(data)
        plan = records[1]["base"]["planning"]
        self.assertEqual(plan["forbiddenAfter"], [8])
        self.assertEqual(plan["blockedWhileActive"], [9])
        self.assertEqual(plan["activeBreadcrumbs"], [10])
        self.assertNotIn(8, plan["blockedBy"])
        self.assertNotIn(9, plan["blockedBy"])

    def test_all_acquisition_methods_join_entity_locations(self):
        compiler, records = self.compile()
        quest = records[1]["base"]
        item = next(row for row in quest["objectives"] if row["type"] == "item")
        self.assertEqual({m["kind"] for m in item["methods"]}, {"drop", "loot", "vendor"})
        self.assertEqual(quest["prerequisites"]["preQuestGroup"], {"1": -9})
        self.assertEqual(quest["objectives"][0]["iconType"], 3)
        self.assertEqual(quest["objectives"][0]["methods"][0]["kind"], "event")
        self.assertNotIn("required", quest["objectives"][0])
        self.assertEqual(quest["starts"][0]["targetID"], 10)
        self.assertEqual(quest["ends"][0]["targetID"], 20)
        self.assertTrue(quest["extraObjectives"][0]["methods"])
        self.assertEqual(compiler.report["coverage"]["quests"]["unsupportedFutureField"]["handling"], "raw-audit-only")

    def test_variant_entity_change_propagates_without_quest_override(self):
        _, records = self.compile()
        base = records[1]["base"]["objectives"][0]["methods"][0]["areas"]
        variant = records[1]["variants"]["Horde:MAGE"]["objectives"][0]["methods"][0]["areas"]
        self.assertNotEqual(base, variant)
        self.assertEqual(variant[0]["x"], .8)

    def test_spawn_clusters_keep_maps_phase_and_unknown_floors_separate(self):
        _, records = self.compile()
        quest = records[1]["base"]
        areas = quest["objectives"][0]["methods"][0]["areas"]
        self.assertEqual({a["mapID"] for a in areas}, {1429, 1436})
        self.assertEqual(sum(a["spawnCount"] for a in areas), 4)
        cluster = next(a for a in areas if a["spawnCount"] == 2)
        self.assertAlmostEqual(cluster["radiusNormalized"], .01)
        self.assertNotIn("radius", cluster)
        item = next(row for row in quest["objectives"] if row["type"] == "item")
        loot = next(m for m in item["methods"] if m["kind"] == "loot")
        self.assertFalse(loot["areas"])
        self.assertEqual({a["reason"] for a in loot["unresolvedAreas"]}, {"floor-map-unknown", "coordinate-unknown"})
        vendor = next(m for m in item["methods"] if m["kind"] == "vendor")
        self.assertEqual(vendor["areas"][0]["phase"], 2)
        self.assertNotIn("floor", vendor["areas"][0])

    def test_container_cycle_is_explicit_and_bounded(self):
        data = fixture()
        data["base"]["items"]["30"]["itemDrops"] = {"1": 31}
        data["base"]["items"]["31"] = {"name": "Box", "itemDrops": {"1": 30}}
        compiler, _ = self.compile(data)
        self.assertTrue(any(row["code"] == "item-cycle" for row in compiler.report["unknowns"]))

    def test_client_membership_union_preserves_unknown_semantics(self):
        compiler, records = self.compile()
        corpus.add_client_records(records, {1: {"ID": 1}, 2: {"ID": 2}}, compiler.report)
        self.assertEqual(compiler.report["clientUniverse"]["union"], 2)
        self.assertEqual(records[2]["base"]["title"], "")
        self.assertEqual(records[2]["base"]["objectives"], [])
        self.assertFalse(records[2]["base"]["known"]["semanticRecord"])
        self.assertTrue(records[1]["base"]["known"]["clientRecord"])

    def test_interaction_icons_do_not_invent_kills_or_required_counts(self):
        data = fixture()
        quest = data["base"]["quests"]["1"]
        quest["objectives"]["3"]["1"]["3"] = 17
        quest["extraObjectives"]["1"] = {"1": {"12": {"1": {"1": 30, "2": 40}}}, "2": 20, "3": "Fish", "4": 1}
        _, records = self.compile(data)
        result = records[1]["base"]
        item = next(row for row in result["objectives"] if row["type"] == "item")
        self.assertNotIn("required", item)
        method = next(row for row in item["methods"] if row.get("acquisitionKind") == "drop")
        self.assertEqual(method["kind"], "interact")
        self.assertEqual(result["extraObjectives"][0]["methods"][0]["kind"], "fish")

    def test_provider_manifest_binds_bytes_counts_and_personas(self):
        data = fixture()
        classes = ("WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID")
        data["variants"] = [{"selector": {"faction": faction, "classFile": cls}} for faction in ("Alliance", "Horde") for cls in classes]
        raw = corpus.canonical(data).encode()
        proof = {"schemaVersion": 1, "revision": "a"*40, "flavor": "Forever", "exportSha256": corpus.sha(raw), "exportBytes": len(raw), "personaCount": 18, "counts": {"Quest": 1, "Npc": 2, "Item": 1, "Object": 1}, "inputs": [{"path": f"source/{index}.lua", "sha256": "0" * 64} for index in range(147)]}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "proof.json"
            path.write_text(corpus.canonical(proof), encoding="utf8")
            metadata, _ = corpus.verify_provider_manifest(path, data, raw)
            self.assertEqual(metadata["inputFiles"], 147)
            with self.assertRaises(ValueError):
                corpus.verify_provider_manifest(path, data, raw + b" ")
            data["variants"].pop()
            with self.assertRaises(ValueError):
                corpus.verify_provider_manifest(path, data, raw)

    def test_objective_order_reverses_each_flagged_group(self):
        data = fixture()
        row = data["base"]["quests"]["1"]
        row["objectives"] = {
            "1": {"1": {"1": 10}, "2": {"1": 11}},
            "2": {"1": {"1": 20}},
            "3": {"1": {"1": 30}, "2": {"1": 31}},
            "4": {"1": 72, "2": 3000},
            "5": {"1": {"1": {"1": 10}, "2": 10}},
            "6": {"1": {"1": 100}, "2": {"1": 101}},
        }
        data["objectiveFirst"] = {"itemObjectiveFirst": {"1": True}, "spellObjectiveFirst": {"1": True}, "eventObjectiveFirst": {"1": True}}
        _, records = self.compile(data)
        objectives = records[1]["base"]["objectives"]
        self.assertEqual([value["id"] for value in objectives], ["event:1:1", "spell:101:2", "spell:100:1", "item:31:2", "item:30:1", "monster:10:1", "monster:11:2", "object:20:1", "reputation:72:1", "kill-credit:10:1"])
        self.assertEqual([value["runtimeObjectiveIndex"] for value in objectives], list(range(1, 11)))
        self.assertEqual(records[1]["base"]["extraObjectives"][0]["objectiveIndex"], 1)

    def test_sparse_objective_groups_do_not_claim_runtime_indices(self):
        data = fixture()
        row = data["base"]["quests"]["1"]
        row["objectives"]["1"] = {"2": {"1": 10}}
        _, records = self.compile(data)
        quest = records[1]["base"]
        self.assertEqual(quest["objectiveOrderUnknown"], "sparse-source-objectives")
        self.assertTrue(all("runtimeObjectiveIndex" not in value for value in quest["objectives"]))

    def test_field_coverage_reports_schema_absence_and_defaults_honestly(self):
        data = fixture()
        data["schema"] = {"Object": {"keys": {"name": 1, "zoneID": 5, "waypoints": 7}}}
        data["base"]["objects"]["20"]["zoneID"] = 0
        data["base"]["npcs"]["10"]["zoneID"] = 12
        data["base"]["items"]["30"]["relatedQuests"] = {}
        compiler, _ = self.compile(data)
        coverage = compiler.report["coverage"]
        self.assertEqual(coverage["objects"]["waypoints"], {"present": 0, "nonempty": 0, "nonDefault": 0, "denominator": 1, "handling": "raw-audit-only"})
        self.assertEqual(coverage["objects"]["zoneID"]["present"], 1)
        self.assertEqual(coverage["objects"]["zoneID"]["nonempty"], 1)
        self.assertEqual(coverage["objects"]["zoneID"]["nonDefault"], 0)
        self.assertEqual(coverage["npcs"]["zoneID"]["handling"], "raw-audit-only")
        self.assertEqual(coverage["items"]["relatedQuests"]["handling"], "raw-audit-only")
        self.assertEqual(coverage["items"]["relatedQuests"]["present"], 1)
        self.assertEqual(coverage["items"]["relatedQuests"]["nonempty"], 0)

    def test_diagnostic_occurrences_distinguish_baseline_and_personas(self):
        data = fixture()
        data["base"]["objects"]["20"]["questStarts"] = {"1": 1}
        compiler, _ = self.compile(data)
        report = compiler.report
        self.assertEqual(report["diagnosticEvaluations"]["totalCount"], 2)
        self.assertEqual(report["diagnosticEvaluations"]["personaCount"], 1)
        for field in ("unknownSummary", "conflictSummary"):
            summary = report[field]
            self.assertEqual(summary["evaluationOccurrences"], summary["baseOccurrences"] + summary["personaOccurrences"])
            self.assertLessEqual(summary["uniqueAcrossEvaluations"], summary["evaluationOccurrences"])
        self.assertEqual(report["conflictSummary"]["uniqueAcrossEvaluations"], 1)
        self.assertEqual(report["conflictSummary"]["evaluationOccurrences"], 2)
        self.assertEqual(report["conflictSummary"]["affectedQuestIDs"], [1])

    def test_corpus_revision_binds_all_build_inputs(self):
        inputs = {"source_hash": "a" * 64, "compiler_hash": "b" * 64, "proof_hash": "c" * 64, "client_hash": "d" * 64, "identity": corpus.IDENTITY, "partition_size": 128}
        expected = corpus.corpus_revision(**inputs)
        self.assertEqual(expected, corpus.corpus_revision(**copy.deepcopy(inputs)))
        for field in ("source_hash", "compiler_hash", "proof_hash", "client_hash"):
            self.assertNotEqual(expected, corpus.corpus_revision(**{**inputs, field: "f" * 64}))
        self.assertNotEqual(expected, corpus.corpus_revision(**{**inputs, "partition_size": 64}))
        self.assertNotEqual(expected, corpus.corpus_revision(**{**inputs, "identity": {**corpus.IDENTITY, "build": "other"}}))

    def test_sparse_order_and_lua_escaping(self):
        self.assertEqual(corpus.sequence({"6": "b", "2": "a"}), [(2, "a"), (6, "b")])
        self.assertEqual(corpus.lua('a\n1"\\é'), '"a\\0101\\"\\\\é"')
        with self.assertRaises(ValueError):
            corpus.sequence({"name": 3})

    def test_explicit_client_index_keeps_exact_build_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);export=root/"export.json"
            export.write_text(corpus.canonical(fixture()),encoding="utf8")
            raw=b"ID,UniqueBitFlag,UiQuestDetailsThemeID\n99001,1,0\n"
            index=root/"QuestV2.csv";index.write_bytes(raw)
            manifest=corpus.build(export,root/"build",client_index=index,client_index_sha=corpus.sha(raw),client_build="1.60.1.99999")
            self.assertEqual(manifest["identity"]["build"],"1.60.1.99999")
            catalog=json.loads((root/"build/catalog.json").read_text())
            self.assertEqual(catalog["identity"],manifest["identity"])
            corpus.verify(root/"build")

    def test_build_repeat_stale_and_install_rollback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            export = root / "export.json"
            export.write_text(corpus.canonical(fixture()), encoding="utf8")
            output = root / "build"
            first = corpus.build(export, output)
            second = corpus.build(export, output)
            self.assertEqual(first, second)
            catalog = json.loads((output / "catalog.json").read_text(encoding="utf8"))
            self.assertEqual(catalog["revision"], first["corpusRevision"])
            self.assertNotEqual(catalog["revision"], "a"*40)
            pages = sorted((output / "generated" / "corpus").glob("p*.lua"))
            lua_data = "\n".join(path.read_text(encoding="utf8") for path in pages)
            self.assertIn('Register(0,"' + first["corpusRevision"] + '"', lua_data)
            self.assertTrue(lua_data.startswith('RikUI.QuestPlanner.SemanticData.Page("P00000_S001",function()'))
            include = (output / "generated" / "corpus" / "corpus.xml").read_text(encoding="utf8")
            self.assertEqual(include.count("<Script file="), len(pages) + 1)
            self.assertEqual(catalog["partitions"]["0"]["pages"][0], "P00000_S001")
            raw = json.loads((output / "audit/source-export.json").read_text(encoding="utf8"))
            self.assertEqual(raw["base"]["quests"]["1"]["unsupportedFutureField"], {"proof": 7})
            (output / "unexpected.txt").write_text("stale")
            with self.assertRaises(ValueError):
                corpus.verify(output)
            (output / "unexpected.txt").unlink()
            addons = root / "AddOns"
            rikui = rikui_folder(addons)
            unrelated = addons / "UserAddon"
            unrelated.mkdir()
            (unrelated / "data.txt").write_text("keep")
            with self.assertRaises(ValueError):
                corpus.install(output, unrelated)
            corpus.install(output, rikui)
            corpus.verify_installed(output, rikui)
            installed = rikui / "generated" / "corpus" / "catalog.lua"
            before = installed.read_bytes()
            with mock.patch.object(corpus, "verify_installed", side_effect=ValueError("injected")):
                with self.assertRaises(ValueError):
                    corpus.install(output, rikui)
            self.assertEqual(installed.read_bytes(), before)
            stale = addons / "RikUIQuestCorpus_P99999"
            stale.mkdir()
            (stale / "old.lua").write_text("old")
            with self.assertRaises(ValueError):
                corpus.install(output, rikui)
            corpus.write_json(stale, corpus.OWNERSHIP_FILE, {"owner": "RikUI quest_corpus", "files": corpus.owned_files(stale)})
            result = corpus.install(output, rikui)
            self.assertEqual(result["removedLegacyAddons"], [stale.name])
            self.assertFalse(stale.exists())
            self.assertTrue((unrelated / "data.txt").is_file())
            self.assertEqual(sorted(p.name for p in (rikui / "generated").iterdir()), ["corpus", "index.xml"])

    def test_failed_restore_keeps_backup_for_recovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            export = root / "export.json"
            export.write_text(corpus.canonical(fixture()), encoding="utf8")
            output, addons = root / "build", root / "AddOns"
            rikui = rikui_folder(addons)
            corpus.build(export, output)
            corpus.install(output, rikui)
            original_replace = Path.replace
            def replacement(path, target):
                if path.parent.name == "previous":
                    raise OSError("injected restore failure")
                return original_replace(path, target)
            with mock.patch.object(corpus, "verify_installed", side_effect=ValueError("injected install failure")), mock.patch.object(Path, "replace", replacement):
                with self.assertRaises(RuntimeError):
                    corpus.install(output, rikui)
            retained = list((rikui / "generated").glob(".rikuicorpus-install-*"))
            self.assertEqual(len(retained), 1)
            self.assertTrue((retained[0] / "RECOVERY.json").is_file())
            self.assertTrue((retained[0] / "previous" / "corpus" / "catalog.lua").is_file())

    def test_malformed_pin_and_duplicate_json_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "bad.json"
            data = fixture()
            data["provider"]["revision"] = "unexpected"
            path.write_text(corpus.canonical(data), encoding="utf8")
            with self.assertRaises(ValueError):
                corpus.load_export(path)
            csv_path = Path(temporary) / "QuestV2-1.60.1.69913.csv"
            csv_path.write_text("ID,UniqueBitFlag,UiQuestDetailsThemeID\n1,2,0\n")
            with self.assertRaises(ValueError):
                corpus.load_client_index(csv_path)
            path.write_text('{"schemaVersion":1,"schemaVersion":1}', encoding="utf8")
            with self.assertRaises(ValueError):
                corpus.load_export(path)


if __name__ == "__main__":
    unittest.main()

