#!/usr/bin/env python3
"""Deterministic, local-only Forever semantic quest corpus compiler (stdlib)."""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import tempfile

PIN = "baa0998d49695c70a1fb8fec559fa9169e9adf33"
CLIENT_INDEX_SHA256 = "07353cb935ef0907a71c2e51f2aeed4d6460712d4011cb3873f759af5536df4a"
IDENTITY = {"product": "forever", "build": "1.60.1.69913", "locale": "enUS"}
KINDS = ("quests", "npcs", "items", "objects")
PARTITION_SIZE = 128
CELL_SIZE = .06
ELIGIBILITY = ("requiredLevel", "questLevel", "requiredMaxLevel", "requiredRaces", "requiredClasses", "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSpell", "requiredSpecialization", "requiredRanks", "questFlags", "specialFlags")
PREREQUISITES = ("preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo", "nextQuestInChain", "parentQuest", "breadcrumbForQuestId", "breadcrumbs", "availableUntilCompleted", "availableStartingWith", "disabledByQuest")
SEMANTIC_FIELDS = {
    "quests": {"name", "startedBy", "finishedBy", "objectives", "objectivesText", "triggerEnd", "extraObjectives", "zoneOrSort", "sourceItemId", "requiredSourceItems", "reputationReward", *ELIGIBILITY, *PREREQUISITES},
    "npcs": {"name", "spawns", "questStarts", "questEnds", "minLevel", "maxLevel", "friendlyToFaction"},
    "items": {"name", "npcDrops", "objectDrops", "itemDrops", "vendors", "startQuest", "questRewards"},
    "objects": {"name", "spawns", "questStarts", "questEnds"},
}
ICON_ACTIONS = {1: "kill", 2: "loot", 3: "event", 4: "interact", 5: "talk", 17: "interact", 19: "mount", 20: "fish", 21: "herb", 22: "mine", 23: "loot", 24: "pet-battle"}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def sha(value):
    return hashlib.sha256(value).hexdigest()


def slot(value, index, default=None):
    if isinstance(value, dict):
        return value.get(str(index), value.get(index, default))
    if isinstance(value, list) and 0 < index <= len(value):
        return value[index - 1]
    return default


def sequence(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [(index + 1, item) for index, item in enumerate(value) if item is not None]
    if not isinstance(value, dict) or any(not str(key).isdigit() or int(key) <= 0 for key in value):
        raise ValueError("expected positive positional Lua table keys")
    return [(int(key), value[key]) for key in sorted(value, key=int)]


def ids(value):
    result = []
    for _, item in sequence(value):
        if not finite(item) or item != int(item):
            raise ValueError("expected integral ID in ID array")
        result.append(int(item))
    return result


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def nonempty(value):
    """A storage-shape count, not a claim of useful gameplay knowledge."""
    return value is not None and value != "" and value != {} and value != []


def nondefault(value):
    """Count values with at least one nonempty, nonzero scalar leaf."""
    if isinstance(value, dict):
        return any(nondefault(child) for child in value.values())
    if isinstance(value, list):
        return any(nondefault(child) for child in value)
    return nonempty(value) and value is not False and value != 0


def selector_key(selector):
    faction, class_file = selector.get("faction"), selector.get("classFile")
    if faction not in ("Alliance", "Horde") or not isinstance(class_file, str) or not re.fullmatch(r"[A-Z]+", class_file):
        raise ValueError("invalid variant selector")
    return faction + ":" + class_file


def load_export(path):
    path = Path(path)
    if path.stat().st_size > 512 * 1024 * 1024:
        raise ValueError("export exceeds 512 MiB input bound")
    raw = path.read_bytes()
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result
    def invalid(value):
        raise ValueError(f"nonfinite JSON value: {value}")
    data = json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)
    if data.get("schemaVersion") != 1:
        raise ValueError("unsupported export schemaVersion")
    if data.get("provider", {}).get("revision") != PIN or data["provider"].get("flavor") != "Forever":
        raise ValueError("export must use pinned QuestieDB Forever revision")
    base = data.get("base")
    if not isinstance(base, dict) or any(not isinstance(base.get(kind), dict) for kind in KINDS):
        raise ValueError("base must include all four entity tables")
    views, selectors = [base], set()
    for variant in data.get("variants", []):
        key = selector_key(variant.get("selector", {}))
        if key in selectors:
            raise ValueError(f"duplicate selector: {key}")
        selectors.add(key)
        views.append(variant)
    count = 0
    for view in views:
        for kind in KINDS:
            rows = view.get(kind, {})
            if not isinstance(rows, dict):
                raise ValueError(f"{kind} must be an object")
            count += len(rows)
            for key, row in rows.items():
                if not str(key).isdigit() or not 0 < int(key) < 2**31 or not isinstance(row, dict):
                    raise ValueError(f"invalid {kind} record: {key}")
    if count > 2_000_000:
        raise ValueError("export exceeds record bound")
    return data, raw


def lua(value):
    """Lua 5.1 literal writer; provider strings are never executed."""
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (float, int)):
        if not math.isfinite(value):
            raise ValueError("nonfinite Lua number")
        return str(value)
    if isinstance(value, str):
        escaped = []
        for char in value:
            code = ord(char)
            escaped.append("\\\\" if char == "\\" else '\\"' if char == '"' else f"\\{code:03d}" if code < 32 or code == 127 else char)
        return '"' + "".join(escaped) + '"'
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + lua_key(key) + "]=" + lua(value[key]) for key in sorted(value, key=lambda key: (type(key).__name__, str(key)))) + "}"
    raise ValueError(f"cannot encode {type(value).__name__}")


def lua_key(value):
    # Exported positional keys were stringified for lossless JSON transport.
    return str(int(value)) if isinstance(value, str) and re.fullmatch(r"-?[0-9]+", value) else lua(value)


def lua_partition(bucket, rows, revision):
    """Intern immutable shared tables inside a page; no whole-corpus preload.

    Each pool assignment is its own statement, avoiding giant Lua constructor
    constant tables. Consumers treat records as borrowed immutable references.
    """
    counts, values, order = collections.Counter(), {}, []
    def scan(value):
        if not isinstance(value, (dict, list)):
            return
        key = canonical(value)
        counts[key] += 1
        if key in values:
            return
        values[key] = value
        children = value.values() if isinstance(value, dict) else value
        for child in children:
            scan(child)
        order.append(key)
    scan(rows)
    pools = {key: index + 1 for index, key in enumerate(key for key in order if len(key) > 300 or counts[key] > 1 and len(key) > 100)}
    def emit(value, own=None):
        if isinstance(value, (dict, list)):
            key = canonical(value)
            if key in pools and key != own:
                return f"P[{pools[key]}]"
            if isinstance(value, list):
                return "{" + ",".join(emit(child) for child in value) + "}"
            return "{" + ",".join("[" + lua_key(key) + "]=" + emit(value[key]) for key in sorted(value, key=lambda key: (type(key).__name__, str(key)))) + "}"
        return lua(value)
    lines = []
    for key in order:
        if key in pools:
            lines.append(f"P[{pools[key]}]=" + emit(values[key], own=key))
    lines.append("RikUI.QuestPlanner.SemanticData.Register(" + str(bucket) + "," + lua(revision) + "," + emit(rows) + ")")
    files, current, size = [], [], 0
    for line in lines:
        length = len(line.encode("utf-8")) + 1
        if length > 240 * 1024 - 256:
            raise ValueError("generated statement exceeds 240 KiB parser bound")
        if current and size + length > 240 * 1024 - 256:
            files.append(current)
            current, size = [], 0
        current.append(line)
        size += length
    if current:
        files.append(current)
    result = []
    for index, lines in enumerate(files):
        header = "-- Generated immutable local data. Do not redistribute.\n"
        header += "RikUIQuestCorpusPagePool={}\n" if index == 0 else ""
        header += "local P=RikUIQuestCorpusPagePool\n"
        tail = "\nRikUIQuestCorpusPagePool=nil\n" if index == len(files) - 1 else "\n"
        result.append(header + "\n".join(lines) + tail)
    return result


class Compiler:
    def __init__(self, data, source_hash):
        self.data = data
        self.report = {"schemaVersion": 1, "sourceSHA256": source_hash, "provider": data["provider"], "unknowns": [], "conflicts": [], "coverage": {}, "zones": {}, "variants": {}, "methodKinds": {}, "areaPolicy": {"coordinates": "normalized percentages; no reprojection", "clustering": "6 percent grid cells, actual-spawn representative, enclosing radius", "phase": "third coordinate is phase, never floor", "unknownFloors": "legacy dungeon aliases never become navigation targets"}}
        self.unknown_keys = set()
        self.context = "base"
        self.objective_first = data.get("objectiveFirst", {})
        self.set_maps(data)
        self.set_entities(data["base"])

    def set_maps(self, data):
        support = data.get("decodedSupport", self.data.get("decodedSupport", {}))
        zones = support.get("ZoneDB", {})
        private = zones.get("private", {})
        maps = data.get("maps", self.data.get("maps", {}))
        self.area_to_map = maps.get("areaToMap", private.get("areaIdToUiMapId", {}))
        overrides = maps.get("areaMapOverride", private.get("areaIdToUiMapIdOverride", {}))
        if not isinstance(self.area_to_map, dict) or not isinstance(overrides, dict):
            raise ValueError("decoded Forever area maps are required")
        self.dungeon_areas = {int(key) for key in overrides if int(key) not in (0, 10073, 10074, 10089)}
        dungeons = maps.get("dungeons", zones.get("dungeons", private.get("dungeons", {})))
        if isinstance(dungeons, dict):
            for key, row in dungeons.items():
                self.dungeon_areas.add(int(key))
                self.dungeon_areas.update(ids(slot(row, 2)))

    def unknown(self, code, entity, detail=None):
        entry = {"code": code, "entity": entity, "variant": self.context}
        if detail is not None:
            entry["detail"] = detail
        key = canonical(entry)
        if key not in self.unknown_keys:
            self.unknown_keys.add(key)
            self.report["unknowns"].append(entry)

    def set_entities(self, entities):
        self.entities, self.area_cache, self.method_cache, self.item_cache = entities, {}, {}, {}
        self.reciprocal = {"starts": collections.defaultdict(list), "ends": collections.defaultdict(list)}
        for entity_kind, target_kind in (("npcs", "npc"), ("objects", "object"), ("items", "item")):
            for target_id, row in entities[entity_kind].items():
                fields = (("startQuest", "starts"),) if target_kind == "item" else (("questStarts", "starts"), ("questEnds", "ends"))
                for field, direction in fields:
                    quest_ids = ([row[field]] if row.get(field) else []) if target_kind == "item" else ids(row.get(field))
                    for quest_id in quest_ids:
                        self.reciprocal[direction][int(quest_id)].append((target_kind, int(target_id)))

    def areas(self, spawns, source):
        if not spawns:
            return [], []
        if not isinstance(spawns, dict):
            raise ValueError(f"spawns must be area-keyed at {source}")
        result, unresolved = [], []
        for area_key in sorted(spawns, key=int):
            area_id = int(area_key)
            map_id = self.area_to_map.get(str(area_id))
            reason = "floor-map-unknown" if area_id in self.dungeon_areas else "ui-map-unknown" if not finite(map_id) or map_id <= 0 else None
            groups = collections.defaultdict(set)
            for index, point in sequence(spawns[area_key]):
                x, y, phase = slot(point, 1), slot(point, 2), slot(point, 3)
                if not finite(x) or not finite(y) or not 0 <= x <= 100 or not 0 <= y <= 100:
                    unresolved.append({"areaID": area_id, "reason": "coordinate-unknown", "sourceIndex": index})
                    self.unknown("coordinate-unknown", source, {"areaID": area_id, "index": index})
                    continue
                if phase is not None and not finite(phase):
                    raise ValueError(f"invalid phase at {source}/{area_id}/{index}")
                if reason:
                    unresolved.append({"areaID": area_id, "x": x / 100, "y": y / 100, "reason": reason, **({"phase": phase} if phase is not None else {})})
                    continue
                nx, ny = round(x / 100, 7), round(y / 100, 7)
                groups[(phase, int(nx / CELL_SIZE), int(ny / CELL_SIZE))].add((nx, ny))
            if reason:
                self.unknown(reason, source, {"areaID": area_id})
            for (phase, cx, cy), points in sorted(groups.items(), key=lambda item: (str(item[0][0]), item[0][1:])):
                points = sorted(points)
                avg_x, avg_y = sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)
                x, y = min(points, key=lambda p: ((p[0] - avg_x)**2 + (p[1] - avg_y)**2, p))
                radius = max(math.hypot(px - x, py - y) for px, py in points)
                area = {"id": f"{source}:{area_id}:{phase}:{cx}:{cy}", "areaID": area_id, "mapID": int(map_id), "x": x, "y": y, "radiusNormalized": round(radius, 7), "spawnCount": len(points), "floorKnown": False, "source": "QuestieDB", "precision": "spawn" if len(points) == 1 else "cluster", "bounds": {"minX": min(p[0] for p in points), "maxX": max(p[0] for p in points), "minY": min(p[1] for p in points), "maxY": max(p[1] for p in points)}}
                if phase is not None:
                    area["phase"] = phase
                result.append(area)
        return result, unresolved

    def entity_method(self, kind, target_kind, target_id):
        cache_key = (kind, target_kind, target_id)
        if cache_key in self.method_cache:
            return self.method_cache[cache_key]
        table = {"npc": "npcs", "object": "objects", "item": "items"}.get(target_kind)
        row = self.entities.get(table, {}).get(str(target_id))
        source = f"{target_kind}:{target_id}"
        method = {"kind": kind, "targetKind": target_kind, "targetID": target_id, "name": row.get("name", source) if row else source, "areas": [], "source": "QuestieDB"}
        if row is None:
            method["unknown"] = "record-missing"
            self.unknown("record-missing", source)
        elif target_kind in ("npc", "object"):
            if source not in self.area_cache:
                self.area_cache[source] = self.areas(row.get("spawns"), source)
            method["areas"], unknown = self.area_cache[source]
            by_map = collections.defaultdict(list)
            for area in method["areas"]:
                by_map[area["mapID"]].append(area)
            method["areasByMap"] = dict(by_map)
            if unknown:
                method["unresolvedAreas"] = unknown
            if not method["areas"]:
                method["unknown"] = "location-unknown"
                self.unknown("location-unknown", source)
            if target_kind == "npc":
                method["eligibility"] = {field: row[field] for field in ("friendlyToFaction", "minLevel", "maxLevel") if field in row}
                method["dispositionKnown"] = True
                method["friendlyToFaction"] = row.get("friendlyToFaction") or "none"
            if kind == "vendor":
                method["costKnown"] = False
        self.method_cache[cache_key] = method
        return method

    def item_methods(self, item_id, trail=()):
        if not trail and item_id in self.item_cache:
            return self.item_cache[item_id]
        row = self.entities["items"].get(str(item_id))
        if row is None:
            self.unknown("record-missing", f"item:{item_id}")
            return []
        if item_id in trail or len(trail) >= 12:
            self.unknown("item-cycle" if item_id in trail else "item-depth-bound", f"item:{item_id}", list(trail))
            return []
        result = []
        for field, kind, target_kind in (("npcDrops", "drop", "npc"), ("objectDrops", "loot", "object"), ("vendors", "vendor", "npc")):
            result.extend(self.entity_method(kind, target_kind, target_id) for target_id in sorted(set(ids(row.get(field)))))
        for container_id in sorted(set(ids(row.get("itemDrops")))):
            nested = self.item_methods(container_id, (*trail, item_id))
            if nested:
                result.extend({**method, "viaItemID": container_id, "acquisition": "container"} for method in nested)
            else:
                result.append(self.entity_method("container", "item", container_id))
        for quest_id in sorted(set(ids(row.get("questRewards")))):
            quest = self.entities["quests"].get(str(quest_id), {})
            result.append({"kind": "quest-reward", "targetKind": "quest", "targetID": quest_id, "name": quest.get("name", f"Quest {quest_id}"), "areas": [], "source": "QuestieDB"})
        result = list({canonical(method): method for method in result}.values())
        if not trail:
            self.item_cache[item_id] = result
        return result

    def objective(self, quest_id, objective_type, source_index, row):
        target_id = slot(row, 1)
        icon_type = None
        if objective_type == "kill-credit":
            target_id = slot(row, 2)
            text, icon_type, required = slot(row, 3), slot(row, 4), None
            target_ids = ids(slot(row, 1))
            action = ICON_ACTIONS.get(icon_type, "kill" if not icon_type else "unknown")
            methods = [self.entity_method(action, "npc", value) for value in target_ids]
            name = text or self.entities["npcs"].get(str(target_id), {}).get("name", f"NPC {target_id}")
        elif objective_type == "reputation":
            target_id, required = slot(row, 1), slot(row, 2)
            text, methods, name = None, [], f"Faction {target_id}"
        else:
            text, icon_type, required = slot(row, 2), slot(row, 3), None
            if not finite(target_id) or target_id != int(target_id):
                raise ValueError(f"invalid target at quest {quest_id}/{objective_type}/{source_index}")
            target_id = int(target_id)
            if objective_type == "monster":
                action = ICON_ACTIONS.get(icon_type, "kill" if not icon_type else "unknown")
                methods = [self.entity_method(action, "npc", target_id)]
                name = self.entities["npcs"].get(str(target_id), {}).get("name", f"NPC {target_id}")
            elif objective_type == "object":
                action = ICON_ACTIONS.get(icon_type, "interact" if not icon_type else "unknown")
                methods = [self.entity_method(action, "object", target_id)]
                name = self.entities["objects"].get(str(target_id), {}).get("name", f"Object {target_id}")
            elif objective_type == "item":
                methods = self.item_methods(target_id)
                if icon_type not in (None, 0, 1, 2):
                    action = ICON_ACTIONS.get(icon_type, "unknown")
                    methods = [{**method, "kind": action, "acquisitionKind": method["kind"], "iconType": icon_type} if method["kind"] in ("drop", "loot") else method for method in methods]
                name = self.entities["items"].get(str(target_id), {}).get("name", f"Item {target_id}")
            else:
                # Spell slot 3 is a source item, never an objective count.
                source_item = slot(row, 3)
                methods = self.item_methods(source_item) if finite(source_item) and source_item > 0 else []
                icon_type = None
                name, required = text or f"Spell {target_id}", None
        objective = {"id": f"{objective_type}:{target_id}:{source_index}", "type": objective_type, "targetID": target_id, "name": name, "methods": methods, "sourceIndex": source_index}
        if text:
            objective["text"] = text
        if icon_type is not None:
            objective["iconType"] = icon_type
        if finite(required) and required > 0:
            objective["required"] = required
        if objective_type == "spell" and slot(row, 3):
            objective["sourceItemID"] = slot(row, 3)
        if objective_type == "kill-credit":
            objective["creditTargetIDs"] = target_ids
        if not methods:
            objective["unknown"] = "acquisition-unknown" if objective_type == "item" else "location-unknown"
            self.unknown(objective["unknown"], f"quest:{quest_id}:{objective['id']}")
        return objective

    def relationships(self, quest_id, row, direction):
        field = "startedBy" if direction == "starts" else "finishedBy"
        declared = []
        for index, target_kind in ((1, "npc"), (2, "object"), (3, "item")):
            declared.extend((target_kind, target_id) for target_id in ids(slot(row.get(field), index)))
        reverse, declared_set = set(self.reciprocal[direction].get(quest_id, [])), set(declared)
        for pair in sorted(reverse - declared_set):
            self.report["conflicts"].append({"questID": quest_id, "field": field, "targetKind": pair[0], "targetID": pair[1], "kind": "reciprocal-only", "variant": self.context})
        # Explicit quest links win conflicts; missing quest links use inverse data.
        pairs = declared_set if declared_set else reverse
        result = []
        for target_kind, target_id in sorted(pairs):
            relation = self.entity_method("start" if direction == "starts" else "finish", target_kind, target_id)
            if target_kind == "item":
                relation = {**relation, "methods": self.item_methods(target_id)}
            result.append({**relation, "relationshipSource": "quest" if (target_kind, target_id) in declared_set else "entity"})
        return result

    def order_objectives(self, quest_id, row, objectives):
        """Reproduce the pinned Questie consumer's dense objective ordering.

        Questie@454b9d0 Database/QuestieDB.lua:1535-1661 visits these
        groups in order. Every flagged member is inserted at index one, so
        each flagged group reverses and later flagged groups take precedence.
        Its pairs() loops do not promise order for sparse tables: retain the
        semantic records but omit binding indices in that case.
        """
        for index in (1, 2, 3, 5, 6):
            source = sequence(slot(row.get("objectives"), index))
            if [position for position, _ in source] != list(range(1, len(source) + 1)):
                return objectives, False
        groups = collections.defaultdict(list)
        for objective in objectives:
            groups[objective["type"]].append(objective)
        flags = {"object": "objectObjectiveFirst", "item": "itemObjectiveFirst", "kill-credit": "killCreditObjectiveFirst", "spell": "spellObjectiveFirst", "event": "eventObjectiveFirst"}
        ordered = []
        for kind in ("monster", "object", "item", "reputation", "kill-credit", "spell", "event"):
            first = self.objective_first.get(flags.get(kind), {}).get(str(quest_id))
            for objective in sorted(groups[kind], key=lambda value: value["sourceIndex"]):
                if first:
                    ordered.insert(0, objective)
                else:
                    ordered.append(objective)
        for index, objective in enumerate(ordered, 1):
            objective["runtimeObjectiveIndex"] = index
        return ordered, True

    def compile_quest(self, quest_id, row):
        objectives = []
        for index, objective_type in ((1, "monster"), (2, "object"), (3, "item"), (5, "kill-credit"), (6, "spell")):
            for source_index, objective_row in sequence(slot(row.get("objectives"), index)):
                objectives.append(self.objective(quest_id, objective_type, source_index, objective_row))
        reputation = slot(row.get("objectives"), 4)
        if reputation:
            objectives.append(self.objective(quest_id, "reputation", 1, reputation))
        trigger = row.get("triggerEnd")
        if trigger:
            areas, unknown = self.areas(slot(trigger, 2), f"quest:{quest_id}:event")
            method = {"kind": "explore", "targetKind": "event", "name": slot(trigger, 1) or "Explore", "areas": areas}
            if unknown:
                method["unresolvedAreas"] = unknown
            objectives.append({"id": f"event:{quest_id}:1", "type": "event", "targetID": quest_id, "name": slot(trigger, 1) or "Explore", "methods": [method], "sourceIndex": 1})
        objectives, objective_order_known = self.order_objectives(quest_id, row, objectives)
        extras = []
        for index, extra in sequence(row.get("extraObjectives")):
            text = slot(extra, 3) or "Additional objective"
            areas, unknown = self.areas(slot(extra, 1), f"quest:{quest_id}:extra:{index}")
            methods = []
            if areas or unknown:
                icon_type = slot(extra, 2)
                action = ICON_ACTIONS.get(icon_type, "explore" if not icon_type else "unknown")
                method = {"kind": action, "targetKind": "event", "name": text, "areas": areas, "iconType": icon_type}
                if unknown:
                    method["unresolvedAreas"] = unknown
                methods.append(method)
            for _, reference in sequence(slot(extra, 5)):
                kind, target_id = slot(reference, 1), slot(reference, 2)
                if kind == "item":
                    icon_type = slot(extra, 2)
                    item_methods = self.item_methods(target_id)
                    if icon_type not in (None, 0, 1, 2):
                        item_methods = [{**method, "kind": ICON_ACTIONS.get(icon_type, "unknown"), "acquisitionKind": method["kind"], "iconType": icon_type} if method["kind"] in ("drop", "loot") else method for method in item_methods]
                    methods.extend(item_methods)
                elif kind in ("monster", "object"):
                    icon_type = slot(extra, 2)
                    default = "kill" if kind == "monster" else "interact"
                    action = ICON_ACTIONS.get(icon_type, default if not icon_type else "unknown")
                    methods.append(self.entity_method(action, "npc" if kind == "monster" else "object", target_id))
                else:
                    self.unknown("extra-reference-kind", f"quest:{quest_id}:extra:{index}", reference)
            extras.append({"id": f"extra:{quest_id}:{index}", "type": "extra", "name": text, "text": text, "objectiveIndex": slot(extra, 4), "iconType": slot(extra, 2), "methods": methods})
        quest = {"id": quest_id, "title": row.get("name", f"Quest {quest_id}"), "objectives": objectives, "extraObjectives": extras, "starts": self.relationships(quest_id, row, "starts"), "ends": self.relationships(quest_id, row, "ends"), "eligibility": {field: row[field] for field in ELIGIBILITY if field in row}, "prerequisites": {field: row[field] for field in PREREQUISITES if field in row}, "provenance": {"provider": "QuestieDB", "revision": PIN, "flavor": "Forever"}}
        if not objective_order_known:
            quest["objectiveOrderUnknown"] = "sparse-source-objectives"
        for field in ("zoneOrSort", "objectivesText", "reputationReward"):
            if field in row:
                quest[field] = row[field]
        hints = {field: True for field, members in self.objective_first.items() if isinstance(members, dict) and members.get(str(quest_id))}
        if hints:
            quest["objectiveOrderHints"] = hints
        source_items = sorted(set(ids(row.get("requiredSourceItems"))))
        if row.get("sourceItemId"):
            quest["providedItemID"] = row["sourceItemId"]
        if source_items:
            quest["requiredItems"] = [{"itemID": value, "methods": self.item_methods(value)} for value in source_items]
        return quest

    def compile(self):
        base, records = self.data["base"], {}
        for quest_id in sorted(base["quests"], key=int):
            records[int(quest_id)] = {"base": self.compile_quest(int(quest_id), base["quests"][quest_id]), "variants": {}}
        self.coverage(records)
        for variant in self.data.get("variants", []):
            self.context = selector_key(variant["selector"])
            entities = {kind: {**base[kind], **variant.get(kind, {})} for kind in KINDS}
            for kind in KINDS:
                for removed in variant.get(kind + "Removed", variant.get("removed", {}).get(kind, [])):
                    entities[kind].pop(str(removed), None)
            self.set_maps(variant)
            self.objective_first = variant.get("objectiveFirst", self.data.get("objectiveFirst", {}))
            self.set_entities(entities)
            changed = 0
            for quest_id in sorted(entities["quests"], key=int):
                quest = self.compile_quest(int(quest_id), entities["quests"][quest_id])
                record = records.setdefault(int(quest_id), {"variants": {}})
                if quest != record.get("base"):
                    record["variants"][self.context] = quest
                    changed += 1
            for quest_id in set(base["quests"]) - set(entities["quests"]):
                records[int(quest_id)]["variants"][self.context] = False
                changed += 1
            self.report["variants"][self.context] = {"changedQuestRecords": changed, "entityOverrides": {kind: len(variant.get(kind, {})) for kind in KINDS}}
        self.report["unknowns"].sort(key=canonical)
        self.report["conflicts"].sort(key=canonical)
        self.report["counts"] = {kind: len(base[kind]) for kind in KINDS}
        self.report["counts"].update(compiledQuests=len(records), unknowns=len(self.report["unknowns"]), conflicts=len(self.report["conflicts"]))
        self.report["diagnosticEvaluations"] = {"baseCount": 1, "personaCount": len(self.data.get("variants", [])), "totalCount": 1 + len(self.data.get("variants", [])), "policy": "Baseline and every exported persona are evaluated separately; diagnostic occurrence counts include repeats. Unique counts remove only the variant label."}
        def diagnostic_summary(rows):
            normalized = lambda row: canonical({key: value for key, value in row.items() if key != "variant"})
            return {"uniqueAcrossEvaluations": len({normalized(row) for row in rows}), "uniqueAcrossPersonas": len({normalized(row) for row in rows if row["variant"] != "base"}), "evaluationOccurrences": len(rows), "personaOccurrences": sum(row["variant"] != "base" for row in rows), "baseOccurrences": sum(row["variant"] == "base" for row in rows)}
        self.report["unknownSummary"] = diagnostic_summary(self.report["unknowns"])
        self.report["unknownSummary"]["baseByReason"] = dict(sorted(collections.Counter(row["code"] for row in self.report["unknowns"] if row["variant"] == "base").items()))
        self.report["conflictSummary"] = diagnostic_summary(self.report["conflicts"])
        self.report["conflictSummary"]["affectedQuestIDs"] = sorted({row["questID"] for row in self.report["conflicts"]})
        self.report["limitations"] = {"vendorPrices": "not supplied by provider; costKnown false and affordability unknown", "sourceItemUse": "item references and icon action hints preserved; no invented spell, target, or use action", "floorIdentity": "not supplied by spawn coordinates", "questCounts": "objective counts not supplied by positional icon fields; use live quest progress", "rawAudit": "all source fields, translations, support/drop tables and unsupported metadata retained"}
        return records

    def coverage(self, records):
        schema_names = {"quests": "Quest", "npcs": "Npc", "items": "Item", "objects": "Object"}
        for kind in KINDS:
            rows = self.data["base"][kind]
            present = collections.Counter(field for row in rows.values() for field in row)
            nonempty_values = collections.Counter(field for row in rows.values() for field, value in row.items() if nonempty(value))
            nondefault_values = collections.Counter(field for row in rows.values() for field, value in row.items() if nondefault(value))
            schema_fields = self.data.get("schema", {}).get(schema_names[kind], {}).get("keys", {})
            fields = set(present) | set(schema_fields)
            self.report["coverage"][kind] = {field: {"present": present[field], "nonempty": nonempty_values[field], "nonDefault": nondefault_values[field], "denominator": len(rows), "handling": "semantic" if field in SEMANTIC_FIELDS[kind] else "raw-audit-only"} for field in sorted(fields)}
        self.report["fieldCoveragePolicy"] = {"population": "baseline entity records only; all declared schema fields and observed additional fields", "present": "field key exists, including zero and empty defaults", "nonempty": "value is not null, empty string, empty list or empty object; numeric zero is included", "nonDefault": "at least one scalar leaf is nonempty and neither zero nor false", "handling": "semantic means compiler consumes or preserves the field in semantic records; raw-audit-only means source export retention only", "limitation": "Storage and handling counts do not establish semantic correctness or gameplay completeness; zero can be a meaningful unrestricted value."}
        zones = collections.defaultdict(lambda: {"quests": 0, "objectives": 0, "objectivesWithMethods": 0, "objectivesWithAreas": 0, "starts": 0, "ends": 0})
        kinds = collections.Counter()
        for record in records.values():
            quest = record["base"]
            zone = zones[str(quest.get("zoneOrSort", "unknown"))]
            zone["quests"] += 1
            zone["starts"] += bool(quest["starts"])
            zone["ends"] += bool(quest["ends"])
            for objective in quest["objectives"]:
                zone["objectives"] += 1
                zone["objectivesWithMethods"] += bool(objective["methods"])
                zone["objectivesWithAreas"] += any(method.get("areas") for method in objective["methods"])
                kinds.update(method["kind"] for method in objective["methods"])
        self.report["zones"] = dict(sorted(zones.items()))
        self.report["methodKinds"] = dict(sorted(kinds.items()))
        self.report["questCoverage"] = {key: sum(zone[key] for zone in zones.values()) for key in ("quests", "objectives", "objectivesWithMethods", "objectivesWithAreas", "starts", "ends")}


def write_bytes(root, relative, data):
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)


def write_json(root, relative, value):
    write_bytes(root, relative, (canonical(value) + "\n").encode("utf-8"))


OWNERSHIP_FILE = ".rikui-corpus-owned.json"
COMPANION_PATTERN = r"RikUIQuestCorpus_P[0-9]{5}(?:_S[0-9]{3})?"


def owned_files(folder):
    if folder.is_symlink():
        raise ValueError("refusing symbolic-link companion directory")
    result = {}
    for path in sorted(folder.rglob("*")):
        if path.is_symlink():
            raise ValueError("refusing symbolic link in generated companions")
        if path.is_file() and path != folder / OWNERSHIP_FILE:
            result[path.relative_to(folder).as_posix()] = sha(path.read_bytes())
    return result


def verify_owned(folder):
    marker = folder / OWNERSHIP_FILE
    if not marker.is_file():
        raise ValueError(f"refusing unowned existing companion directory: {folder}")
    metadata = json.loads(marker.read_text(encoding="utf-8"))
    if metadata.get("owner") != "RikUI quest_corpus" or metadata.get("files") != owned_files(folder):
        raise ValueError(f"existing companion has unowned or modified files: {folder}")


def manifest_files(root):
    return {path.relative_to(root).as_posix(): {"sha256": sha(path.read_bytes()), "bytes": path.stat().st_size} for path in sorted(root.rglob("*")) if path.is_file() and path != root / "manifest.json"}


def safe_output(path):
    path = Path(path).resolve()
    if path == Path(path.anchor) or len(path.parts) < 3:
        raise ValueError("output must be a dedicated nested build directory")
    return path


def atomic_publish(stage, destination):
    destination = safe_output(destination)
    backup = destination.with_name(destination.name + ".previous")
    if backup.exists():
        raise ValueError(f"backup exists; inspect before retrying: {backup}")
    had_old = destination.exists()
    if had_old and not (destination / "manifest.json").is_file():
        raise ValueError("refusing to replace directory without corpus manifest")
    if had_old:
        destination.replace(backup)
    try:
        stage.replace(destination)
    except BaseException:
        if had_old:
            backup.replace(destination)
        raise
    if had_old:
        shutil.rmtree(backup)


def load_client_index(path):
    raw = Path(path).read_bytes()
    if len(raw) > 64 * 1024 * 1024:
        raise ValueError("client index exceeds 64 MiB bound")
    if sha(raw) != CLIENT_INDEX_SHA256:
        raise ValueError("QuestV2 CSV is not the audited exact-build 1.60.1.69913 index")
    rows = {}
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    if reader.fieldnames != ["ID", "UniqueBitFlag", "UiQuestDetailsThemeID"]:
        raise ValueError("unsupported QuestV2 client index columns")
    for row in reader:
        try:
            normalized = {key: int(value) for key, value in row.items()}
        except (ValueError, TypeError) as error:
            raise ValueError("malformed QuestV2 row") from error
        quest_id = normalized["ID"]
        if quest_id in rows or not 0 < quest_id < 2**31:
            raise ValueError("invalid or duplicate QuestV2 ID")
        rows[quest_id] = normalized
    return rows, raw


def add_client_records(records, rows, report):
    provider_ids, client_ids = set(records), set(rows)
    report["clientUniverse"] = {"clientIDs": len(client_ids), "providerIDs": len(provider_ids), "overlap": len(client_ids & provider_ids), "clientOnly": len(client_ids - provider_ids), "providerOnly": len(provider_ids - client_ids), "union": len(client_ids | provider_ids), "clientOnlyIDs": sorted(client_ids - provider_ids), "providerOnlyIDs": sorted(provider_ids - client_ids), "semantics": "membership only; no names, objectives, locations, or inferred rules"}
    for quest_id in sorted(client_ids - provider_ids):
        records[quest_id] = {"base": {"id": quest_id, "title": "", "objectives": [], "extraObjectives": [], "starts": [], "ends": [], "eligibility": {}, "prerequisites": {}, "known": {"clientRecord": True, "semanticRecord": False}, "provenance": {"provider": "QuestV2", "build": IDENTITY["build"], "fields": rows[quest_id]}}, "variants": {}}
    for quest_id in provider_ids:
        for quest in [records[quest_id].get("base"), *records[quest_id]["variants"].values()]:
            if isinstance(quest, dict):
                quest["known"] = {"clientRecord": quest_id in client_ids, "semanticRecord": True}
    report["counts"]["compiledQuests"] = len(records)


def verify_provider_manifest(path, data, raw):
    proof_raw = Path(path).read_bytes()
    proof = json.loads(proof_raw)
    if proof.get("schemaVersion") != 1 or proof.get("revision") != PIN or proof.get("flavor") != "Forever":
        raise ValueError("provider provenance manifest identity mismatch")
    if proof.get("exportSha256") != sha(raw) or proof.get("exportBytes") != len(raw):
        raise ValueError("provider export does not match acquisition manifest bytes/hash")
    counts = {singular: len(data["base"][plural]) for singular, plural in (("Quest", "quests"), ("Npc", "npcs"), ("Item", "items"), ("Object", "objects"))}
    classes = ("WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID")
    expected = {faction + ":" + class_file for faction in ("Alliance", "Horde") for class_file in classes}
    selectors = {selector_key(variant["selector"]) for variant in data.get("variants", [])}
    if proof.get("counts") != counts or proof.get("personaCount") != 18 or selectors != expected:
        raise ValueError("provider manifest counts or complete persona coverage mismatch")
    inputs = proof.get("inputs", [])
    if len(inputs) != 135 or len({row.get("path") for row in inputs}) != len(inputs):
        raise ValueError("pinned provider must include 135 unique hashed source inputs")
    for row in inputs:
        path = Path(row.get("path", ""))
        if path.is_absolute() or ".." in path.parts or not re.fullmatch(r"[0-9a-f]{64}", row.get("sha256", "")):
            raise ValueError("malformed provider source input provenance")
    metadata = {"manifestSHA256": sha(proof_raw), "inputFiles": len(inputs), "exportSha256": sha(raw), "revision": PIN, "personaCount": 18}
    return metadata, proof_raw


def corpus_revision(source_hash, compiler_hash, proof_hash, client_hash, identity, partition_size):
    """Bind runtime cache identity to every input that can alter generated data."""
    inputs = {"schemaVersion": 1, "sourceSHA256": source_hash, "compilerSHA256": compiler_hash, "providerManifestSHA256": proof_hash, "clientIndexSHA256": client_hash, "identity": identity, "partitionSize": partition_size}
    return sha(canonical(inputs).encode("utf-8"))


def build(export_path, output, partition_size=PARTITION_SIZE, client_index=None, provider_manifest=None):
    if not 16 <= partition_size <= 256:
        raise ValueError("partition size must be 16..256")
    data, raw = load_export(export_path)
    compiler_hash = sha(Path(__file__).read_bytes())
    proof, proof_raw = verify_provider_manifest(provider_manifest, data, raw) if provider_manifest else (None, None)
    compiler = Compiler(data, sha(raw))
    records = compiler.compile()
    if proof:
        compiler.report["providerProof"] = proof
    client_raw, client_metadata = None, None
    if client_index:
        client_rows, client_raw = load_client_index(client_index)
        add_client_records(records, client_rows, compiler.report)
        client_metadata = {"sha256": sha(client_raw), "build": IDENTITY["build"], "table": "QuestV2", "records": len(client_rows)}
    revision = corpus_revision(sha(raw), compiler_hash, proof["manifestSHA256"] if proof else None, client_metadata["sha256"] if client_metadata else None, IDENTITY, partition_size)
    output = safe_output(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=output.name + ".building-", dir=output.parent))
    try:
        partitions = collections.defaultdict(dict)
        for quest_id, row in records.items():
            partitions[quest_id // partition_size][quest_id] = row
        names = {}
        catalog = {"version": 1, "identity": IDENTITY, "revision": revision, "providerRevision": PIN, "sourceSHA256": sha(raw), "partitionSize": partition_size, "partitions": names, "counts": compiler.report["counts"], "baseSelector": "Alliance:WARRIOR", "selectors": sorted(selector_key(variant["selector"]) for variant in data.get("variants", [])), "terms": "local-only; upstream redistribution grant unresolved"}
        if client_metadata:
            catalog["clientIndex"] = client_metadata
        toc = "## Interface: 16001\n## Title: RikUI Forever Quest Corpus\n## Notes: Local generated QuestieDB data; provenance in build manifest\n## LoadOnDemand: 1\n"
        write_bytes(stage, "addons/RikUIQuestCorpus/RikUIQuestCorpus.toc", (toc + "Catalog.lua\n").encode())
        for bucket, rows in sorted(partitions.items()):
            partition_name = f"RikUIQuestCorpus_P{bucket:05d}"
            bodies = lua_partition(bucket, rows, revision)
            if len(bodies) > 999:
                raise ValueError("partition exceeds 999 shard bound")
            shard_names = [f"{partition_name}_S{index + 1:03d}" for index in range(len(bodies))]
            names[bucket] = {"addons": shard_names}
            for name, body in zip(shard_names, bodies):
                write_bytes(stage, f"addons/{name}/{name}.toc", (toc + "## Dependencies: RikUI, RikUIQuestCorpus\nData.lua\n").encode())
                write_bytes(stage, f"addons/{name}/Data.lua", body.encode("utf-8"))
        write_bytes(stage, "addons/RikUIQuestCorpus/Catalog.lua", ("RikUIQuestCorpusCatalog=" + lua(catalog) + "\n").encode("utf-8"))
        write_json(stage, "catalog.json", catalog)
        write_json(stage, "coverage.json", compiler.report)
        write_bytes(stage, "audit/source-export.json", raw)
        if proof_raw:
            write_bytes(stage, "audit/provider-manifest.json", proof_raw)
        if client_raw is not None:
            write_bytes(stage, "audit/QuestV2.csv", client_raw)
        write_json(stage, "audit/semantic-quests.json", records)
        write_bytes(stage, "LOCAL_ONLY.txt", b"Locally generated from QuestieDB. No upstream redistribution grant has been established. Do not commit or distribute generated data.\n")
        for folder in (stage / "addons").iterdir():
            write_json(folder, OWNERSHIP_FILE, {"owner": "RikUI quest_corpus", "sourceSHA256": sha(raw), "files": owned_files(folder)})
        manifest = {"schemaVersion": 1, "compilerVersion": 1, "compilerSHA256": compiler_hash, "corpusRevision": revision, "provider": data["provider"], "identity": IDENTITY, "sourceSHA256": sha(raw), "partitionSize": partition_size, "terms": catalog["terms"], "counts": compiler.report["counts"], "files": manifest_files(stage)}
        if proof:
            manifest["providerProof"] = proof
        if client_metadata:
            manifest["clientIndex"] = client_metadata
        write_json(stage, "manifest.json", manifest)
        verify(stage)
        atomic_publish(stage, output)
        return manifest
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def verify(output):
    output = safe_output(output)
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1 or manifest.get("provider", {}).get("revision") != PIN:
        raise ValueError("invalid corpus manifest")
    revision = corpus_revision(manifest.get("sourceSHA256"), manifest.get("compilerSHA256"), manifest.get("providerProof", {}).get("manifestSHA256"), manifest.get("clientIndex", {}).get("sha256"), manifest.get("identity"), manifest.get("partitionSize"))
    if manifest.get("corpusRevision") != revision:
        raise ValueError("corpus revision does not match build inputs")
    actual, expected = manifest_files(output), manifest.get("files", {})
    if actual != expected:
        missing, extra = sorted(set(expected) - set(actual)), sorted(set(actual) - set(expected))
        changed = sorted(key for key in set(actual) & set(expected) if actual[key] != expected[key])
        raise ValueError(f"verification failed: missing={missing[:8]} unexpected={extra[:8]} changed={changed[:8]}")
    if sha((output / "audit/source-export.json").read_bytes()) != manifest.get("sourceSHA256"):
        raise ValueError("source hash mismatch")
    return manifest


def install(output, addons):
    output, addons = safe_output(output), Path(addons).resolve()
    manifest = verify(output)
    if not addons.is_dir() or addons.name.lower() != "addons":
        raise ValueError("installation target must be an existing AddOns directory")
    source = output / "addons"
    generated = {path.name for path in source.iterdir() if path.is_dir()}
    existing = {path.name for path in addons.iterdir() if path.is_dir() and (path.name == "RikUIQuestCorpus" or re.fullmatch(COMPANION_PATTERN, path.name))}
    for name in sorted(existing):
        verify_owned(addons / name)
    staging = Path(tempfile.mkdtemp(prefix=".rikuicorpus-install-", dir=addons.parent))
    backup = staging / "previous"
    backup.mkdir()
    placed, moved, cleanup = [], [], True
    try:
        for name in sorted(generated):
            shutil.copytree(source / name, staging / name)
        for name in sorted(existing):
            (addons / name).replace(backup / name)
            moved.append(name)
        for name in sorted(generated):
            (staging / name).replace(addons / name)
            placed.append(name)
        verify_installed(output, addons)
    except BaseException as original:
        try:
            for name in placed:
                shutil.rmtree(addons / name)
            for name in moved:
                (backup / name).replace(addons / name)
        except BaseException as rollback_error:
            cleanup = False
            write_json(staging, "RECOVERY.json", {"target": str(addons), "placed": placed, "moved": moved, "error": str(original), "rollbackError": str(rollback_error), "instruction": "Keep this directory; remaining prior companions are in previous/."})
            raise RuntimeError(f"install rollback incomplete; backup retained at {staging}") from rollback_error
        raise
    finally:
        if cleanup:
            shutil.rmtree(staging)
    return {"installedAddons": len(generated), "removedStaleAddons": sorted(existing - generated), "sourceSHA256": manifest["sourceSHA256"]}


def verify_installed(output, addons):
    output, addons = Path(output), Path(addons).resolve()
    manifest = verify(output)
    expected = {key.removeprefix("addons/"): value for key, value in manifest["files"].items() if key.startswith("addons/")}
    actual = {}
    for folder in addons.iterdir():
        if folder.is_dir() and (folder.name == "RikUIQuestCorpus" or re.fullmatch(COMPANION_PATTERN, folder.name)):
            for path in folder.rglob("*"):
                if path.is_file():
                    actual[path.relative_to(addons).as_posix()] = {"sha256": sha(path.read_bytes()), "bytes": path.stat().st_size}
    if actual != expected:
        raise ValueError("installed files differ from exact manifest, including stale files")
    return {"verifiedFiles": len(expected)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    make = sub.add_parser("build")
    make.add_argument("--export", required=True, type=Path)
    make.add_argument("--output", required=True, type=Path)
    make.add_argument("--partition-size", default=PARTITION_SIZE, type=int)
    make.add_argument("--client-index", type=Path)
    make.add_argument("--provider-manifest", type=Path)
    for name in ("verify", "install", "verify-installed"):
        command = sub.add_parser(name)
        command.add_argument("--output", required=True, type=Path)
        if name != "verify":
            command.add_argument("--addons", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "build":
            provider_manifest = args.provider_manifest or args.export.with_suffix(".manifest.json")
            if not provider_manifest.is_file():
                raise ValueError("build requires the exporter's provider provenance manifest")
            result = build(args.export, args.output, args.partition_size, args.client_index, provider_manifest)
        elif args.command == "verify":
            result = verify(args.output)
        elif args.command == "install":
            result = install(args.output, args.addons)
        else:
            result = verify_installed(args.output, args.addons)
        print(canonical({key: value for key, value in result.items() if key != "files"}))
    except (ValueError, OSError) as error:
        parser.exit(1, f"quest_corpus: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


