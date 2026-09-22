"""Filesystem delivery invariants with isolated temporary AddOns directories."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import compile_backbone as compiler
import install_backbone as delivery
from test_compile_backbone import CompactCompileTests


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addons = self.root / 'AddOns'
        self.addons.mkdir()
        self.source, self.sha = self.pack('a')
        self.unrelated = self.addons / 'Unrelated'
        self.unrelated.mkdir()
        (self.unrelated / 'keep.txt').write_text('untouched')

    def pack(self, revision):
        backbone, nodes = CompactCompileTests().fixture()
        surfaces = compiler.pack_surface_geometry(backbone, nodes, 'a'*64, 'a'*64)
        files, _ = compiler.build_files(backbone, revision*64, surfaces)
        root = self.root / ('pack-' + revision)
        compiler.write_or_verify(files, root)
        return root, delivery.digest((root / 'manifest.json').read_bytes())

    def test_install_verify_repeat_and_owned_upgrade(self):
        delivered = delivery.install(self.source, self.sha, self.addons)
        self.assertGreater(delivered['verifiedFiles'], 1)
        self.assertEqual(delivery.verify_installed(self.source, self.sha, self.addons)['manifestSHA256'], self.sha)
        self.assertEqual(delivery.install(self.source, self.sha, self.addons)['manifestSHA256'], self.sha)
        second, second_sha = self.pack('b')
        upgraded = delivery.install(second, second_sha, self.addons)
        self.assertTrue((Path(upgraded['backup']) / delivery.RECEIPT).is_file())
        self.assertEqual((self.unrelated / 'keep.txt').read_text(), 'untouched')

    def test_corrupt_source_or_wrong_receipt_rejected_before_install(self):
        with self.assertRaises(ValueError):
            delivery.install(self.source, '0'*64, self.addons)
        path = self.source / 'RikUIQuestPaths' / 'catalog.lua'
        path.write_text('corrupt')
        with self.assertRaises(ValueError):
            delivery.install(self.source, self.sha, self.addons)
        self.assertEqual({p.name for p in self.addons.iterdir()}, {'Unrelated'})

    def test_unowned_or_modified_target_preserved(self):
        folder = self.addons / 'RikUIQuestPaths'
        folder.mkdir()
        (folder / 'user.lua').write_text('user content')
        with self.assertRaises(ValueError):
            delivery.install(self.source, self.sha, self.addons)
        self.assertEqual((folder / 'user.lua').read_text(), 'user content')

    def test_modified_owned_target_preserved(self):
        delivery.install(self.source, self.sha, self.addons)
        path = self.addons / 'RikUIQuestPaths' / 'catalog.lua'
        path.write_text('user change')
        with self.assertRaises(ValueError):
            delivery.install(self.source, self.sha, self.addons)
        self.assertEqual(path.read_text(), 'user change')

    def test_final_verification_failure_restores_exact_previous_pack(self):
        delivery.install(self.source, self.sha, self.addons)
        second, sha = self.pack('b')
        with mock.patch.object(delivery, 'verify_installed', side_effect=ValueError('injected final check')):
            with self.assertRaisesRegex(ValueError, 'injected'):
                delivery.install(second, sha, self.addons)
        delivery.verify_installed(self.source, self.sha, self.addons)

    def test_move_failure_before_receipt_move_preserves_ownership(self):
        delivery.install(self.source, self.sha, self.addons)
        second, sha = self.pack('b')
        original = Path.replace
        calls = 0
        def fail_second(path, target):
            nonlocal calls
            if path.parent == self.addons and path.name != delivery.RECEIPT:
                calls += 1
                if calls == 2:
                    raise OSError('injected rename')
            return original(path, target)
        with mock.patch.object(Path, 'replace', fail_second):
            with self.assertRaisesRegex(OSError, 'injected'):
                delivery.install(second, sha, self.addons)
        delivery.verify_installed(self.source, self.sha, self.addons)

    def test_manifest_cannot_rename_unrelated_addon(self):
        manifest = json.loads((self.source / 'manifest.json').read_text())
        manifest['files'][0]['path'] = '../Unrelated/keep.txt'
        with self.assertRaises(ValueError):
            delivery.expected_files(manifest)


if __name__ == '__main__':
    unittest.main()
