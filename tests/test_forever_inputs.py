"""Discovery contracts and failure cases; fixture versions are synthetic."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import forever_inputs as inputs

BUILD = "1.99.1.12345"
HEADER = "Active!DEC:1|Build Key!HEX:16|CDN Key!HEX:16|Version!STRING:0|Product!STRING:0"
ROW = "1|" + "a" * 32 + "|" + "b" * 32 + "|" + BUILD + "|wow_future"
RAW = (HEADER + "\n" + ROW + "\n").encode()


class Publishers:
    def __init__(self):
        self.calls = []
        self.revisions = {repo: str(index + 1) * 40
                          for index, (repo, _) in enumerate(inputs.SOURCES.values())}
        self.build = BUILD
        self.message = "1.99.1 (12345)"

    def fetch(self, url):
        self.calls.append(url)
        if url.endswith("/version.txt"):
            return self.build.encode()
        for repo, branch in inputs.SOURCES.values():
            if url == "https://github.com/" + repo + ".git/info/refs?service=git-upload-pack":
                revision = self.revisions[repo]
                def packet(value):
                    raw = value.encode()
                    return ("%04x" % (len(raw)+4)).encode()+raw
                head = revision+" HEAD\0symref=HEAD:refs/heads/publisher-default\n"
                result = packet("# service=git-upload-pack\n")+b"0000"+packet(head)
                result += packet(revision+" refs/heads/publisher-default\n")
                if branch:
                    result += packet(revision+" refs/heads/"+branch+"\n")
                return result+b"0000"
            base = "https://api.github.com/repos/" + repo
            if url == base:
                return json.dumps({"default_branch": "publisher-default"}).encode()
            if url.startswith(base + "/commits/"):
                return json.dumps({"sha": self.revisions[repo],
                                   "commit": {"message": self.message}}).encode()
        raise AssertionError("Unexpected publisher URL: " + url)


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.client = self.root / "release-directory"
        self.client.mkdir()
        self.exe = self.client / "DiscoveredForever.exe"
        self.exe.write_bytes(b"fixture only; injected version reader")
        self.info = self.root / ".build.info"
        self.info.write_bytes(RAW)
        self.publishers = Publishers()

    def discover(self, version=BUILD):
        return inputs.discover(self.exe, self.publishers.fetch, lambda _: version)

    def test_release_product_executable_directory_discovered(self):
        result = self.discover()
        self.assertEqual(result["inputs"]["identity"]["product"], "wow_future")
        self.assertEqual(result["installation"]["directory"], str(self.client))
        self.assertEqual(result["installation"]["executable"], str(self.exe))
        self.assertEqual(result["compatibility"], "not-yet-verified")
        self.assertEqual(inputs.validate_resolution(result), result)

    def test_forever_branch_and_exact_revision_version_url(self):
        self.discover()
        self.assertIn("https://github.com/Gethe/wow-ui-source.git/info/refs?service=git-upload-pack",
                      self.publishers.calls)
        revision = self.publishers.revisions["Gethe/wow-ui-source"]
        self.assertIn("https://raw.githubusercontent.com/Gethe/wow-ui-source/"
                      + revision + "/version.txt", self.publishers.calls)

    def test_other_publishers_discover_default_branches(self):
        self.discover()
        for name in ("provider", "events", "schemas"):
            repo = inputs.SOURCES[name][0]
            self.assertIn("https://github.com/" + repo
                          + ".git/info/refs?service=git-upload-pack", self.publishers.calls)

    def test_mismatch_refuses_old_executable(self):
        with self.assertRaisesRegex(ValueError, "not the current"):
            self.discover("1.99.1.12344")

    def test_message_version_mismatch_refused(self):
        self.publishers.message = "1.99.1 (12344)"
        with self.assertRaisesRegex(ValueError, "disagree"):
            self.discover()

    def test_version_must_be_exact(self):
        self.publishers.build = "notes " + BUILD
        with self.assertRaisesRegex(ValueError, "exact full version"):
            self.discover()

    def test_unique_active_product_required(self):
        self.info.write_bytes((HEADER + "\n" + ROW + "\n" + ROW + "\n").encode())
        with self.assertRaisesRegex(ValueError, "unique active"):
            self.discover()

    def test_inactive_build_refused(self):
        self.info.write_bytes(RAW.replace(b"\n1|", b"\n0|"))
        with self.assertRaisesRegex(ValueError, "unique active"):
            self.discover()

    def test_invalid_config_refused(self):
        self.info.write_bytes(RAW.replace(b"a" * 32, b"bad"))
        with self.assertRaisesRegex(ValueError, "configuration"):
            self.discover()

    def test_duplicate_metadata_locations_refused(self):
        (self.client / ".build.info").write_bytes(RAW)
        with self.assertRaisesRegex(ValueError, "unique supported"):
            self.discover()

    def test_unsupported_metadata_schema_refused(self):
        self.info.write_bytes(RAW.replace(b"CDN Key", b"Unknown"))
        with self.assertRaisesRegex(ValueError, "schema"):
            self.discover()

    def test_client_metadata_change_during_discovery_refused(self):
        def version_reader(_):
            self.info.write_bytes(RAW + b"\n")
            return BUILD
        with self.assertRaisesRegex(ValueError, "changed during"):
            inputs.discover(self.exe, self.publishers.fetch, version_reader)

    def test_network_failure_has_no_fallback(self):
        def fail(_):
            raise OSError("publisher unavailable")
        with self.assertRaisesRegex(OSError, "publisher unavailable"):
            inputs.discover(self.exe, fail, lambda _: BUILD)

    def test_unchanged_metadata_is_hint_not_asset_acceptance(self):
        prior = self.discover()
        now = self.discover()
        now["resolvedAt"] = "a later observation"
        self.assertEqual(inputs.changes(prior, now), [])
        self.assertEqual(now["compatibility"], "not-yet-verified")

    def test_changed_provider_is_detected(self):
        prior = self.discover()
        self.publishers.revisions["Questie/QuestieDB"] = "f" * 40
        self.assertEqual(inputs.changes(prior, self.discover()), ["provider"])

    def test_changed_schema_is_detected(self):
        prior = self.discover()
        self.publishers.revisions["wowdev/WoWDBDefs"] = "f" * 40
        self.assertEqual(inputs.changes(prior, self.discover()), ["schemas"])

    def test_changed_config_is_detected(self):
        prior = self.discover()
        self.info.write_bytes(RAW.replace(b"a" * 32, b"c" * 32))
        self.assertEqual(inputs.changes(prior, self.discover()), ["client"])

    def test_first_resolution_requires_all_groups(self):
        self.assertEqual(inputs.changes(None, self.discover()),
                         ["client", "ui", "provider", "events", "schemas"])

    def test_tampered_receipt_refused(self):
        receipt = self.discover()
        receipt["inputs"]["identity"]["buildConfig"] = "c" * 32
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            inputs.validate_resolution(receipt)

    def test_missing_source_refused_even_after_rehash(self):
        receipt = self.discover()
        del receipt["inputs"]["sources"]["events"]
        receipt["fingerprint"] = inputs.sha(inputs.canonical(receipt["inputs"]))
        with self.assertRaisesRegex(ValueError, "Incomplete upstream"):
            inputs.validate_resolution(receipt)

    def test_discovery_cannot_claim_compatibility(self):
        receipt = self.discover()
        receipt["compatibility"] = "verified"
        with self.assertRaisesRegex(ValueError, "Unsupported discovery"):
            inputs.validate_resolution(receipt)

    def test_immutable_receipt_preserves_existing_bytes(self):
        receipt = self.discover()
        target = self.root / "receipt.json"
        inputs.save_resolution(target, receipt)
        original = target.read_bytes()
        with self.assertRaises(FileExistsError):
            inputs.save_resolution(target, receipt)
        self.assertEqual(target.read_bytes(), original)
        self.assertEqual(json.loads(original), receipt)

    def test_rehashed_unknown_provider_repository_refused(self):
        receipt = copy.deepcopy(self.discover())
        receipt["inputs"]["sources"]["provider"]["repository"] = "other/provider"
        receipt["fingerprint"] = inputs.sha(inputs.canonical(receipt["inputs"]))
        with self.assertRaisesRegex(ValueError, "Invalid upstream"):
            inputs.validate_resolution(receipt)


class ReferencePacketTests(unittest.TestCase):
    def test_malformed_truncated_empty_and_unadvertised_protocol(self):
        for raw in (b"", b"xyz0", b"0005", b"0001", b"0008ABCD", b"001e# service=git-upload-pack\n000500"):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                inputs.advertised_refs(raw)

    def test_default_and_forever_heads_are_discovered(self):
        publisher=Publishers()
        refs,default=inputs.advertised_refs(publisher.fetch(
            "https://github.com/Gethe/wow-ui-source.git/info/refs?service=git-upload-pack"))
        self.assertEqual(default,"publisher-default")
        self.assertEqual(refs["refs/heads/forever"],publisher.revisions["Gethe/wow-ui-source"])

    def test_missing_advertised_forever_branch_fails(self):
        publisher=Publishers()
        with self.assertRaisesRegex(ValueError,"not advertised"):
            inputs.resolve_source("Questie/QuestieDB","absent",publisher.fetch)


if __name__ == "__main__":
    unittest.main()
