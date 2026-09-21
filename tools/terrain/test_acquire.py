import copy,json,os,pathlib,tempfile,unittest
import acquire as a

class AcquisitionChecks(unittest.TestCase):
    def test_pinned_profile_and_full_asset_inventory(self):
        profile=a.load_profile();self.assertEqual(len(profile['files']),391)
        self.assertEqual(sum(r['bytes'] for r in profile['files']),8785514)
        self.assertEqual({layer:sum(r['layer']==layer for r in profile['files']) for layer in a.LAYERS},dict(root=5,collision=158,**{'wmo-groups':26,'wmo-doodads':202}))
    def test_profile_modification_is_not_accepted(self):
        value=a.load_profile();value['files'][0]['sha256']='0'*64
        with tempfile.TemporaryDirectory() as folder:
            path=pathlib.Path(folder)/'profile.json';path.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError,'unpinned'):a.load_profile(path)
    def test_path_traversal_absolute_and_duplicate_destinations_rejected(self):
        profile=a.load_profile()
        for path in ('../asset.bin','C:/asset.bin','/asset.bin','collision/../asset.bin','collision/x:stream','collision\\evil.bin','collision/CON:name'):
            bad=copy.deepcopy(profile);bad['files'][0]['path']=path
            with self.assertRaises(ValueError,msg=path):a.validate_profile(bad)
        bad=copy.deepcopy(profile);bad['files'][1]['path']=bad['files'][0]['path']
        with self.assertRaises(ValueError):a.validate_profile(bad)
    def test_nonempty_and_overlapping_outputs_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);(root/'existing').write_text('preserve')
            with self.assertRaises(ValueError):a.empty_output(root)
            with self.assertRaises(ValueError):a.empty_output(root/'child',(root,))
            self.assertEqual((root/'existing').read_text(),'preserve')
    def test_repository_outputs_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);(root/'.git').mkdir()
            with self.assertRaisesRegex(ValueError,'repository'):a.empty_output(root/'output')
    def test_linked_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);(root/'real').write_text('x')
            try:(root/'link').symlink_to(root/'real')
            except OSError:self.skipTest('OS does not permit test symlink creation')
            with self.assertRaisesRegex(ValueError,'symlink'):a.checked_path(root/'link')
    def test_source_hashes_verified_before_copy(self):
        profile={'files':[dict(path='source.bin',bytes=1,sha256=a.digest(b'x'))]}
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);(root/'source.bin').write_bytes(b'y')
            with self.assertRaisesRegex(ValueError,'asset-hash'):a.verify(profile,root)
    def test_existing_exact_assets_match_profile(self):
        root=os.environ.get('RIKUI_TERRAIN_ACQUISITION')
        if not root:self.skipTest('External exact-build assets not configured')
        self.assertEqual(a.verify(a.load_profile(),root)['files'],391)
if __name__=='__main__':unittest.main()
