"""Adversarial protocol/archival tests; fixtures are synthetic, never game facts."""

import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zlib

import quest_observations as q


def encoded(value):
    """Fixture encoder; the production tool intentionally provides no exporter."""
    if type(value) is bool:
        return b"b1" if value else b"b0"
    if type(value) is bytes:
        return b"s" + str(len(value)).encode() + b":" + value
    if type(value) in (int, float):
        raw = format(value, ".17g").encode()
        return b"n" + str(len(raw)).encode() + b":" + raw
    parts = [b"t" + str(len(value)).encode() + b":"]
    for key, child in value.items():
        parts.extend((encoded(key), encoded(child)))
    return b"".join(parts)


def wire(payload):
    return b"RIKQ1:" + f"{zlib.adler32(payload):08x}".encode() + b":" + payload.hex().encode()


def fixture():
    return {
        b"identity": {b"product": b"forever", b"build": b"1.60.1.69913", b"locale": b"enUS"},
        b"order": {1: 98319},
        b"quests": {98319: {b"id": 98319, b"title": b"Synthetic fixture", b"objectivesComplete": False}},
        b"observedCount": 1,
        b"reportedCount": 1,
        b"coverage": b"log-complete",
        b"origin": b"trusted-looking-label",
        b"fixture": True,
    }


def from_lossless(value):
    if isinstance(value, dict):
        if "$table" in value:
            return q.LuaTable((from_lossless(key), from_lossless(child)) for key, child in value["$table"])
        return bytes.fromhex(value["$bytes"])
    if isinstance(value, str):
        return value.encode("utf-8")
    return value


class ObservationTests(unittest.TestCase):
    def parse(self, value=None):
        return q.decode_packet(wire(encoded(value if value is not None else fixture())))

    def test_lua_snapshot_contract_and_forced_untrusted_origin(self):
        result = self.parse()
        self.assertEqual(result[b"origin"], b"imported-untrusted")
        self.assertEqual(result[b"order"][1], 98319)
        self.assertIs(result[b"quests"][98319][b"objectivesComplete"], False)
        self.assertEqual(q.identity_of(result), {"product": "forever", "build": "1.60.1.69913", "locale": "enUS"})

    def test_empty_and_partial_snapshots(self):
        value = fixture()
        value.update({b"order": {}, b"quests": {}, b"observedCount": 0, b"reportedCount": 5, b"coverage": b"log-partial"})
        self.assertEqual(self.parse(value)[b"reportedCount"], 5)

    def test_non_target_identity_is_preserved_never_relabelled(self):
        value = fixture()
        value[b"identity"] = {b"product": b"era", b"build": b"1.15.8.99999", b"locale": b"frFR"}
        result = self.parse(value)
        self.assertEqual(q.identity_of(result)["product"], "era")
        with self.assertRaisesRegex(q.ObservationError, "identity mismatch"):
            q.check_identity(result, {"product": "forever"})

    def test_invalid_identity_tokens(self):
        for invalid in (b"", b"x" * 129, b"en US", b"en/US", b"\xff", 123, False):
            with self.subTest(invalid=invalid):
                value = fixture()
                value[b"identity"][b"locale"] = invalid
                with self.assertRaises(q.ObservationError):
                    self.parse(value)

    def test_snapshot_required_fields(self):
        for key in (b"identity", b"order", b"quests", b"observedCount", b"reportedCount", b"coverage"):
            with self.subTest(key=key):
                value = fixture()
                del value[key]
                with self.assertRaises(q.ObservationError):
                    self.parse(value)

    def test_counts_are_bounded_integers_not_booleans(self):
        for field in (b"observedCount", b"reportedCount"):
            for invalid in (-1, 257, 1.5, True, b"1"):
                with self.subTest(field=field, invalid=invalid):
                    value = fixture()
                    value[field] = invalid
                    with self.assertRaises(q.ObservationError):
                        self.parse(value)

    def test_holey_string_indexed_and_duplicate_order(self):
        for order in ({2: 98319}, {b"1": 98319}, {1: 98319, 2: 98319}, {1: 0}):
            value = fixture()
            value[b"order"] = order
            value[b"observedCount"] = len(order)
            with self.assertRaises(q.ObservationError):
                self.parse(value)

    def test_quest_identity_and_order_correspondence(self):
        for quests in ({}, {98319: {b"id": 1}}, {98319: {b"id": True}},
                       {b"98319": {b"id": 98319}}, {98319: False},
                       {98319: {b"id": 98319}, 1: {b"id": 1}}):
            value = fixture()
            value[b"quests"] = quests
            with self.assertRaises(q.ObservationError):
                self.parse(value)

    def test_observed_count_matches_order(self):
        value = fixture()
        value[b"observedCount"] = 2
        with self.assertRaises(q.ObservationError):
            self.parse(value)

    def test_coverage_values(self):
        for invalid in (b"world-complete", b"", 1, False):
            value = fixture()
            value[b"coverage"] = invalid
            with self.assertRaises(q.ObservationError):
                self.parse(value)

    def test_top_level_must_be_table(self):
        for value in (True, 1, b"payload"):
            with self.assertRaises(q.ObservationError):
                self.parse(value)

    def test_packet_framing_and_case(self):
        valid = wire(encoded(fixture()))
        for bad in (valid.decode(), b"", valid.upper(), b" " + valid, valid + b"\n", valid + b"0",
                    valid.replace(b"RIKQ1", b"RIKQ2"), b"RIKQ1:12345678:", b"RIKQ1:12345678:0g"):
            with self.subTest(bad=str(bad)[:40]):
                with self.assertRaises(q.ObservationError):
                    q.decode_packet(bad)

    def test_checksum_corruption(self):
        valid = wire(encoded(fixture()))
        with self.assertRaisesRegex(q.ObservationError, "checksum"):
            q.decode_packet(valid[:6] + b"00000000" + valid[14:])

    def test_wire_size_limit(self):
        with self.assertRaises(q.ObservationError):
            q.decode_packet(b"x" * (q.MAX_WIRE + 1))
        with self.assertRaises(q.ObservationError):
            q.strip_file_newline(b"x" * (q.MAX_WIRE + 3))

    def test_maximum_valid_wire_and_next_byte_rejected(self):
        value = fixture()
        value[b"filler"] = {index: b"x" * q.MAX_TEXT for index in range(1, 32)}
        payload = None
        for size in range(q.MAX_TEXT + 1):
            value[b"padding"] = b"p" * size
            candidate = encoded(value)
            if len(candidate) == q.MAX_PAYLOAD:
                payload = candidate
                break
        self.assertIsNotNone(payload)
        packet = wire(payload)
        self.assertEqual(len(packet), q.MAX_WIRE - 1)
        self.assertEqual(q.decode_packet(packet)[b"origin"], b"imported-untrusted")
        value[b"padding"] += b"p"
        with self.assertRaises(q.ObservationError):
            self.parse(value)

    def test_node_limit_in_an_otherwise_valid_snapshot(self):
        value = fixture()
        value[b"many"] = {index.to_bytes(2, "big"): False for index in range(8191)}
        packet = wire(encoded(value))
        self.assertLess(len(packet), q.MAX_WIRE)
        with self.assertRaisesRegex(q.ObservationError, "node"):
            q.decode_packet(packet)

    def test_trailing_decoded_payload_rejected(self):
        with self.assertRaisesRegex(q.ObservationError, "trailing"):
            q.decode_packet(wire(encoded(fixture()) + b"b0"))

    def test_invalid_tags_booleans_lengths_truncation(self):
        for payload in (b"x", b"b2", b"b", b"s:", b"s01:x", b"s+1:x", b"s-1:x", b"s0000000:",
                        b"s1000000:", b"s1", b"s2:x", b"t1:s1:k", b"t16385:", b"n0:"):
            with self.subTest(payload=payload):
                with self.assertRaises(q.ObservationError):
                    q.decode_packet(wire(payload))

    def test_noncanonical_nonfinite_and_out_of_range_numbers(self):
        for raw in (b"nan", b"NaN", b"inf", b"-inf", b"1e999", b"1.0", b"01", b"+1", b"0x10",
                    b"1e+00", b"1E-10", b" 1", b"2147483648", b"-2147483648"):
            payload = b"n" + str(len(raw)).encode() + b":" + raw
            with self.subTest(raw=raw):
                with self.assertRaises(q.ObservationError):
                    q.Decoder(payload).value()

    def test_valid_number_boundaries_and_negative_zero(self):
        for raw in (b"2147483647", b"-2147483647", b"0", b"-0", b"0.5", b"4.9406564584124654e-324"):
            payload = b"n" + str(len(raw)).encode() + b":" + raw
            self.assertEqual(q.number_text(q.Decoder(payload).value()), raw)

    def test_duplicate_and_invalid_table_keys(self):
        for payload in (b"t2:s1:ab0s1:ab1", b"t2:n1:1b0n1:1b1", b"t1:b1b0", b"t1:n1:0b0",
                        b"t1:n3:1.5b0", b"t1:t0:b0"):
            with self.subTest(payload=payload):
                with self.assertRaises(q.ObservationError):
                    q.decode_packet(wire(payload))

    def test_scalar_text_limit(self):
        value = fixture()
        value[b"extra"] = b"x" * q.MAX_TEXT
        self.assertEqual(len(self.parse(value)[b"extra"]), q.MAX_TEXT)
        value[b"extra"] += b"x"
        with self.assertRaises(q.ObservationError):
            self.parse(value)

    def test_depth_boundary(self):
        value = b"leaf"
        for _ in range(15):
            value = {b"k": value}
        snapshot = fixture()
        snapshot[b"nested"] = value
        self.parse(snapshot)
        snapshot[b"nested"] = {b"oneMore": value}
        with self.assertRaisesRegex(q.ObservationError, "depth"):
            self.parse(snapshot)

    def test_node_budget(self):
        value = {index.to_bytes(2, "big"): False for index in range(8191)}
        decoder = q.Decoder(encoded(value))
        decoder.value()
        self.assertEqual(decoder.nodes, 16383)
        value[b"oneMore"] = False
        with self.assertRaisesRegex(q.ObservationError, "node"):
            q.Decoder(encoded(value)).value()

    def test_256_quests_allowed_257_rejected(self):
        value = fixture()
        value[b"order"] = {n: n for n in range(1, 257)}
        value[b"quests"] = {n: {b"id": n} for n in range(1, 257)}
        value[b"observedCount"] = value[b"reportedCount"] = 256
        self.assertEqual(len(self.parse(value)[b"quests"]), 256)
        value[b"order"][257] = 257
        value[b"quests"][257] = {b"id": 257}
        value[b"observedCount"] = 257
        with self.assertRaises(q.ObservationError):
            self.parse(value)

    def test_lossless_bytes_unicode_markup_nul_and_mixed_key_types(self):
        value = fixture()
        value[b"extra"] = {1: b"numeric key", b"1": b"string key", b"\xff": b"\xfe\x00\xff",
                           b"utf8": "é |Hlink|h : \x00\n\t".encode(), b"empty": {}}
        packet = wire(encoded(value))
        archive, raw = q.create_archive(packet, "fixture.txt")
        saved = json.loads(raw)
        result = from_lossless(saved["snapshot"])
        self.assertEqual(result, q.decode_packet(packet))
        self.assertEqual(result[b"extra"][1], b"numeric key")
        self.assertEqual(result[b"extra"][b"1"], b"string key")
        self.assertEqual(saved["packet"].encode(), packet)
        self.assertNotIn("assertions", saved)
        self.assertEqual(archive["origin"], "imported-untrusted")

    def test_single_terminal_newline_policy_and_hashes(self):
        packet = wire(encoded(fixture()))
        for suffix, label in ((b"", None), (b"\n", "LF"), (b"\r\n", "CRLF")):
            archive, _ = q.create_archive(packet + suffix, "fixture.txt")
            self.assertEqual(archive["source"]["terminalNewline"], label)
            self.assertEqual(archive["source"]["sha256"], hashlib.sha256(packet + suffix).hexdigest())
            self.assertEqual(archive["source"]["packetSHA256"], hashlib.sha256(packet).hexdigest())
        for suffix in (b"\r", b"\n\n", b" ", b"\r\n\r\n"):
            with self.assertRaises(q.ObservationError):
                q.create_archive(packet + suffix, "fixture.txt")

    def test_reproducible_archive_and_parser_hash(self):
        packet = wire(encoded(fixture()))
        archive, raw = q.create_archive(packet, "fixture.txt")
        self.assertEqual(raw, q.create_archive(packet, "fixture.txt")[1])
        self.assertEqual(archive["source"]["parserSHA256"], hashlib.sha256(Path(q.__file__).read_bytes()).hexdigest())

    def test_source_name_limit(self):
        with self.assertRaises(q.ObservationError):
            q.create_archive(wire(encoded(fixture())), "x" * 4097)

    def test_exclusive_archive_write_preserves_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "archive.json"
            path.write_bytes(b"existing work")
            with self.assertRaises(FileExistsError):
                q.write_new_archive(path, b"new")
            self.assertEqual(path.read_bytes(), b"existing work")

    def test_directory_and_symlink_outputs_never_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            with self.assertRaises(OSError):
                q.write_new_archive(parent, b"new")
            target = parent / "target.json"
            target.write_bytes(b"existing work")
            link = parent / "link.json"
            try:
                link.symlink_to(target)
            except OSError:
                return  # Platforms without symlink privilege still test directory refusal.
            with self.assertRaises(FileExistsError):
                q.write_new_archive(link, b"new")
            self.assertEqual(target.read_bytes(), b"existing work")
            self.assertTrue(link.is_symlink())

    def test_failed_write_removes_only_new_partial_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "archive.json"
            with patch.object(q.os, "fsync", side_effect=OSError("simulated disk failure")):
                with self.assertRaises(OSError):
                    q.write_new_archive(path, b"partial")
            self.assertFalse(path.exists())


    def test_durable_archive_reread_and_identity(self):
        packet = wire(encoded(fixture()))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "archive.json"
            for suffix in (b"", b"\n", b"\r\n"):
                with self.subTest(suffix=suffix):
                    _, raw = q.create_archive(packet + suffix, "fixture.txt")
                    path.write_bytes(raw)
                    result = q.verify_archive_file(path, {"product": "forever"})
                    self.assertTrue(result["archiveVerified"])
                    self.assertEqual(result["packetSHA256"], hashlib.sha256(packet).hexdigest())
                    self.assertEqual(result["archiveSHA256"], hashlib.sha256(raw).hexdigest())
                    self.assertEqual(path.read_bytes(), raw)
            with self.assertRaisesRegex(q.ObservationError, "identity mismatch"):
                q.verify_archive_file(path, {"build": "1.60.1.unknown"})

    def test_archive_rejects_changed_snapshot_packet_and_metadata(self):
        packet = wire(encoded(fixture()))
        original, raw = q.create_archive(packet, "fixture.txt")
        mutations = [
            ("origin", "live"), ("format", "unknown"),
            ("packet", packet.decode()[:-1] + "0"), ("snapshot", {}),
            ("identity", {"product": "era"}), ("inspection", {}),
            ("snapshotEncoding", "ordinary-json"),
        ]
        source_mutations = [
            ("sha256", "0" * 64), ("packetSHA256", "0" * 64),
            ("adler32", "00000000"), ("bytes", 1), ("packetBytes", 1),
            ("terminalNewline", "space"), ("parser", "unknown"),
            ("parserSHA256", "unrecorded"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "archive.json"
            for field, value in mutations + source_mutations:
                with self.subTest(field=field):
                    archive = json.loads(raw)
                    target = archive["source"] if (field, value) in source_mutations else archive
                    target[field] = value
                    path.write_text(json.dumps(archive), encoding="utf-8")
                    with self.assertRaises(q.ObservationError):
                        q.verify_archive_file(path)
            # Python equality conflates bool and number; archive verification must not.
            changed = json.loads(raw)
            changed["inspection"]["observedCount"] = True
            path.write_text(json.dumps(changed), encoding="utf-8")
            with self.assertRaises(q.ObservationError):
                q.verify_archive_file(path)
            # Historical parser hashes remain provenance, not a demand to rerun that executable.
            original["source"]["parserSHA256"] = "0" * 64
            path.write_text(json.dumps(original), encoding="utf-8")
            self.assertTrue(q.verify_archive_file(path)["archiveVerified"])

    def test_archive_rejects_duplicate_fields_malformed_and_oversized_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "archive.json"
            malformed = (b'{"format":1,"format":2}', b'{}', b'[]', b'{"x":',
                         b'\xff', b" " * (q.MAX_ARCHIVE + 1),
                         b"[" * 1100 + b"0" + b"]" * 1100)
            for raw in malformed:
                with self.subTest(size=len(raw)):
                    path.write_bytes(raw)
                    with self.assertRaises(q.ObservationError):
                        q.verify_archive_file(path)

    def test_cli_verify_is_read_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "archive.json"
            _, raw = q.create_archive(wire(encoded(fixture())), "fixture.txt")
            path.write_bytes(raw)
            before = path.stat().st_mtime_ns
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(q.main(["verify", str(path), "--expect-locale", "enUS"]), 0)
            self.assertTrue(json.loads(output.getvalue())["archiveVerified"])
            self.assertEqual(path.read_bytes(), raw)
            self.assertEqual(path.stat().st_mtime_ns, before)
            path.write_bytes(b"{}")
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(q.main(["verify", str(path)]), 2)

    def test_cli_inspect_import_and_failure_status(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            packet = parent / "packet.txt"
            packet.write_bytes(wire(encoded(fixture())) + b"\n")
            out = parent / "archive.json"
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                status = q.main(["inspect", str(packet), "--expect-product", "forever"])
            self.assertEqual(status, 0)
            self.assertEqual(json.loads(stdout.getvalue())["origin"], "imported-untrusted")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(q.main(["import", str(packet), "--out", str(out)]), 0)
            before = out.read_bytes()
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(q.main(["import", str(packet), "--out", str(out)]), 2)
                self.assertEqual(q.main(["inspect", str(packet), "--expect-locale", "deDE"]), 2)
            self.assertEqual(out.read_bytes(), before)

    def test_failed_validation_never_creates_output(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bad.txt"
            out = Path(directory) / "archive.json"
            source.write_bytes(b"bad packet")
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(q.main(["import", str(source), "--out", str(out)]), 2)
            self.assertFalse(out.exists())

    def test_bounded_file_read(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "big.txt"
            path.write_bytes(b"x" * (q.MAX_WIRE + 3))
            with self.assertRaises(q.ObservationError):
                q.read_packet_file(path)


if __name__ == "__main__":
    unittest.main()
