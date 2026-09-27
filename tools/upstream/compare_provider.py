"""Compare independently acquired records without merging any baseline data."""
import argparse
import collections
import json
from pathlib import Path
import zipfile

from normalize import compare_baseline, zip_json


def slot(value, index):
    if isinstance(value, dict):
        return value.get(str(index), value.get(index))
    if isinstance(value, list) and 0 < index <= len(value):
        return value[index - 1]
    return None


def sequence(value):
    if isinstance(value, dict):
        return list(value.values())
    return value if isinstance(value, list) else []


def baseline_targets(row):
    result = set()
    for index, kind in ((1, "npc"), (2, "object"), (3, "item")):
        for target in sequence(slot(row.get("objectives"), index)):
            entity = slot(target, 1)
            if entity:
                result.add((kind, int(entity)))
    return result


def baseline_relations(row):
    result = set()
    for field, direction in (("startedBy", "starts"), ("finishedBy", "ends")):
        for index, kind in ((1, "npc"), (2, "object"), (3, "item")):
            for entity in sequence(slot(row.get(field), index)):
                if entity:
                    result.add((direction, kind, int(entity)))
    return result


def compare(provider, source):
    relations = collections.defaultdict(set)
    for row in provider["relations"]:
        relations[str(row["questID"])].add((row["relation"], row["kind"], row["entityID"]))
    metrics = {name: {"equal": 0, "equalNonempty": 0, "differentQuestIDs": []}
               for name in ("basicObjectiveTargets", "declaredGiverAndTurnInRelations")}
    shared = sorted(set(provider["quests"]) & set(source["base"]["quests"]), key=int)
    for quest_id in shared:
        new, old = provider["quests"][quest_id], source["base"]["quests"][quest_id]
        targets = {(row["targetKind"] if row["kind"] == "target" else "item", row["targetID"])
                   for row in new["objectives"] if row["kind"] in ("target", "item")}
        pairs = ((targets, baseline_targets(old)),
                 (relations[quest_id], baseline_relations(old)))
        for metric, (left, right) in zip(metrics.values(), pairs):
            if left == right:
                metric["equal"] += 1
                metric["equalNonempty"] += bool(left)
            else:
                metric["differentQuestIDs"].append(int(quest_id))
    for metric in metrics.values():
        metric["different"] = len(metric["differentQuestIDs"])
    return {"sharedQuestsCompared": len(shared), "metrics": metrics,
            "scope": "Baseline base records only; set equality, ignoring order and duplicates.",
            "limitations": [
                "Basic targets compare NPC, object and item IDs only, not counts or action semantics.",
                "Spell, kill-credit, reputation and event objectives are not compared.",
                "Relations compare explicit startedBy/finishedBy declarations, not inferred entity backlinks.",
                "Variants, eligibility, prerequisites, drop conditions and coordinates are not compared.",
                "Equal sets, especially empty sets, do not establish complete quest equivalence."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    provider = json.loads(args.provider.read_text(encoding="utf-8"))
    with zipfile.ZipFile(args.baseline) as archive:
        source = zip_json(archive, "audit/source-export.json")
    report = {"ids": compare_baseline(provider, args.baseline), **compare(provider, source)}
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2, sort_keys=True)
        stream.write("\n")
    summary = {name: {key: value for key, value in metric.items() if key != "differentQuestIDs"}
               for name, metric in report["metrics"].items()}
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
