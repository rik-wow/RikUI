"""Inspect or archive a bounded RikUI RIKQ1 observation packet; never emit world facts.

Usage:
    python quest_observations.py inspect quest-export.txt
    python quest_observations.py import quest-export.txt --out observation.json

The input may have one terminal LF or CRLF from saving a text file. All other
packet bytes are exact. Archives preserve Lua table key types and arbitrary byte
strings. A checksum or local hash proves integrity only, never source authority.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import zlib

PARSER_REVISION = "rikui-observation-import-v1"
ARCHIVE_FORMAT = "rikui-observation-archive-v1"
MAX_WIRE = 131072
MAX_PAYLOAD = 65528
MAX_NODES = 16384
MAX_DEPTH = 16
MAX_TEXT = 2048
MAX_ID = 2147483647
MAX_QUESTS = 256
MAX_ARCHIVE = 2 * 1024 * 1024
NUMBER_RE = re.compile(rb"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:e[+-][0-9]+)?\Z")
TOKEN_RE = re.compile(rb"[A-Za-z0-9_.-]{1,128}\Z")
PACKET_RE = re.compile(rb"RIKQ1:([a-f0-9]{8}):([a-f0-9]+)\Z")
LIMITATIONS = [
    "Imported, untrusted character observation; never a world-fact source.",
    "Identity is declared by the packet and is not independently authenticated.",
    "Checksum and SHA256 detect byte changes; they do not establish authenticity.",
    "Only the Lua Transfer structural contract is validated; additional quest fields remain untrusted.",
    "A snapshot does not establish prerequisites, rewards, world coverage, walkability or historical turn-in.",
]


class ObservationError(ValueError):
    """Malformed, oversized or structurally invalid observation data."""


class LuaTable(dict):
    """A Lua plain table whose keys remain byte strings or positive integers."""


def is_integer(value, minimum, maximum):
    return (type(value) in (int, float) and math.isfinite(value)
            and minimum <= value <= maximum and value % 1 == 0)


def number_text(number):
    """Lua string.format('%.17g') for finite IEEE-754 doubles in this range."""
    return format(number, ".17g").encode("ascii")


class Decoder:
    def __init__(self, payload):
        self.payload = payload
        self.at = 0
        self.nodes = 0

    def length(self):
        colon = self.payload.find(b":", self.at, self.at + 7)
        if colon < 0:
            raise ObservationError("invalid observation length")
        raw = self.payload[self.at:colon]
        if not raw or not raw.isdigit() or (len(raw) > 1 and raw[0] == 48):
            raise ObservationError("invalid observation length")
        self.at = colon + 1
        return int(raw)

    def value(self, depth=0):
        self.nodes += 1
        if self.nodes > MAX_NODES or depth > MAX_DEPTH:
            raise ObservationError("observation node/depth limit")
        tag = self.payload[self.at:self.at + 1]
        self.at += 1
        if tag == b"b":
            flag = self.payload[self.at:self.at + 1]
            self.at += 1
            if flag not in (b"0", b"1"):
                raise ObservationError("invalid observation boolean")
            return flag == b"1"
        if tag not in (b"s", b"n", b"t"):
            raise ObservationError("invalid observation tag")
        size = self.length()
        if tag != b"t":
            end = self.at + size
            if size > MAX_TEXT or end > len(self.payload):
                raise ObservationError("truncated or oversized observation scalar")
            raw = self.payload[self.at:end]
            self.at = end
            if tag == b"s":
                return raw
            if not NUMBER_RE.fullmatch(raw):
                raise ObservationError("invalid observation number")
            number = float(raw)
            if (not math.isfinite(number) or not -MAX_ID <= number <= MAX_ID
                    or number_text(number) != raw):
                raise ObservationError("invalid observation number")
            return number
        if size > MAX_NODES:
            raise ObservationError("observation table limit")
        result = LuaTable()
        for _ in range(size):
            key = self.value(depth + 1)
            value = self.value(depth + 1)
            if type(key) is not bytes and not is_integer(key, 1, MAX_ID):
                raise ObservationError("invalid observation key")
            if key in result:
                raise ObservationError("duplicate observation key")
            result[key] = value
        return result


def validate_snapshot(snapshot):
    if type(snapshot) is not LuaTable:
        raise ObservationError("invalid observation snapshot")
    identity = snapshot.get(b"identity")
    if type(identity) is not LuaTable:
        raise ObservationError("invalid observation identity")
    for name in (b"product", b"build", b"locale"):
        value = identity.get(name)
        if type(value) is not bytes or not TOKEN_RE.fullmatch(value):
            raise ObservationError("invalid observation identity token")
    order = snapshot.get(b"order")
    quests = snapshot.get(b"quests")
    observed = snapshot.get(b"observedCount")
    reported = snapshot.get(b"reportedCount")
    if (type(order) is not LuaTable or len(order) > MAX_QUESTS
            or type(quests) is not LuaTable
            or not is_integer(observed, 0, MAX_QUESTS)
            or not is_integer(reported, 0, MAX_QUESTS)
            or observed != len(order)
            or snapshot.get(b"coverage") not in (b"log-complete", b"log-partial")):
        raise ObservationError("invalid observation snapshot")
    if (any(not is_integer(key, 1, MAX_QUESTS) for key in order)
            or any(index not in order for index in range(1, len(order) + 1))):
        raise ObservationError("invalid observation order")
    seen = set()
    for index in range(1, len(order) + 1):
        quest_id = order[index]
        if not is_integer(quest_id, 1, MAX_ID):
            raise ObservationError("invalid observation ID")
        quest = quests.get(quest_id)
        if (quest_id in seen or type(quest) is not LuaTable
                or type(quest.get(b"id")) is bool or quest.get(b"id") != quest_id):
            raise ObservationError("invalid observation quest")
        seen.add(quest_id)
    if set(quests) != seen:
        raise ObservationError("unordered observation quest")
    return snapshot


def decode_packet(wire):
    """Decode exact bytes with the same bounds and snapshot contract as Lua."""
    if type(wire) is not bytes or len(wire) > MAX_WIRE:
        raise ObservationError("invalid observation packet")
    match = PACKET_RE.fullmatch(wire)
    if not match or len(match[2]) % 2:
        raise ObservationError("invalid observation packet")
    payload = bytes.fromhex(match[2].decode("ascii"))
    if len(payload) > MAX_PAYLOAD:
        raise ObservationError("observation payload byte limit")
    actual_checksum = f"{zlib.adler32(payload):08x}".encode("ascii")
    if actual_checksum != match[1]:
        raise ObservationError("observation checksum mismatch")
    decoder = Decoder(payload)
    snapshot = decoder.value()
    if decoder.at != len(payload):
        raise ObservationError("trailing observation bytes")
    validate_snapshot(snapshot)
    snapshot[b"origin"] = b"imported-untrusted"
    return snapshot


def strip_file_newline(raw):
    if type(raw) is not bytes or len(raw) > MAX_WIRE + 2:
        raise ObservationError("observation input byte limit")
    if raw.endswith(b"\r\n"):
        return raw[:-2], "CRLF"
    if raw.endswith(b"\n"):
        return raw[:-1], "LF"
    return raw, None


def identity_of(snapshot):
    return {key: snapshot[b"identity"][key.encode("ascii")].decode("ascii")
            for key in ("product", "build", "locale")}


def check_identity(snapshot, expected):
    actual = identity_of(snapshot)
    for key, value in (expected or {}).items():
        if key not in actual or actual[key] != value:
            raise ObservationError("observation identity mismatch: " + key)
    return actual


def lossless(value):
    """JSON representation without conflating Lua byte strings or key types."""
    if type(value) is LuaTable:
        # Sorting is deterministic and matches Lua's numeric-then-string order.
        keys = sorted(value, key=lambda key: (0, key) if type(key) is not bytes else (1, key))
        return {"$table": [[lossless(key), lossless(value[key])] for key in keys]}
    if type(value) is bytes:
        try:
            return value.decode("utf-8")
        except UnicodeDecodeError:
            return {"$bytes": value.hex()}
    return value


def inspection(snapshot, wire):
    order = snapshot[b"order"]
    quests = []
    for index in range(1, len(order) + 1):
        quest_id = int(order[index])
        quest = snapshot[b"quests"][quest_id]
        item = {"id": quest_id}
        if type(quest.get(b"title")) is bytes:
            item["title"] = lossless(quest[b"title"])
        quests.append(item)
    return {
        "format": "rikui-observation-inspection-v1",
        "identity": identity_of(snapshot),
        "origin": "imported-untrusted",
        "observedCount": int(snapshot[b"observedCount"]),
        "reportedCount": int(snapshot[b"reportedCount"]),
        "coverage": snapshot[b"coverage"].decode("ascii"),
        "quests": quests,
        "packetSHA256": hashlib.sha256(wire).hexdigest(),
        "packetBytes": len(wire),
        "limitations": LIMITATIONS,
    }


def create_archive(raw, source_name, expected=None):
    wire, newline = strip_file_newline(raw)
    snapshot = decode_packet(wire)
    identity = check_identity(snapshot, expected)
    archive = {
        "format": ARCHIVE_FORMAT,
        "origin": "imported-untrusted",
        "identity": identity,
        "source": {
            "name": source_name,
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "terminalNewline": newline,
            "packetBytes": len(wire),
            "packetSHA256": hashlib.sha256(wire).hexdigest(),
            "adler32": wire[6:14].decode("ascii"),
            "parser": PARSER_REVISION,
            "parserSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        },
        "packet": wire.decode("ascii"),
        "snapshotEncoding": "lua-table-pairs-utf8-or-bytes-v1",
        "snapshot": lossless(snapshot),
        "inspection": inspection(snapshot, wire),
        "limitations": LIMITATIONS,
    }
    if type(source_name) is not str or len(source_name.encode("utf-8")) > 4096:
        raise ObservationError("invalid source name")
    encoded = (json.dumps(archive, ensure_ascii=True, allow_nan=False,
                          sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")
    if len(encoded) > MAX_ARCHIVE:
        raise ObservationError("observation archive byte limit")
    return archive, encoded


def read_packet_file(path):
    # Bounded reads also cover a file changing between stat and read.
    with path.open("rb") as stream:
        raw = stream.read(MAX_WIRE + 3)
    if len(raw) > MAX_WIRE + 2:
        raise ObservationError("observation input byte limit")
    return raw


def write_new_archive(path, encoded):
    """Exclusive creation: an existing file, directory or symlink is never replaced."""
    created = False
    try:
        with path.open("xb") as stream:
            created = True
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        if created:
            path.unlink(missing_ok=True)
        raise


def verify_archive_file(path, expected=None):
    """Reread durable bytes and check the retained packet and derived snapshot."""
    with path.open("rb") as stream:
        raw = stream.read(MAX_ARCHIVE + 1)
    if len(raw) > MAX_ARCHIVE:
        raise ObservationError("observation archive byte limit")

    def unique_fields(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ObservationError("duplicate archive field")
            result[key] = value
        return result

    try:
        archive = json.loads(raw, object_pairs_hook=unique_fields)
        if (type(archive) is not dict or archive.get("format") != ARCHIVE_FORMAT
                or archive.get("origin") != "imported-untrusted"
                or archive.get("snapshotEncoding") != "lua-table-pairs-utf8-or-bytes-v1"):
            raise ObservationError("invalid observation archive")
        wire = archive["packet"].encode("ascii")
        snapshot = decode_packet(wire)
        identity = check_identity(snapshot, expected)
        source = archive["source"]
        endings = {None: b"", "LF": b"\n", "CRLF": b"\r\n"}
        original = wire + endings[source["terminalNewline"]]
        if (source["parser"] != PARSER_REVISION
                or not re.fullmatch("[a-f0-9]{64}", source["parserSHA256"])
                or source["packetBytes"] != len(wire)
                or source["packetSHA256"] != hashlib.sha256(wire).hexdigest()
                or source["adler32"] != wire[6:14].decode("ascii")
                or source["bytes"] != len(original)
                or source["sha256"] != hashlib.sha256(original).hexdigest()
                or archive["identity"] != identity
                or json.dumps(archive["snapshot"], sort_keys=True, allow_nan=False)
                    != json.dumps(lossless(snapshot), sort_keys=True, allow_nan=False)
                or json.dumps(archive["inspection"], sort_keys=True, allow_nan=False)
                    != json.dumps(inspection(snapshot, wire), sort_keys=True, allow_nan=False)):
            raise ObservationError("archive content mismatch")
    except (KeyError, TypeError, AttributeError, UnicodeError, ValueError, RecursionError) as error:
        raise ObservationError("invalid observation archive: " + str(error)) from error
    return dict(inspection(snapshot, wire), archive=str(path), archiveBytes=len(raw),
                archiveSHA256=hashlib.sha256(raw).hexdigest(), archiveVerified=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("inspect", "import", "verify"):
        action = commands.add_parser(command)
        action.add_argument("source", type=Path, help="RIKQ1 packet, or JSON archive for verify")
        for field in ("product", "build", "locale"):
            action.add_argument("--expect-" + field)
        if command == "import":
            action.add_argument("--out", type=Path, required=True, help="New archive path; never overwritten")
    args = parser.parse_args(argv)
    expected = {field: getattr(args, "expect_" + field) for field in ("product", "build", "locale")
                if getattr(args, "expect_" + field) is not None}
    try:
        if args.command == "verify":
            result = verify_archive_file(args.source, expected)
        else:
            raw = read_packet_file(args.source)
            archive, encoded = create_archive(raw, str(args.source), expected)
            result = archive["inspection"]
            if args.command == "import":
                write_new_archive(args.out, encoded)
                result = dict(result, archive=str(args.out), archiveBytes=len(encoded),
                              archiveSHA256=hashlib.sha256(encoded).hexdigest())
    except (ObservationError, OSError, UnicodeError) as error:
        print("error: " + str(error), file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, ensure_ascii=True, allow_nan=False, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
