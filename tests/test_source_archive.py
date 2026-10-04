"""Publisher source acquisition boundaries, preservation and repeat verification."""
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import source_archive as source

REV="a"*40


def archive(rows):
    stream=io.BytesIO()
    with zipfile.ZipFile(stream,"w") as out:
        for name,body in rows:out.writestr("publisher-"+REV+"/"+name,body)
    raw=stream.getvalue()
    # Windows ZipInfo normalizes backslashes when authoring; inject an actual
    # unsafe archive spelling into both local and central directory headers.
    for name,_ in rows:
        if "\\" in name:
            raw=raw.replace(name.replace("\\","/").encode(),name.encode())
    return raw


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/"source"

    def acquire(self,rows,repo="Questie/QuestieDB"):
        with patch.object(source.urllib.request,"urlopen",return_value=io.BytesIO(archive(rows))):
            return source.acquire(repo,REV,self.root)

    def test_exact_snapshot_and_repeat_byte_verification(self):
        rows=[("Database.lua",b"return {}"),("LICENSE",b"publisher notice")]
        result=self.acquire(rows)
        self.assertEqual(result["revision"],REV)
        self.assertEqual(len(result["files"]),2)
        with patch.object(source.urllib.request,"urlopen",side_effect=AssertionError("No download on verified reuse")):
            self.assertEqual(source.acquire("Questie/QuestieDB",REV,self.root),result)

    def test_changed_snapshot_fails_preserves_all_bytes(self):
        self.acquire([("Database.lua",b"original")])
        (self.root/"Database.lua").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError,"changed"):
            source.acquire("Questie/QuestieDB",REV,self.root)
        self.assertEqual((self.root/"Database.lua").read_bytes(),b"changed")

    def test_snapshot_revision_mismatch_fails(self):
        self.acquire([("Database.lua",b"original")])
        with self.assertRaises(ValueError):source.verify(self.root,"b"*40)

    def test_traversal_reserved_case_duplicate_and_slash_rejected(self):
        for names in (["../escape"],["NUL.txt"],["name."],["a\\b"],["A.lua","a.lua"]):
            with self.subTest(names=names),self.assertRaises(ValueError):
                self.acquire([(name,b"x") for name in names])
            self.assertFalse(self.root.exists())

    def test_file_and_archive_bounds_are_enforced(self):
        with patch.object(source,"MAX_EXPANDED",3),self.assertRaises(ValueError):
            self.acquire([("Database.lua",b"1234")])
        with patch.object(source,"MAX_ARCHIVE",3),self.assertRaises(ValueError):
            self.acquire([("Database.lua",b"x")])

    def test_events_obtain_only_compatible_holiday_sources_and_notice(self):
        result=self.acquire([("Database/Corrections/Holidays/quests/Holiday.lua",b"source"),
                             ("Database/quests.lua",b"unrequested data"),
                             ("LICENSE",b"notice")],repo="Questie/Questie")
        self.assertEqual([row["path"] for row in result["files"]],
                         ["Database/Corrections/Holidays/quests/Holiday.lua","LICENSE"])

    def test_incomplete_previous_snapshot_is_never_accepted(self):
        self.root.mkdir()
        (self.root/"keep").write_bytes(b"partial retained")
        with self.assertRaises(OSError):source.acquire("Questie/QuestieDB",REV,self.root)
        self.assertEqual((self.root/"keep").read_bytes(),b"partial retained")

    def test_unsupported_publisher_and_nonrevision_are_refused(self):
        for repo,revision in (("other/provider",REV),("Questie/QuestieDB","master")):
            with self.assertRaises(ValueError):source.acquire(repo,revision,self.root)


if __name__=="__main__":unittest.main()
