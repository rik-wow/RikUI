"""Private preparation storage preserves provenance, bounded reads and batch isolation."""
import copy
import gzip
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/terrain"))
from world_storage import encode, decode
import current_acquisition as acquisition
import world_export_graph as graph
from world_source import sha, canonical
import world_stitch as stitch
from test_world_bake import pair


class StorageTests(unittest.TestCase):
    def test_exact_round_trip_and_deterministic_encoding(self):
        raw = canonical(dict(positions=[1.123456789, -0.0001] * 10000, audit="unknown"))
        stored = encode(raw, len(raw))
        self.assertLess(len(stored), len(raw) / 10)
        self.assertEqual(stored, encode(raw, len(raw)))
        self.assertEqual(decode(stored, len(raw)), raw)

    def test_corruption_truncation_empty_and_expansion_bounds(self):
        stored = encode(b"x" * 10000, 10000)
        for bad in (stored[:-1], stored[:-8], stored[:12], b"invalid"):
            with self.subTest(bad=bad):
                with self.assertRaises((ValueError, EOFError, OSError)):
                    decode(bad, 10000)
        with self.assertRaisesRegex(ValueError, "decoded byte bound"):
            decode(stored, 100)
        with self.assertRaisesRegex(ValueError, "stored byte bound"):
            decode(stored, 1)
        with self.assertRaises(ValueError):
            encode(b"", 1)
        with self.assertRaises(ValueError):
            decode(gzip.compress(b""), 100)

    def test_compressed_and_legacy_geometry_follow_identical_evidence_checks(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "bake").mkdir()
            job = dict(source=dict(profileSHA256="p"))
            source = dict(placementIndexSHA256="i", parserSHA256="g")
            geometry = dict(job=job, source=source, exclusions=[])
            raw = canonical(geometry)
            manifest = dict(geometrySHA256=sha(raw), job=job, source=source, exclusions=[],
                            generator=dict(wrapperSHA256="w", boundedWrapperSHA256="b", filterSHA256="f"))
            batch = dict(manifest=manifest, polygons={})
            inputs = dict(jobSHA256=sha(canonical(job)), sourceProfileSHA256="p", indexSHA256="i",
                          tools={"world_geometry.py":"g", "bake_world_batch.mjs":"w",
                                 "world_tiled.mjs":"b", "mesh_filter.mjs":"f"})
            for compressed in (False, True):
                name = "geometry.json.gz" if compressed else "geometry.json"
                stored = encode(raw, 10000) if compressed else raw
                (root / name).write_bytes(stored)
                receipt = dict(status="derived-pending-seam-validation", nativeVerified=False, input=inputs,
                               files=[dict(filename=name, bytes=len(stored), sha256=sha(stored))])
                receipt_raw = canonical(receipt)
                (root / "receipt.json").write_bytes(receipt_raw)
                record = dict(receiptPath=str(root / "receipt.json"), receiptSHA256=sha(receipt_raw),
                              directory=str(root / "bake"))
                self.assertEqual(graph.validate_receipt(record, batch), receipt)
                wrong = copy.deepcopy(batch)
                wrong["manifest"]["geometrySHA256"] = "0" * 64
                with self.assertRaisesRegex(ValueError, "geometry/manifest hash"):
                    graph.validate_receipt(record, wrong)
                (root / name).write_bytes(stored[:-1])
                with self.assertRaises(ValueError):
                    graph.validate_receipt(record, batch)

    def test_compressed_owned_geometry_retains_exact_reciprocal_seams_and_rejects_tampering(self):
        def write(root, batch, compressed):
            root.mkdir()
            manifest = copy.deepcopy(batch["manifest"])
            world, x, z = batch["namespace"]
            manifest.update(format="rikui-world-nav-batch-v1", nativeVerified=False,
                            worldMapID=world, files=[])
            manifest["job"].update(id="fixture-%s-%s" % (x,z), batchGrid=[x,z])
            for name, rows in (("polygons.json", batch["polygons"]),
                               ("boundary-witnesses.json", batch["witnesses"])):
                raw = canonical(dict(worldMapID=world, jobID=manifest["job"]["id"],
                                     polygons=list(rows.values())))
                name += ".gz" if compressed else ""
                stored = encode(raw, 10000) if compressed else raw
                (root/name).write_bytes(stored)
                manifest["files"].append(dict(filename=name, bytes=len(stored), sha256=sha(stored)))
            raw = canonical(manifest)
            (root/"manifest.json").write_bytes(raw)
            return stitch.load(root, sha(raw))
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            a,b = pair()
            plain = [write(root/("plain-%s"%i), batch, False) for i,batch in enumerate((a,b))]
            zipped = [write(root/("gzip-%s"%i), batch, True) for i,batch in enumerate((a,b))]
            first, second = stitch.admit(*plain), stitch.admit(*zipped)
            self.assertEqual(first["directedLinks"], second["directedLinks"])
            self.assertEqual(first["exactWitnessMatches"], second["exactWitnessMatches"])
            self.assertEqual(second["exactWitnessMatches"], 2)
            path = root/"gzip-0"/"polygons.json.gz"
            path.write_bytes(path.read_bytes()[:-1])
            with self.assertRaisesRegex(ValueError, "batch payload hash"):
                stitch.load(root/"gzip-0", zipped[0]["sha256"])
            changed = copy.deepcopy(zipped[1])
            changed["polygons"][next(iter(changed["polygons"]))]["points"][0][0] += .001
            with self.assertRaisesRegex(ValueError, "geometry mismatch"):
                stitch.admit(zipped[0], changed)

    def test_extractor_batches_share_one_current_job_cache_without_touching_older_data(self):
        with tempfile.TemporaryDirectory() as folder:
            worker = acquisition.Acquisition.__new__(acquisition.Acquisition)
            worker.output = Path(folder) / "new-current-job"
            worker.output.mkdir()
            old = Path(folder) / "previous-job"
            old.mkdir()
            (old / "private").write_bytes(b"preserve")
            worker.resolution = dict(inputs=dict(identity=dict(product="fixture", buildConfig="b", cdnConfig="c")),
                                     installation=dict(storageRoot=str(Path(folder) / "game")))
            worker.tool = Path(folder) / "extractor.exe"
            worker.paths, worker.missing, worker.batches = {}, [], 0
            worker.start = time.monotonic()
            workspaces = []
            class Process:
                returncode = 0
                def poll(self):
                    return 0
            def start(arguments, cwd, **kwargs):
                workspaces.append(Path(cwd))
                listing = Path(arguments[arguments.index("-i") + 1])
                output = Path(arguments[arguments.index("-o") + 1])
                output.mkdir()
                for row in listing.read_text().splitlines():
                    (output / row.split(";")[1]).write_bytes(b"current input")
                cache = Path(cwd) / "cache"
                cache.mkdir(exist_ok=True)
                (cache / "current-metadata.decoded").write_bytes(b"shared current cache")
                return Process()
            with patch.object(acquisition.subprocess, "Popen", side_effect=start), patch.object(
                    acquisition.shutil, "disk_usage", return_value=Mock(free=20*1024**3)):
                worker.extract(list(range(1, 258)))
            self.assertEqual(len(workspaces), 3)
            self.assertEqual(len(set(workspaces)), 1)
            self.assertEqual(workspaces[0], worker.output / "extractor-workspace")
            self.assertEqual(len(worker.paths), 257)
            self.assertEqual(len(list(worker.output.rglob("*.decoded"))), 1)
            self.assertEqual((old / "private").read_bytes(), b"preserve")
            self.assertFalse(any((worker.output / ("extract-%04d" % i) / "cache").exists() for i in range(1,4)))


if __name__ == "__main__":
    unittest.main()
