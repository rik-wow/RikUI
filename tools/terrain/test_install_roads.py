"""Road installer: install, idempotent reinstall, tamper refusal and legacy retirement."""
import hashlib, json, pathlib, tempfile, unittest
import install_roads as r


def pack(root, files):
    rows = []
    for name, text in files.items():
        path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(text)
        rows.append({'path': name, 'bytes': len(text), 'sha256': hashlib.sha256(text).hexdigest()})
    raw = json.dumps({'format': 'rikui-road-network-receipt-v1', 'files': rows}).encode()
    (root / r.MANIFEST).write_bytes(raw)
    return hashlib.sha256(raw).hexdigest()


class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = pathlib.Path(self.tmp.name)
        self.source, self.addons = base / 'source', base / 'game' / 'AddOns'
        self.source.mkdir(); self.addons.mkdir(parents=True)
        self.sha = pack(self.source, {'RikUIQuestRoads/index.lua': b'-- index\n', 'RikUIQuestRoads/RikUIQuestRoads.toc': b'## x\n',
                                      'RikUIQuestRoads_W0/catalog.lua': b'-- c\n', 'RikUIQuestRoads_W0_P001/patch-001.lua': b'-- p\n'})

    def tearDown(self):
        self.tmp.cleanup()

    def test_install_and_verify(self):
        result = r.install(self.source, self.sha, self.addons)
        self.assertEqual(result['addons'], 3)
        self.assertEqual(r.verify(self.source, self.sha, self.addons)['verifiedFiles'], 4)

    def test_reinstall_keeps_previous_copy(self):
        r.install(self.source, self.sha, self.addons)
        result = r.install(self.source, self.sha, self.addons)
        self.assertTrue((pathlib.Path(result['backup']) / 'RikUIQuestRoads_W0').is_dir())

    def test_modified_install_is_refused(self):
        r.install(self.source, self.sha, self.addons)
        (self.addons / 'RikUIQuestRoads_W0' / 'catalog.lua').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'modified'):
            r.install(self.source, self.sha, self.addons)

    def test_wrong_receipt_hash_refused(self):
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            r.install(self.source, '0' * 64, self.addons)

    def test_retire_moves_only_legacy_addons(self):
        for name in ('RikUIQuestTerrain_R001', 'RikUIQuestPaths_M1426_P001', 'RikUIQuestTerrain', 'RikUIQuestCorpus', 'RikUI'):
            (self.addons / name).mkdir(); (self.addons / name / 'a.lua').write_bytes(b'x')
        (self.addons / '.rikui-world-navigation.json').write_text('{}')
        backup = pathlib.Path(self.tmp.name) / 'retired'
        result = r.retire(self.addons, backup)
        self.assertEqual(result['retired'], 3)
        self.assertTrue((self.addons / 'RikUIQuestCorpus').is_dir() and (self.addons / 'RikUI').is_dir())
        self.assertTrue((backup / 'RikUIQuestTerrain_R001' / 'a.lua').is_file())
        self.assertFalse((self.addons / '.rikui-world-navigation.json').exists())
        with self.assertRaisesRegex(ValueError, 'new directory'):
            r.retire(self.addons, backup)


if __name__ == '__main__':
    unittest.main()
