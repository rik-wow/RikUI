"""Atomic world delivery and separation from existing legacy navigation."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import install_world as delivery

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.addons=self.root/'AddOns';self.addons.mkdir()
        for name in ('Unrelated','RikUIQuestTerrain','RikUIQuestPaths','RikUIQuestPaths_M1426'):
            folder=self.addons/name;folder.mkdir();(folder/'keep.txt').write_text(name)
        self.source,self.sha=self.pack('a')
    def pack(self,revision):
        ns='W0_G'+revision*16
        terrain='RikUIQuestTerrain_'+ns
        names=[terrain,terrain+'_R001','RikUIQuestTerrainMap_M1426']
        root=self.root/('pack-'+revision);root.mkdir()
        files={}
        for name in names:
            folder=root/name;folder.mkdir()
            for leaf,data in ((name+'.toc',b'## Dependencies: RikUI\n## LoadOnDemand: 1\ndata.lua\n'),('data.lua',('return "'+revision+'"\n').encode())):
                (folder/leaf).write_bytes(data);files[name+'/'+leaf]=data
        (root/'audit').mkdir();files['audit/'+ns+'.json']=b'{}';files['world-pack-seams.json']=b'{"seams":[]}'
        for name,data in files.items():
            if name.startswith('audit/') or name=='world-pack-seams.json':(root/name).write_bytes(data)
        manifest=dict(format=delivery.FORMAT,identity=dict(product='forever',build='1.60.1.69913',locale='enUS'),
            inputSHA256=revision*64,sourceProfileSHA256='b'*64,placementIndexSHA256='c'*64,seamSHA256='d'*64,
            maps=[1426],seams=0,packs=[dict(namespace=ns,worldMapID=0,regions=1,compact=False)],
            files=[dict(path=n,bytes=len(d),sha256=delivery.digest(d)) for n,d in sorted(files.items())])
        raw=json.dumps(manifest,sort_keys=True).encode();(root/delivery.MANIFEST).write_bytes(raw)
        return root,delivery.digest(raw)
    def test_install_repeat_upgrade_and_legacy_preservation(self):
        result=delivery.install(self.source,self.sha,self.addons)
        self.assertEqual(result['verifiedFiles'],6);self.assertEqual(result['addons'],3)
        self.assertEqual(delivery.install(self.source,self.sha,self.addons)['manifestSHA256'],self.sha)
        second,sha=self.pack('b');result=delivery.install(second,sha,self.addons)
        self.assertTrue((Path(result['backup'])/delivery.RECEIPT).is_file())
        for name in ('Unrelated','RikUIQuestTerrain','RikUIQuestPaths','RikUIQuestPaths_M1426'):
            self.assertEqual((self.addons/name/'keep.txt').read_text(),name)
        self.assertFalse((self.addons/'audit').exists())
    def test_wrong_manifest_and_mutated_audit_rejected(self):
        with self.assertRaises(ValueError):delivery.install(self.source,'0'*64,self.addons)
        next((self.source/'audit').iterdir()).write_text('changed')
        with self.assertRaisesRegex(ValueError,'audit bytes'):delivery.install(self.source,self.sha,self.addons)
        self.assertFalse((self.addons/delivery.RECEIPT).exists())
    def test_unowned_namespace_preserved(self):
        path=self.addons/'RikUIQuestTerrain_W0_Gaaaaaaaaaaaaaaaa';path.mkdir();(path/'user.lua').write_text('keep')
        with self.assertRaisesRegex(ValueError,'no ownership'):delivery.install(self.source,self.sha,self.addons)
        self.assertEqual((path/'user.lua').read_text(),'keep')
    def test_modified_owned_source_preserved(self):
        delivery.install(self.source,self.sha,self.addons)
        path=self.addons/'RikUIQuestTerrain_W0_Gaaaaaaaaaaaaaaaa'/'data.lua';path.write_text('changed')
        with self.assertRaisesRegex(ValueError,'modified'):delivery.install(self.source,self.sha,self.addons)
        self.assertEqual(path.read_text(),'changed')
    def test_verification_failure_rolls_back_previous_generation(self):
        delivery.install(self.source,self.sha,self.addons);second,sha=self.pack('b')
        with mock.patch.object(delivery,'verify_installed',side_effect=ValueError('injected check')):
            with self.assertRaisesRegex(ValueError,'injected'):delivery.install(second,sha,self.addons)
        delivery.verify_installed(self.source,self.sha,self.addons)
    def test_mid_rename_failure_preserves_previous_receipt(self):
        delivery.install(self.source,self.sha,self.addons);second,sha=self.pack('b');original=Path.replace;calls=0
        def fail(path,target):
            nonlocal calls
            if path.parent==self.addons and path.name!=delivery.RECEIPT:
                calls+=1
                if calls==2:raise OSError('injected rename')
            return original(path,target)
        with mock.patch.object(Path,'replace',fail):
            with self.assertRaisesRegex(OSError,'injected'):delivery.install(second,sha,self.addons)
        delivery.verify_installed(self.source,self.sha,self.addons)
    def test_unsafe_paths_and_unrelated_addons_rejected(self):
        for path in ('../Unrelated/keep.txt','C:/foreign.lua','RikUIQuestTerrain/catalog.lua','RikUIQuestTerrain_W0_Gbbbbbbbbbbbbbbbb/data.lua'):
            manifest=json.loads((self.source/delivery.MANIFEST).read_bytes());manifest['files'][0]['path']=path
            with self.assertRaises(ValueError):delivery.expected_files(manifest)
    def test_missing_or_duplicate_records_rejected(self):
        original=json.loads((self.source/delivery.MANIFEST).read_bytes())
        for mutate in (lambda m:m['files'].append(m['files'][0]),lambda m:m['files'].pop(0),lambda m:m['packs'][0].update(regions=2),lambda m:m.update(maps=[1426,1426]),lambda m:m.update(seams=1)):
            manifest=json.loads(json.dumps(original));mutate(manifest)
            with self.assertRaises(ValueError):delivery.expected_files(manifest)
    def test_source_extra_content_rejected(self):
        (self.source/'unlisted.txt').write_text('unexpected')
        with self.assertRaisesRegex(ValueError,'unexpected source'):delivery.source_pack(self.source,self.sha)
    def test_identity_mismatch_rejected(self):
        manifest=json.loads((self.source/delivery.MANIFEST).read_bytes());manifest['identity']['locale']='deDE'
        with self.assertRaisesRegex(ValueError,'identity'):delivery.expected_files(manifest)
if __name__=='__main__':unittest.main()
