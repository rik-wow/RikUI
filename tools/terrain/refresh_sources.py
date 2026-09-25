"""Refresh a world acquisition from a completed exact-build comparison.
Only current referenced assets enter the new profile. Missing files are extracted
with the pinned tool; no old bytes substitute for a missing current dependency.
"""
import argparse
import collections
import json
import pathlib
import subprocess

import acquire
import client_build
import terrain_probe
import wmo_probe
from world_source import WDT_PINS, canonical, sha, need

MAX_FILES = 32768
MAX_BYTES = 64 * 1024 * 1024
BATCH = 128


def digest_file(path):
    raw = path.read_bytes()
    need(0 < len(raw) <= MAX_BYTES, "asset byte bound")
    return len(raw), sha(raw)


def seed_paths(report, original, verification, supplement):
    expected = {r["fileDataID"]: r["sha256"] for r in original["files"]}
    expected.update({r["fileDataID"]: r["new"] for r in report["changed"]})
    paths = {}
    for path in pathlib.Path(verification).glob("chunk-*/files/*.bin"):
        ident = int(path.stem)
        need(ident not in paths, "duplicate comparison asset")
        need(ident in expected and expected[ident] is not None, "unreported comparison asset")
        need(digest_file(path)[1] == expected[ident], "comparison asset changed: " + str(ident))
        paths[ident] = path
    # Supplementary files are admitted only by the pinned topology hashes.
    # Any other missing dependency must be extracted under the current config.
    for _, (ident, expected_sha) in WDT_PINS.items():
        path = pathlib.Path(supplement, "%d.bin" % ident)
        need(digest_file(path)[1] == expected_sha, "changed world topology")
        paths[ident] = path
    return paths


class Refresh:
    def __init__(self, args):
        self.args = args
        self.output = acquire.empty_output(args.output, (pathlib.Path(args.game_root),))
        self.tool = acquire.checked_path(args.tact_tool)
        pin = acquire.load_profile()["tool"]["binary"]
        need(digest_file(self.tool) == (pin["bytes"], pin["sha256"]), "pinned TACTTool hash")
        self.report = json.loads(pathlib.Path(args.verification, "verification.json").read_bytes())
        need(self.report.get("format") == "rikui-build-verification-v1", "comparison format")
        need(self.report["tool"] == pin, "comparison extractor")
        need(self.report["cdnConfig"] == client_build.IDENTITY["cdnConfig"], "comparison CDN")
        need(self.report["toVersion"] == client_build.BUILD, "comparison build")
        need(self.report["buildConfig"] == client_build.IDENTITY["buildConfig"], "comparison config")
        profile_path = pathlib.Path(self.report["profile"])
        need(sha(profile_path.read_bytes()) == self.report["profileSHA256"], "comparison profile")
        self.original = json.loads(profile_path.read_bytes())
        self.paths = seed_paths(self.report, self.original, args.verification, args.supplement)
        self.rows, self.batch = {}, 0

    def want(self, ident, kind, worlds, tile=None):
        need(type(ident) is int and 0 < ident < 2**31, "asset id")
        prior = self.rows.setdefault(ident, dict(fileDataID=ident, kind=kind, worldMapIDs=[]))
        need(prior["kind"] == kind, "conflicting asset kind")
        prior["worldMapIDs"] = sorted(set(prior["worldMapIDs"]) | set(worlds))
        if tile is not None:
            need(prior.get("tile", tile) == tile, "conflicting asset tile")
            prior["tile"] = tile
        need(len(self.rows) <= MAX_FILES, "dependency cap")

    def extract(self, ids):
        for at in range(0, len(ids), BATCH):
            self.batch += 1
            folder = self.output / ("extract-%03d" % self.batch)
            folder.mkdir()
            listing = folder / "files.list"
            listing.write_text("".join("%d;%d.bin\n" % (i, i) for i in ids[at:at+BATCH]))
            cmd = [str(self.tool), "-d", self.args.game_root, "-p", client_build.IDENTITY["product"],
                   "-b", client_build.IDENTITY["buildConfig"], "-c", client_build.IDENTITY["cdnConfig"],
                   "-l", "enUS", "-m", "list", "-i", str(listing), "-o", str(folder / "assets")]
            with (folder / "extract.log").open("xb") as log:
                run = subprocess.run(cmd, cwd=folder, stdout=log, stderr=subprocess.STDOUT, timeout=600)
            need(run.returncode == 0, "extract failed; see " + str(folder))
            for ident in ids[at:at+BATCH]:
                path = folder / "assets" / ("%d.bin" % ident)
                need(path.is_file(), "current dependency missing: " + str(ident))
                self.paths[ident] = path

    def ensure(self):
        missing = sorted(set(self.rows) - set(self.paths))
        if missing:
            self.extract(missing)
        for ident, row in self.rows.items():
            size, digest = digest_file(self.paths[ident])
            row.update(path=str(self.paths[ident].resolve()), bytes=size, sha256=digest)
        print(json.dumps(dict(files=len(self.rows), extracted=len(missing))), flush=True)

    def run(self):
        for row in self.original["files"]:
            if row["kind"] in ("rootADT", "obj0ADT"):
                self.want(row["fileDataID"], row["kind"], row["worldMapIDs"], row["tile"])
        self.ensure()
        for row in list(self.rows.values()):
            if row["kind"] != "obj0ADT":
                continue
            placed, _, names = terrain_probe.objects(pathlib.Path(row["path"]).read_bytes())
            need(not names, "named placements unsupported")
            for item in placed:
                self.want(item["reference"], "M2" if item["kind"] == "m2" else "WMO", row["worldMapIDs"])
        self.ensure()
        for row in list(self.rows.values()):
            if row["kind"] != "WMO":
                continue
            root = wmo_probe.root(pathlib.Path(row["path"]).read_bytes())
            for ident in root["groups"]:
                self.want(ident, "WMOGroup", row["worldMapIDs"])
            for item in root["doodads"]:
                self.want(item["reference"], "M2", row["worldMapIDs"])
        self.ensure()
        self.finish()

    def finish(self):
        topology = []
        for world, (ident, expected) in WDT_PINS.items():
            path = self.paths[ident]
            need(digest_file(path)[1] == expected, "changed world topology: " + str(world))
            topology.append(dict(worldMapID=world, fileDataID=ident, path=str(path.resolve()), sha256=expected))
        profile = dict(format="rikui-forever-world-acquisition-profile-v1", identity=client_build.IDENTITY,
                       files=[self.rows[i] for i in sorted(self.rows)], nativeVerified=False)
        path = self.output / "acquisition-profile.json"
        path.write_bytes(canonical(profile))
        (self.output / "topology.json").write_bytes(canonical(dict(topologyEvidence=topology)))
        print(json.dumps(dict(profile=str(path), sha256=sha(path.read_bytes()),
                              counts=dict(collections.Counter(r["kind"] for r in self.rows.values())))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("verification", "supplement", "game-root", "tact-tool", "output"):
        parser.add_argument("--" + name, required=True)
    Refresh(parser.parse_args()).run()


if __name__ == "__main__":
    main()

