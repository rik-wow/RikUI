"""Build an independent CMaNGOS snapshot without changing RikUI's current provider."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess

from mariadb_session import BuildDatabase
from normalize import normalize, compare_baseline

SOURCE_URL = "https://github.com/cmangos/classic-db"
CORE_URL = "https://github.com/cmangos/mangos-classic"
TABLES = ("quest_template", "creature_template", "gameobject_template", "item_template",
          "creature", "gameobject", "creature_spawn_entry", "gameobject_spawn_entry",
          "creature_questrelation", "creature_involvedrelation", "gameobject_questrelation",
          "gameobject_involvedrelation", "creature_loot_template", "gameobject_loot_template",
          "item_loot_template", "reference_loot_template", "conditions",
          "creature_conditional_spawn", "game_event_creature", "game_event_gameobject",
          "game_event_quest", "quest_pool", "pool_quest", "quest_relations",
          "creature_zone", "gameobject_zone")


def revision(root):
    result = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], check=True,
                            capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", str(root), "status", "--porcelain", "--untracked-files=no"],
                           check=True, capture_output=True, text=True).stdout
    if not re.fullmatch(r"[a-f0-9]{40}", result) or dirty:
        raise ValueError("Source checkout must have a clean, resolved revision")
    return result


def apply_group(db, root, pattern, role):
    paths = sorted(root.glob(pattern))
    for path in paths:
        db.apply(path, root, role)
    return len(paths)


def apply_sources(db, source, core):
    db.apply(core / "sql/base/mangos.sql", core, "core-schema")
    bases = list(source.glob("Full_DB/*.sql.gz"))
    if len(bases) != 1:
        raise ValueError("Expected exactly one full upstream database")
    db.apply(bases[0], source, "database-base")
    print("Imported base; applying content and instance updates", flush=True)
    apply_group(db, source, "Updates/[0-9]*.sql", "database-update")
    apply_group(db, source, "Updates/Instances/[0-9]*.sql", "instance-update")
    fields = db.query("SHOW COLUMNS FROM db_version;")
    match = re.search(r"required_z(\d+)_(\d+)", fields)
    if not match:
        raise ValueError("Missing core schema version")
    current = tuple(map(int, match.groups()))
    for path in sorted((core / "sql/updates/mangos").glob("z*_mangos_*.sql")):
        version = re.match(r"z(\d+)_(\d+)", path.name)
        if version and tuple(map(int, version.groups())) > current:
            db.apply(path, core, "core-update")
    for pattern, role in (("sql/base/dbc/original_data/*.sql", "dbc-source"),
                          ("sql/base/dbc/cmangos_fixes/*.sql", "dbc-correction"),
                          ("sql/scriptdev2/*.sql", "scriptdev2")):
        apply_group(db, core, pattern, role)
    db.apply(source / "ACID/acid_classic.sql", source, "event-scripts")
    db.apply(source / "utilities/cmangos_custom.sql", source, "upstream-custom")
    return db.query("SELECT version FROM db_version;").strip()


def export_raw(db, output):
    present = set(db.query("SHOW TABLES;").splitlines())
    data = {}
    for table in TABLES:
        if table in present:
            data[table] = db.rows(table)
            print(table + ": " + str(len(data[table])), flush=True)
    connection = sqlite3.connect(output / "quest-data.sqlite")
    connection.execute("CREATE TABLE source_rows (source_table TEXT NOT NULL, ordinal INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(source_table,ordinal))")
    for table, rows in data.items():
        ordered = sorted((json.dumps(row, sort_keys=True, ensure_ascii=False) for row in rows))
        connection.executemany("INSERT INTO source_rows VALUES (?,?,?)",
                               ((table, index, row) for index, row in enumerate(ordered)))
    connection.commit()
    connection.close()
    return data, sorted(set(TABLES) - present)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def build(args):
    source, core, output = args.source_root.resolve(), args.core_root.resolve(), args.output.resolve()
    identities = {"database": revision(source), "core": revision(core)}
    output.mkdir(parents=True, exist_ok=False)
    db = BuildDatabase(args.mariadb_bin, output / "build-server")
    try:
        db.start()
        version = apply_sources(db, source, core)
        raw, absent = export_raw(db, output)
        normalized = normalize(raw)
        write_json(output / "provider.json", normalized)
        report = {"counts": {name: len(rows) for name, rows in raw.items()},
                  "missingOptionalTables": absent, "upstreamVersion": version,
                  "normalized": normalized["counts"], "foreverCoordinatesVerified": False}
        if args.baseline:
            report["comparison"] = compare_baseline(normalized, args.baseline)
        write_json(output / "coverage.json", report)
        for name in ("LICENSE.md", "COPYRIGHT.md", "AUTHORS"):
            shutil.copyfile(source / name, output / name)
        manifest = {"schemaVersion": 1, "provider": "CMaNGOS Classic-DB",
                    "source": SOURCE_URL, "coreSource": CORE_URL, "revisions": identities,
                    "sourceClient": "original WoW 1.12", "targetCompatibility": "Forever unverified",
                    "inputs": db.inputs, "license": "GPL-3.0 with upstream Blizzard-content exclusions",
                    "publicRedistribution": "unresolved for excluded game content",
                    "outputs": {}}
        for name in ("provider.json", "coverage.json", "quest-data.sqlite", "LICENSE.md", "COPYRIGHT.md", "AUTHORS"):
            payload = (output / name).read_bytes()
            manifest["outputs"][name] = {"sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload)}
        write_json(output / "manifest.json", manifest)
        print(json.dumps(report, ensure_ascii=False))
    finally:
        db.stop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New output directory; never overwrites")
    parser.add_argument("--mariadb-bin", type=Path, default=Path("C:/Program Files/MariaDB 12.1/bin"))
    parser.add_argument("--baseline", type=Path, help="Existing corpus ZIP for read-only coverage comparison")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
