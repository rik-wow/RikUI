"""Differential offline proof against the project's real Lua Transfer implementation."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess
import tempfile

import quest_observations as q
from test_quest_observations import encoded, fixture, wire


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path, required=True)
    parser.add_argument("--transfer", type=Path, required=True)
    parser.add_argument("--luajit", default="luajit")
    parser.add_argument("--out", type=Path, required=True, help="New or empty proof directory")
    args = parser.parse_args()
    if args.out.exists() and any(args.out.iterdir()):
        parser.error("proof output must be new or empty")
    args.out.mkdir(exist_ok=True)
    probe = Path(__file__).with_name("lua_transfer_probe.lua")
    command = [args.luajit, str(probe), str(args.schema), str(args.transfer)]
    packet_file = args.out / "synthetic-lua-export.txt"
    lua_packet = subprocess.run(command + ["encode"], check=True, capture_output=True).stdout
    packet_file.write_bytes(lua_packet)
    packet, _ = q.strip_file_newline(lua_packet)
    snapshot = q.decode_packet(packet)
    assert snapshot[b"fixture"] is True
    assert len(snapshot[b"numbers"]) == 1028
    assert snapshot[b"mixed"][1] == b"numeric key"
    assert snapshot[b"mixed"][b"1"] == b"string key"
    assert snapshot[b"mixed"][b"\xff"] == b"\xfe\0\xff"
    assert snapshot[b"quests"][98319][b"objectivesComplete"] is False
    archive, archive_bytes = q.create_archive(lua_packet, packet_file.name)
    q.write_new_archive(args.out / "synthetic-observation.json", archive_bytes)
    candidates = [packet, wire(encoded(fixture()))]
    malformed = [b"x", b"b2", b"s01:x", b"s1000000:", b"t16385:", b"s2:x", b"t2:s1:ab0s1:ab1",
                 b"t1:b1b0", b"t1:n1:0b0", b"t1:n3:1.5b0", b"t1:t0:b0", b"n3:nan", b"n3:1.0"]
    candidates.extend(wire(payload) for payload in malformed)
    base = encoded(fixture())
    candidates.extend([wire(base + b"b0"), wire(base) + b"0", b"RIKQ1:00000000:" + base.hex().encode()])
    for field in (b"identity", b"order", b"quests", b"observedCount", b"reportedCount", b"coverage"):
        value = fixture()
        del value[field]
        candidates.append(wire(encoded(value)))
    for invalid in (False, 257, -1, 1.5, b"1"):
        value = fixture()
        value[b"observedCount"] = invalid
        candidates.append(wire(encoded(value)))
    for order in ({2: 98319}, {b"1": 98319}, {1: 98319, 2: 98319}, {1: 0}):
        value = fixture()
        value[b"order"] = order
        value[b"observedCount"] = len(order)
        candidates.append(wire(encoded(value)))
    for invalid in (b"", b"en US", b"x" * 129, b"\xff", b"a_b.c-1", b"enUS"):
        value = fixture()
        value[b"identity"][b"locale"] = invalid
        candidates.append(wire(encoded(value)))
    for raw in (b"nan", b"NaN", b"inf", b"-inf", b"1e999", b"1.0", b"01", b"+1", b"0x10",
                b"1e+00", b"1E-10", b" 1", b"2147483648", b"-2147483648", b"-0", b"0",
                b"4.9406564584124654e-324", b"2147483647", b"-2147483647"):
        # Inject a scalar into an otherwise valid snapshot so acceptance is meaningful.
        value = fixture()
        value[b"numeric"] = b"NUMBER_PLACEHOLDER"
        payload = encoded(value).replace(b"s18:NUMBER_PLACEHOLDER", b"n" + str(len(raw)).encode() + b":" + raw)
        candidates.append(wire(payload))
    for depth in (15, 16):
        nested = b"leaf"
        for _ in range(depth):
            nested = {b"k": nested}
        value = fixture()
        value[b"nested"] = nested
        candidates.append(wire(encoded(value)))
    rng = random.Random(8675309)
    for index in range(400):
        at = rng.randrange(len(base))
        if index % 3 == 0:
            payload = base[:at] + bytes([rng.randrange(256)]) + base[at + 1:]
        elif index % 3 == 1:
            payload = base[:at] + base[at + 1:]
        else:
            payload = base[:at] + bytes([rng.randrange(256)]) + base[at:]
        candidates.append(wire(payload))
    with tempfile.TemporaryDirectory() as temporary:
        candidate_file = Path(temporary) / "packets.txt"
        candidate_file.write_bytes(b"\n".join(candidates) + b"\n")
        result = subprocess.run(command + ["decode", str(candidate_file)], check=True, capture_output=True)
    lua = result.stdout.decode("ascii").splitlines()
    assert len(lua) == len(candidates)
    python = []
    for candidate in candidates:
        try:
            q.decode_packet(candidate)
            python.append("1")
        except q.ObservationError:
            python.append("0")
    mismatches = [index for index, (left, right) in enumerate(zip(lua, python)) if left != right]
    if mismatches:
        raise AssertionError("Lua/Python acceptance differs at cases " + str(mismatches))
    receipt = {
        "format": "rikui-observation-decoder-parity-v1",
        "syntheticOnly": True,
        "nativeClientUsed": False,
        "cases": len(candidates),
        "accepted": python.count("1"),
        "rejected": python.count("0"),
        "luaGeneratedNumberSamples": 1028,
        "mismatches": mismatches,
        "sources": {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in (args.schema, args.transfer, probe, Path(q.__file__), Path(__file__))},
        "packetSHA256": hashlib.sha256(packet).hexdigest(),
        "archiveSHA256": hashlib.sha256(archive_bytes).hexdigest(),
        "limits": q.LIMITATIONS,
    }
    (args.out / "parity-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(candidates), "accepted": python.count("1"), "rejected": python.count("0"), "mismatches": mismatches}))


if __name__ == "__main__":
    main()
