"""Acquisition rejects unsupported semantics and pins bytes before parsing."""
import hashlib
import importlib.util
import struct
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("quest_acquire", Path(__file__).parents[1] / "tools" / "quest_acquire.py")
acquire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acquire)


class AcquisitionTests(unittest.TestCase):
    def index(self, raw):
        return acquire.quest_index(raw, hashlib.sha256(raw).hexdigest(), "1.60.1.69913", "fixture://original")

    def test_index_only_not_world_facts(self):
        raw = b"ID,UniqueBitFlag,UiQuestDetailsThemeID\n98319,71516,0\n218,9,0\n"
        result = self.index(raw)
        self.assertEqual([row["ID"] for row in result["index"]], [218, 98319])
        self.assertEqual(result["source"]["assertions"], 2)
        self.assertEqual(result["coverage"]["worldQuestDenominator"], "unknown")
        self.assertEqual({row["field"] for row in result["assertions"]}, {"clientRecord"})

    def test_tamper_and_schema_rejection(self):
        with self.assertRaises(ValueError):
            acquire.quest_index(b"x", "0" * 64, "1.60.1.69913", "fixture")
        for raw in [b"ID,XP\n1,100\n", b"ID,UniqueBitFlag,UiQuestDetailsThemeID\n1,2,0\n1,2,0\n"]:
            with self.assertRaises(ValueError):
                self.index(raw)

    def test_realistic_index_larger_than_prototype_limit(self):
        raw = ("ID,UniqueBitFlag,UiQuestDetailsThemeID\n" +
               "".join(f"{i},{i},0\n" for i in range(1, 6601))).encode()
        self.assertEqual(self.index(raw)["coverage"]["clientRecords"], 6600)

    def test_wdb_framing_does_not_decode_payload(self):
        raw = struct.pack("<4sI4sIII", b"TSQW", 69913, b"SUne", 12296, 12, 0)
        raw += struct.pack("<II", 98319, 4) + b"test" + bytes(8)
        result = acquire.cache_inventory(raw, hashlib.sha256(raw).hexdigest())
        self.assertFalse(result["semanticSupport"])
        self.assertEqual(result["records"][0]["questID"], 98319)
        for bad in [raw[:-1], raw + b"x", raw[:24] + struct.pack("<II", 1, 999)]:
            with self.assertRaises(ValueError):
                acquire.cache_inventory(bad, hashlib.sha256(bad).hexdigest())


if __name__ == "__main__":
    unittest.main()
