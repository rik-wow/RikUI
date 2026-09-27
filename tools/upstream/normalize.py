"""Provider-neutral facts with explicit original-world coordinates and unresolved semantics."""
import collections
import json
import math
import zipfile


def value(row, key, default=0):
    return next((item for name, item in row.items() if name.lower() == key.lower()), default)


def integer(row, key, default=0):
    item = value(row, key, default)
    if isinstance(item, bool) or int(item) != float(item):
        raise ValueError("Expected integer " + key)
    return int(item)


def quest(row):
    objectives = []
    for slot in range(1, 5):
        target = integer(row, "ReqCreatureOrGOId" + str(slot))
        spell = integer(row, "ReqSpellCast" + str(slot))
        item = integer(row, "ReqItemId" + str(slot))
        if target or spell:
            objectives.append({"slot": slot, "kind": "spell" if spell else "target",
                "targetKind": "object" if target < 0 else "npc" if target else "unknown",
                "targetID": abs(target), "spellID": spell,
                "count": integer(row, "ReqCreatureOrGOCount" + str(slot))})
        if item:
            objectives.append({"slot": slot, "kind": "item", "targetID": item,
                               "count": integer(row, "ReqItemCount" + str(slot))})
    return {"id": integer(row, "entry"), "name": value(row, "Title", ""),
        "level": integer(row, "QuestLevel"), "minLevel": integer(row, "MinLevel"),
        "zoneOrSort": integer(row, "ZoneOrSort"), "objectives": objectives,
        "restrictions": {key: value(row, key) for key in ("RequiredClasses", "RequiredRaces",
            "RequiredSkill", "RequiredSkillValue", "RequiredCondition")},
        "links": {key: integer(row, key) for key in ("PrevQuestId", "NextQuestId", "ExclusiveGroup")},
        "provenance": {"table": "quest_template", "entry": integer(row, "entry")},
        "foreverVerified": False}


def relations(raw):
    result = []
    for kind, prefix in (("npc", "creature"), ("object", "gameobject")):
        for suffix, direction in (("questrelation", "starts"), ("involvedrelation", "ends")):
            table = prefix + "_" + suffix
            for row in raw.get(table, []):
                result.append({"questID": integer(row, "quest"), "kind": kind,
                    "entityID": integer(row, "id"), "relation": direction, "sourceTable": table})
    for row in raw.get("item_template", []):
        start = integer(row, "startquest")
        if start:
            result.append({"questID": start, "kind": "item", "entityID": integer(row, "entry"),
                           "relation": "starts", "sourceTable": "item_template"})
    return sorted(result, key=lambda r: (r["questID"], r["kind"], r["entityID"], r["relation"]))


def spawns(raw):
    result = []
    for kind, table in (("npc", "creature"), ("object", "gameobject")):
        entries = collections.defaultdict(list)
        for row in raw.get(table + "_spawn_entry", []):
            entries[integer(row, "guid")].append(integer(row, "entry"))
        for row in raw.get(table, []):
            guid, direct = integer(row, "guid"), integer(row, "id")
            ids = [direct] if direct else sorted(set(entries[guid]))
            position = [float(value(row, "position_" + axis)) for axis in ("x", "y", "z")]
            if not all(math.isfinite(number) for number in position):
                raise ValueError("Nonfinite spawn coordinate")
            result.append({"kind": kind, "guid": guid, "entityIDs": ids,
                "map": integer(row, "map"), "position": position,
                "coordinateSystem": "cmangos-classic-world", "uiMapID": None,
                "foreverVerified": False, "sourceTable": table,
                "selection": "direct" if direct else "upstream-spawn-entry"})
    return sorted(result, key=lambda row: (row["kind"], row["guid"]))


def normalize(raw):
    quests = {str(integer(row, "entry")): quest(row) for row in raw["quest_template"]}
    if len(quests) != len(raw["quest_template"]):
        raise ValueError("Duplicate quest ID")
    links, points = relations(raw), spawns(raw)
    entities = {}
    for kind, table in (("npc", "creature_template"), ("object", "gameobject_template"), ("item", "item_template")):
        entities[kind] = {str(integer(row, "entry")): {"name": value(row, "name", ""),
            "sourceTable": table, "sourceID": integer(row, "entry")} for row in raw.get(table, [])}
    return {"schemaVersion": 1, "provider": "CMaNGOS Classic-DB",
        "sourceClient": "original WoW 1.12", "targetCompatibility": "Forever unverified",
        "quests": quests, "entities": entities, "relations": links, "spawns": points,
        "counts": {"quests": len(quests), "objectives": sum(len(q["objectives"]) for q in quests.values()),
                   "relations": len(links), "spawnRows": len(points)},
        "limitations": ["No QuestieDB correction tables are copied.",
            "Original-world coordinates are retained; no Forever UI-map mapping is asserted.",
            "Signed prerequisite/group fields are retained without inventing AND/OR semantics.",
            "Loot, conditions, event and optional tables remain in the SQLite source archive.",
            "Spawn-entry choices are alternatives; this is not proof of simultaneous spawns.",
            "Same quest IDs do not establish equivalent objectives, phases or routing."]}


def zip_json(archive, suffix):
    matches = [name for name in archive.namelist() if name == suffix or name.endswith("/" + suffix)]
    if len(matches) != 1:
        raise ValueError("Expected exactly one baseline " + suffix)
    info = archive.getinfo(matches[0])
    if info.file_size > 512 * 1024 * 1024:
        raise ValueError("Baseline member exceeds 512 MiB")
    return json.loads(archive.read(info))


def compare_baseline(provider, baseline):
    with zipfile.ZipFile(baseline) as archive:
        source = zip_json(archive, "audit/source-export.json")
        catalog = zip_json(archive, "catalog.json")
    old_ids = set(map(int, source["base"]["quests"]))
    new_ids = set(map(int, provider["quests"]))
    return {"baselineRevision": catalog["revision"],
        "baselineSemanticQuests": len(old_ids), "upstreamQuests": len(new_ids),
        "sharedQuestIDs": len(old_ids & new_ids),
        "baselineOnlyQuestIDs": sorted(old_ids - new_ids),
        "upstreamOnlyQuestIDs": sorted(new_ids - old_ids),
        "meaning": "ID coverage only; does not establish semantic or spatial parity"}
