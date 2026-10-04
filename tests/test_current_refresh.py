"""Changed-input/no-op byte verification and release discovery fixtures."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from test_forever_inputs import Publishers, BUILD, RAW
import forever_inputs as current
import current_refresh as refresh


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.client=self.root/"release"
        self.client.mkdir()
        self.exe=self.client/"WowRelease.exe"
        self.exe.write_bytes(b"fixture")
        (self.root/".build.info").write_bytes(RAW)
        self.publisher=Publishers()
        self.resolution=current.discover(self.exe,self.publisher.fetch,lambda _:BUILD)
        self.tools={"compiler":"a"*64}
        self.previous=dict(format="rikui-local-assembly-v1",resolution=self.resolution,tools=self.tools)

    def test_unchanged_must_verify_bytes(self):
        verify=Mock()
        products,changed=refresh.scopes(self.previous,self.resolution,self.tools,verify)
        self.assertEqual((products,changed),([],[]))
        verify.assert_called_once_with(self.previous)

    def test_changed_provider_recompiles_real_corpus_and_preserves_physical_bytes(self):
        import json
        from test_quest_corpus import fixture, corpus
        source=self.root/"provider.json"
        data=fixture();source.write_text(json.dumps(data))
        membership=self.root/"QuestV2.csv";membership.write_bytes(b"ID,UniqueBitFlag,UiQuestDetailsThemeID\n1,1,0\n99001,2,0\n")
        kwargs=dict(client_index=membership,client_build=BUILD,client_index_sha=corpus.sha(membership.read_bytes()))
        first=corpus.build(source,self.root/"corpus-a",**kwargs)
        physical=self.root/"mesh.fixture";physical.write_bytes(b"verified physical mesh")
        rows=[dict(path=physical.name,bytes=physical.stat().st_size,sha256=current.sha(physical.read_bytes()))]
        def verify(_):
            corpus.verify(self.root/"corpus-a")
            refresh.verify_files(self.root,rows)
        revised=copy.deepcopy(self.resolution)
        revised["inputs"]["sources"]["provider"]["revision"]="f"*40
        revised["fingerprint"]=current.sha(current.canonical(revised["inputs"]))
        products,_=refresh.scopes(self.previous,revised,self.tools,verify)
        self.assertEqual(products,["corpus","roads"])
        data["provider"]["revision"]="f"*40
        data["base"]["quests"]["1"]["name"]="Updated publisher objectives"
        data["base"]["quests"]["1"]["objectives"]["1"]["1"]["3"]=7
        source.write_text(json.dumps(data))
        second=corpus.build(source,self.root/"corpus-b",**kwargs)
        self.assertNotEqual(first["corpusRevision"],second["corpusRevision"])
        semantics=json.loads((self.root/"corpus-b/audit/semantic-quests.json").read_bytes())
        self.assertEqual(semantics["1"]["base"]["title"],"Updated publisher objectives")
        self.assertEqual(semantics["99001"]["base"]["objectives"],[])
        updated=dict(self.previous,resolution=revised)
        def verify_updated(_):
            corpus.verify(self.root/"corpus-b")
            refresh.verify_files(self.root,rows)
        before=(self.root/"corpus-b/manifest.json").stat().st_mtime_ns
        self.assertEqual(refresh.scopes(updated,revised,self.tools,verify_updated),([],[]))
        self.assertEqual((self.root/"corpus-b/manifest.json").stat().st_mtime_ns,before)
        self.assertEqual(physical.read_bytes(),b"verified physical mesh")

    def test_provider_change_rebuilds_semantics_and_patches(self):
        result=copy.deepcopy(self.resolution)
        result["inputs"]["sources"]["provider"]["revision"]="f"*40
        result["fingerprint"]=current.sha(current.canonical(result["inputs"]))
        products,changed=refresh.scopes(self.previous,result,self.tools,Mock())
        self.assertEqual(products,["corpus","roads"])
        self.assertEqual(changed,["provider"])

    def test_client_or_schema_change_rebuilds_all(self):
        for key in ("ui","schemas"):
            result=copy.deepcopy(self.resolution)
            result["inputs"]["sources"][key]["revision"]="f"*40
            result["fingerprint"]=current.sha(current.canonical(result["inputs"]))
            self.assertEqual(refresh.scopes(self.previous,result,self.tools,Mock())[0],
                             ["acquisition","corpus","bakes","roads"])

    def test_unchanged_metadata_never_hides_tampering(self):
        products,changed=refresh.scopes(self.previous,self.resolution,self.tools,
                                       Mock(side_effect=ValueError("changed bytes")))
        self.assertIn("acquisition",products)
        self.assertIn("unverified-bytes",changed)

    def test_tool_change_invalidates_outputs(self):
        self.assertIn("bakes",refresh.scopes(self.previous,self.resolution,{},Mock())[0])

    def test_known_tool_changes_rebuild_only_affected_products(self):
        for name,expected in (
            ("tools/quest_corpus.py",["corpus","roads"]),
            ("tools/terrain/road_textures.py",["roads"]),
            ("tools/local_assembly.py",["bundle"]),
            ("tools/terrain/node_modules/.package-lock.json",["bundle"]),
            ("tools/verify_current_m2.py",["acquisition","corpus","bakes","roads"])):
            with self.subTest(name=name):
                previous=dict(self.previous,tools={name:"a"*64})
                verify=Mock()
                scopes,_=refresh.scopes(previous,self.resolution,{name:"b"*64},verify)
                self.assertEqual(scopes,expected)
                verify.assert_called_once()

    def test_new_verifier_still_rebuilds_when_old_bytes_fail(self):
        previous=dict(self.previous,tools={"tools/local_assembly.py":"a"*64})
        scopes,changed=refresh.scopes(previous,self.resolution,{"tools/local_assembly.py":"b"*64},
                                     Mock(side_effect=ValueError("Required current inputs absent")))
        self.assertEqual(scopes,["acquisition","corpus","bakes","roads","bundle"])
        self.assertIn("unverified-bytes",changed)

    def test_realistic_semantic_audit_bound_is_streamed(self):
        import hashlib
        path=self.root/"semantic-audit.json"
        with path.open("wb") as stream:
            stream.truncate(129*1024*1024)
        with path.open("rb") as stream:expected=hashlib.file_digest(stream,"sha256").hexdigest()
        self.assertEqual(refresh.file_hash(path),expected)
        with path.open("wb") as stream:stream.truncate(513*1024*1024)
        with self.assertRaisesRegex(ValueError,"byte bound"):refresh.file_hash(path)

    def test_inventory_tamper_traversal_and_duplicate(self):
        path=self.root/"data";path.write_bytes(b"current")
        rows=[dict(path="data",bytes=7,sha256=current.sha(b"current"))]
        self.assertTrue(refresh.verify_files(self.root,rows))
        for invalid in (rows+rows,[dict(rows[0],path="../outside")]):
            with self.assertRaises(ValueError):refresh.verify_files(self.root,invalid)
        path.write_bytes(b"changed")
        with self.assertRaises(ValueError):refresh.verify_files(self.root,rows)

    def test_release_directory_and_executable_discovered(self):
        result=refresh.find_client([self.root],self.publisher.fetch,lambda _:BUILD)
        self.assertEqual(result["installation"]["executable"],str(self.exe))
        self.assertEqual(result["inputs"]["identity"]["product"],"wow_future")

    def test_ambiguous_release_needs_selection(self):
        (self.client/"WowOther.exe").write_bytes(b"fixture")
        with self.assertRaisesRegex(ValueError,"2 matching"):
            refresh.find_client([self.root],self.publisher.fetch,lambda _:BUILD)


if __name__=="__main__":
    unittest.main()
