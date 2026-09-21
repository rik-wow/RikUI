"""Pinned local quest-source acquisition. Only demonstrated semantics are emitted."""
import argparse
import csv
import hashlib
import io
import json
import struct
import sys
import urllib.error
import urllib.request
from pathlib import Path

PARSER_REVISION = "rikui-quest-acquire-v1"
MAX_BYTES = 16 * 1024 * 1024
MAX_ROWS = 8192


def checked(raw, expected_hash):
    if len(raw) > MAX_BYTES:
        raise ValueError("source exceeds 16 MiB")
    digest = hashlib.sha256(raw).hexdigest()
    if digest != expected_hash:
        raise ValueError("source SHA256 mismatch")
    return digest


def quest_index(raw, expected_hash, build, uri):
    digest = checked(raw, expected_hash)
    if not build.startswith("1.60.") or not all(part.isdigit() for part in build.split(".")):
        raise ValueError("explicit Forever build required")
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    columns = ["ID", "UniqueBitFlag", "UiQuestDetailsThemeID"]
    if reader.fieldnames != columns:
        raise ValueError("unsupported QuestV2 columns")
    rows, seen = [], set()
    for source in reader:
        if len(rows) >= MAX_ROWS or None in source:
            raise ValueError("invalid or oversized QuestV2 source")
        row = {key: int(source[key]) for key in columns}
        if row["ID"] <= 0 or row["ID"] in seen or any(v < 0 or v > 2147483647 for v in row.values()):
            raise ValueError("invalid or duplicate QuestV2 ID/value")
        seen.add(row["ID"])
        rows.append(row)
    rows.sort(key=lambda row: row["ID"])
    source_id = "questv2-" + digest[:16]
    return {
        "version": 1,
        "identity": {"product": "forever", "build": build, "locale": "enUS"},
        "source": {
            "id": source_id, "dataset": "questv2", "product": "forever", "build": build, "locale": "enUS",
            "authority": "verified", "status": "active", "mode": "snapshot", "assertions": len(rows),
            "revision": digest, "sha256": digest, "parser": PARSER_REVISION, "parserSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "uri": uri,
            "terms": "Blizzard game data via Wago; redistribution terms not established",
        },
        "index": rows,
        "assertions": [{"questID": row["ID"], "field": "clientRecord", "value": True, "source": source_id} for row in rows],
        "coverage": {"clientRecords": len(rows), "worldQuestDenominator": "unknown", "routingFields": "unknown"},
        "limits": "Client table membership and flags only; not availability, prerequisites, XP or walkability.",
    }


def cache_inventory(raw, expected_hash):
    digest = checked(raw, expected_hash)
    if len(raw) < 24:
        raise ValueError("truncated WDB header")
    signature, build, locale, record_size, record_version, format_version = struct.unpack_from("<4sI4sIII", raw)
    signature, locale = signature[::-1], locale[::-1]
    if signature != b"WQST" or locale != b"enUS" or build != 69913 or record_version != 12 or format_version != 0:
        raise ValueError("unsupported WDB framing identity")
    at, records, seen = 24, [], set()
    while at < len(raw):
        if len(raw) - at < 8:
            raise ValueError("truncated WDB record header")
        quest_id, size = struct.unpack_from("<II", raw, at)
        at += 8
        if quest_id == 0 and size == 0:
            if at != len(raw):
                raise ValueError("trailing WDB bytes")
            break
        if quest_id == 0 or quest_id in seen or size == 0 or at + size > len(raw) or len(records) >= MAX_ROWS:
            raise ValueError("invalid WDB record framing")
        records.append({"questID": quest_id, "bytes": size, "sha256": hashlib.sha256(raw[at:at + size]).hexdigest()})
        seen.add(quest_id)
        at += size
    return {
        "version": 1, "parser": PARSER_REVISION, "sha256": digest, "build": build, "locale": locale.decode(),
        "recordSizeHeader": record_size, "recordVersion": record_version, "formatVersion": format_version,
        "records": records, "semanticSupport": False,
        "limits": "Cached response IDs only. Payload fields remain undecoded; this is neither current log nor world coverage.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["questv2", "wdb"])
    parser.add_argument("source")
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--build", default="1.60.1.69913")
    parser.add_argument("--uri")
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    try:
        if args.source.startswith("https://"):
            with urllib.request.urlopen(args.source, timeout=30) as response:
                raw = response.read(MAX_BYTES + 1)
        else:
            path = Path(args.source)
            if path.stat().st_size > MAX_BYTES:
                parser.error("source exceeds 16 MiB")
            raw = path.read_bytes()
        result = (quest_index(raw, args.sha256, args.build, args.uri or args.source) if args.kind == "questv2"
                  else cache_inventory(raw, args.sha256))
    except (ValueError, UnicodeError, KeyError, TypeError, OSError, urllib.error.URLError) as error:
        parser.error(str(error))
    if args.summary:
        result = {key: value for key, value in result.items() if key not in {"index", "assertions", "records"}}
    json.dump(result, sys.stdout, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
