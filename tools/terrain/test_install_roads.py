"""Road installer: embedded files plus patch packs, idempotent reinstall, tamper refusal, legacy retirement."""
import hashlib, json, pathlib, tempfile, unittest
import install_roads as r

INDEX = 'generated/roads/index.lua'


def pack(root, files):
    rows = []
    for name, text in files.items():
        path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(text)
        rows.append({'path': name, 'bytes': len(text), 'sha256': hashlib.sha256(text).hexdigest()})
    raw = json.dumps({'format': 'rikui-road-network-receipt-v1', 'files': rows}).encode()
    (root / r.MANIFEST).write_bytes(raw)
    return hashlib.sha256(raw).hexdigest()


def rikui_folder(addons):
    rikui = addons / 'RikUI'
    (rikui / 'generated').mkdir(parents=True)
    (rikui / 'RikUI.toc').write_bytes(b'## Title: RikUI\n')
    (rikui / 'generated' / 'index.xml').write_bytes(b'<Ui/>\n')
    return rikui


class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = pathlib.Path(self.tmp.name)
        self.source, self.addons = base / 'source', base / 'game' / 'AddOns'
        self.source.mkdir(); self.addons.mkdir(parents=True)
        self.rikui = rikui_folder(self.addons)
        self.files = {INDEX: b'-- index\n', 'generated/roads/roads.xml': b'<Ui/>\n',
                      'generated/roads/w0-catalog.lua': b'-- c\n', 'RikUIQuestRoads_W0_P001/patch-001.lua': b'-- p\n',
                      'RikUIQuestRoads_W0_P001/RikUIQuestRoads_W0_P001.toc': b'## x\n'}
        self.sha = pack(self.source, self.files)

    def tearDown(self):
        self.tmp.cleanup()

    def test_install_places_embedded_files_and_packs(self):
        result = r.install(self.source, self.sha, self.addons, self.rikui)
        self.assertEqual(result['addons'], 1)
        self.assertEqual(r.verify(self.source, self.sha, self.addons, self.rikui)['verifiedFiles'], 5)
        self.assertTrue((self.rikui / 'generated' / 'roads' / 'index.lua').is_file())
        self.assertTrue((self.addons / 'RikUIQuestRoads_W0_P001' / 'patch-001.lua').is_file())
        self.assertEqual({p.name for p in self.addons.iterdir()}, {'RikUI', 'RikUIQuestRoads_W0_P001', r.RECEIPT})

    def test_reinstall_keeps_previous_copy(self):
        r.install(self.source, self.sha, self.addons, self.rikui)
        result = r.install(self.source, self.sha, self.addons, self.rikui)
        backup = pathlib.Path(result['backup'])
        self.assertTrue((backup / 'RikUIQuestRoads_W0_P001').is_dir())
        self.assertTrue((pathlib.Path(result['embeddedBackup']) / 'roads' / 'index.lua').is_file())
        self.assertEqual(sorted(p.name for p in (self.rikui / 'generated').iterdir() if not p.name.startswith('.')), ['index.xml', 'roads'])

    def test_previous_layout_folders_move_to_backup(self):
        # The old layout: always-loaded index addon, world and part addons, 1 MiB packs.
        old = {'RikUIQuestRoads/index.lua': b'-- old\n', 'RikUIQuestRoads_W0/catalog.lua': b'-- old\n',
               'RikUIQuestRoads_W0_N01/stream-1.lua': b'-- old\n', 'RikUIQuestRoads_W0_P007/patch-001.lua': b'-- old\n'}
        for name, text in old.items():
            path = self.addons / name; path.parent.mkdir(); path.write_bytes(text)
        receipt = {'owner': 'rikui-road-network-install-v1', 'manifestSHA256': '0' * 64,
                   'files': {k: {'bytes': len(v), 'sha256': hashlib.sha256(v).hexdigest()} for k, v in old.items()}}
        (self.addons / r.RECEIPT).write_text(json.dumps(receipt))
        result = r.install(self.source, self.sha, self.addons, self.rikui)
        self.assertEqual(result['previousAddons'], 4)
        self.assertFalse((self.addons / 'RikUIQuestRoads').exists())
        self.assertTrue((pathlib.Path(result['backup']) / 'RikUIQuestRoads_W0_N01' / 'stream-1.lua').is_file())
        r.verify(self.source, self.sha, self.addons, self.rikui)

    def test_modified_install_is_refused(self):
        r.install(self.source, self.sha, self.addons, self.rikui)
        (self.rikui / 'generated' / 'roads' / 'w0-catalog.lua').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'modified'):
            r.install(self.source, self.sha, self.addons, self.rikui)

    def test_failed_verify_restores_previous_state(self):
        r.install(self.source, self.sha, self.addons, self.rikui)
        before = (self.rikui / 'generated' / 'roads' / 'w0-catalog.lua').read_bytes()
        original = r.verify
        r.verify = lambda *args: (_ for _ in ()).throw(ValueError('injected'))
        try:
            with self.assertRaisesRegex(ValueError, 'injected'):
                r.install(self.source, self.sha, self.addons, self.rikui)
        finally:
            r.verify = original
        self.assertEqual((self.rikui / 'generated' / 'roads' / 'w0-catalog.lua').read_bytes(), before)
        self.assertTrue((self.addons / 'RikUIQuestRoads_W0_P001' / 'patch-001.lua').is_file())
        r.verify(self.source, self.sha, self.addons, self.rikui)

    def test_wrong_receipt_hash_refused(self):
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            r.install(self.source, '0' * 64, self.addons, self.rikui)

    def test_rikui_folder_must_support_embedded_data(self):
        (self.rikui / 'generated' / 'index.xml').unlink()
        with self.assertRaisesRegex(ValueError, 'generated/index.xml'):
            r.install(self.source, self.sha, self.addons, self.rikui)

    def test_retire_moves_only_legacy_addons(self):
        for name in ('RikUIQuestTerrain_R001', 'RikUIQuestPaths_M1426_P001', 'RikUIQuestTerrain', 'RikUIQuestCorpus'):
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
