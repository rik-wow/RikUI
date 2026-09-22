"""Fail-closed checks for offline client inventory framing and corrupt observations."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

MODULE = Path(__file__).with_name('quest_inventory.py')
if not MODULE.is_file():
    MODULE = Path(__file__).resolve().parents[1] / 'tools' / 'quest_inventory.py'
spec = importlib.util.spec_from_file_location('quest_inventory_under_test', MODULE)
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


class QuestInventoryTests(unittest.TestCase):
    def test_cache_counts_require_complete_record_framing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / 'questcache.wdb'
            archived = root / 'archived.wdb'
            header = b'TSQW' + struct.pack('<I', 69913) + b'SUne' + struct.pack('<III', 12296, 12, 0)
            valid = header + struct.pack('<II', 777, 3) + b'abc' + bytes(8)
            cache.write_bytes(valid)
            row = inventory.wdb_inventory(cache, 69913, archived)
            self.assertEqual(row['state'], 'framing-valid')
            self.assertEqual(row['recordCount'], 1)
            self.assertEqual(row['records'][0]['id'], 777)
            self.assertEqual(row['semanticStatus'], 'unknown')
            self.assertEqual(archived.read_bytes(), valid)
            for invalid in (valid[:-1], valid + b'x', header + struct.pack('<II', 777, 999) + b'abc'):
                cache.write_bytes(invalid)
                row = inventory.wdb_inventory(cache, 69913, archived)
                self.assertEqual(row['state'], 'framing-invalid')
                self.assertNotIn('recordCount', row)
            cache.write_bytes(valid)
            self.assertEqual(inventory.wdb_inventory(cache, 69914, archived)['state'], 'identity-mismatch')

    def test_corrupt_packet_and_mismatched_archive_do_not_supply_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root/'source'; target = root/'target'
            source.mkdir();target.mkdir()
            payload = b's5:hello'; checksum = f'{zlib.adler32(payload)&0xffffffff:08x}'
            packet = f'RIKQ1:{checksum}:{payload.hex()}'
            (source/'valid.rikq').write_text(packet)
            (source/'bad.rikq').write_text(packet[:-1] + ('0' if packet[-1] != '0' else '1'))
            (source/'valid.json').write_text(json.dumps({'inspection': {'observedCount': 99},
                                                        'source': {'packetSHA256': 'wrong'}}))
            rows = {row['name']: row for row in inventory.observations_inventory(source, target)}
            self.assertEqual(rows['valid.rikq']['state'], 'checksum-valid')
            self.assertEqual(rows['bad.rikq']['state'], 'checksum-mismatch')
            self.assertIsNone(rows['valid.rikq']['archiveMetadata']['observedCount'])
            self.assertFalse(rows['valid.rikq']['archiveMetadata']['packetHashMatches'])

    def test_matching_sidecar_hash_cannot_restore_corrupt_packet_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); source=root/'source'; target=root/'target'
            source.mkdir(); target.mkdir()
            for name,packet in [('corrupt',b'RIKQ1:00000000:73353a68656c6c6f'),
                                ('invalid',b'not-a-packet')]:
                (source/(name+'.rikq')).write_bytes(packet)
                (source/(name+'.json')).write_text(json.dumps({
                    'source':{'packetSHA256':inventory.sha(packet)},
                    'inspection':{'observedCount':1,'reportedCount':1,'quests':[{'id':777}]}}))
            rows=inventory.observations_inventory(source,target)
            self.assertEqual(len(rows),2)
            for row in rows:
                metadata=row['archiveMetadata']
                self.assertTrue(metadata['packetHashMatches'])
                self.assertEqual(metadata['state'],'rejected')
                self.assertIsNone(metadata['observedCount'])
                self.assertIsNone(metadata['reportedCount'])
                self.assertEqual(metadata['questIds'],[])

    def test_malformed_sidecar_does_not_abort_independent_packets(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); source=root/'source'; target=root/'target'
            source.mkdir(); target.mkdir()
            payload=b's5:hello'
            packet=f'RIKQ1:{zlib.adler32(payload)&0xffffffff:08x}:{payload.hex()}'.encode()
            sidecars={'a':b'{malformed','b':b'[]','c':b'{"inspection":1}',
                      'd':json.dumps({'source':{'packetSHA256':inventory.sha(packet)},
                          'inspection':{'observedCount':1,'reportedCount':1,'quests':[{'id':777}]}}).encode()}
            for name,sidecar in sidecars.items():
                (source/(name+'.rikq')).write_bytes(packet)
                (source/(name+'.json')).write_bytes(sidecar)
            rows={row['name']:row for row in inventory.observations_inventory(source,target)}
            self.assertEqual(len(rows),4)
            for name in ('a','b','c'):
                metadata=rows[name+'.rikq']['archiveMetadata']
                self.assertEqual(metadata['state'],'invalid')
                self.assertEqual(metadata['questIds'],[])
                self.assertIsNone(metadata['observedCount'])
            self.assertEqual(rows['d.rikq']['archiveMetadata']['state'],'accepted')
            self.assertEqual(rows['d.rikq']['archiveMetadata']['questIds'],[777])

    def test_csv_availability_does_not_invent_semantic_fields(self):
        row = inventory.csv_inventory(b'ID,UniqueBitFlag,UiQuestDetailsThemeID\n77,2,0\n88,3,0\n')
        self.assertEqual(row['rowCount'], 2)
        self.assertEqual(row['uniqueIdCount'], 2)
        self.assertEqual(row['columns'], ['ID', 'UniqueBitFlag', 'UiQuestDetailsThemeID'])
        for value in (b'<html>denied</html>', b'ID\n', b'ID\n0\n', b'ID\nabc\n', b'ID\n1,extra\n'):
            with self.assertRaises(ValueError): inventory.csv_inventory(value)


if __name__ == '__main__':
    unittest.main()


