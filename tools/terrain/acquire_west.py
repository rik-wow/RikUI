"""Acquire the exact-build west/central Dun Morogh sources; read-only client access."""
import argparse
import copy
import json
import pathlib
import re
import shutil
import struct
import subprocess
import acquire as a
import terrain_probe as t
import wmo_probe as w
import west_profile as west

TILES = tuple((x, y) for x in range(30, 34) for y in (41, 42))
REGION = ((-1066.6673177083333, -5866.667317708333), (1066.666015625, -5150.0))
MAX_FILES, MAX_BYTES = 2048, 64 * 1024 * 1024


def relevant(placement):
    return west.relevant(placement)


class Acquisition:
    max_files, max_bytes = MAX_FILES, MAX_BYTES

    def __init__(self, args):
        self.profile = a.load_profile()
        self.source = a.checked_path(args.existing)
        a.verify(self.profile, self.source)
        self.tool, game = a.checked_path(args.tact_tool), a.checked_path(args.game_root)
        pin = self.profile["tool"]["binary"]
        if self.tool.stat().st_size != pin["bytes"] or a.digest(self.tool.read_bytes()) != pin["sha256"]:
            a.fail("pinned-TACTTool-hash")
        if not (game/"Data").is_dir():
            a.fail("game-root-must-contain-Data")
        self.output = a.empty_output(args.output, (self.source, game, self.tool.parent, pathlib.Path(__file__).parent))
        self.arguments = [str(self.tool), "-d", str(game), "-p", self.profile["product"],
                          "-b", self.profile["buildConfig"], "-c", self.profile["cdnConfig"], "-l", "enUS"]
        self.files = {}
        self.old = {row["fileDataID"]: row for row in self.profile["files"]}

    def batch(self, layer, entries):
        selected = [(ident, name) for ident, name in sorted(set(entries)) if ident not in self.files]
        output = self.output if layer == "root" else self.output/layer
        output.mkdir(exist_ok=True)
        missing = []
        for ident, name in selected:
            if ident in self.old:
                old = self.old[ident]
                dest = output/name
                with a.asset_path(self.source, old).open("rb") as inp, dest.open("xb") as out:
                    shutil.copyfileobj(inp, out)
                self.register(ident, dest, layer, old["encodingKey"])
            else:
                missing.append((ident, name))
        if not missing:
            return
        self.extract(layer, output, missing)

    def extract(self, layer, output, missing, retry=True):
        listing = self.output/(layer+"-dependencies.list")
        listing.write_text("".join(f"{ident};{name}\n" for ident, name in missing), encoding="utf-8")
        logpath = self.output/(layer+"-extract.log")
        with logpath.open("xb") as log:
            result = subprocess.run(self.arguments+["-m", "list", "-i", str(listing), "-o", str(output)],
                                    cwd=self.output, stdout=log, stderr=subprocess.STDOUT, timeout=240)
        if result.returncode:
            a.fail("TACTTool-failed:"+layer)
        logs = logpath.read_text(encoding="utf-8", errors="replace")
        for ident, name in missing:
            keys = re.findall(r"Extracting ([a-f0-9]{32}) to "+re.escape(name)+r"(?:\r?\n|$)", logs)
            if len(keys) != 1:
                a.fail("missing-exact-encoding-key:"+name)
            if not (output/name).is_file():
                # Shared encoding keys can race in TACTTool's parallel download cache.
                # Retry missing outputs individually; keep the original extraction log.
                if not retry:
                    a.fail("missing-extracted-asset:"+name)
                retry_layer = layer+"-retry-"+str(ident)
                self.extract(retry_layer, output, [(ident, name)], retry=False)
                self.files[ident]["layer"] = layer
                continue
            self.register(ident, output/name, layer, keys[0])
        print(f"Acquired {layer}: {len(missing)} new assets", flush=True)

    def register(self, ident, path, layer, key):
        if not 0 < path.stat().st_size <= 4*1024*1024:
            a.fail("asset-size")
        data = path.read_bytes()
        if not 0 < len(data) <= 4*1024*1024:
            a.fail("asset-size")
        self.files[ident] = dict(fileDataID=ident, path=path.relative_to(self.output).as_posix(),
                                layer=layer, bytes=len(data), sha256=a.digest(data), encodingKey=key)
        if len(self.files) > self.max_files or sum(row["bytes"] for row in self.files.values()) > self.max_bytes:
            a.fail("acquisition-budget")

    def asset(self, ident):
        row = self.files[ident]
        return (self.output/row["path"]).read_bytes()


def terrain_sources(job, tiles=TILES):
    job.batch("root", [(775971, "Azeroth.69913.wdt")])
    raw = job.asset(775971)
    chunks = {tag: raw[start:end] for tag, start, end in t.chunks(raw)}
    if len(chunks["MAID"]) != 4096*32 or len(chunks["MAIN"]) != 4096*8:
        a.fail("WDT-layout")
    mapping, entries = [], []
    for x, y in tiles:
        refs = struct.unpack_from("<8I", chunks["MAID"], (y*64+x)*32)
        flags = struct.unpack_from("<II", chunks["MAIN"], (y*64+x)*8)
        if not flags[0] & 1 or not all(refs[:2]):
            a.fail("missing-source-tile")
        mapping.append(dict(tile=[x, y], MAIDIndex=y*64+x, rootFileDataID=refs[0], obj0FileDataID=refs[1]))
        entries.extend([(refs[0], f"Azeroth_{x}_{y}.69913.adt"), (refs[1], f"Azeroth_{x}_{y}_obj0.69913.adt")])
    job.batch("root", entries)
    return mapping


def collision_sources(job, mapping, predicate=relevant):
    placements = {}
    for row in mapping:
        rows, _, names = t.objects(job.asset(row["obj0FileDataID"]))
        if names:
            a.fail("legacy-name-references")
        for p in rows:
            key = (p["kind"], p["uniqueID"])
            if key in placements and placements[key] != p:
                a.fail("conflicting-placement")
            placements[key] = p
    selected = [p for p in placements.values() if predicate(p)]
    job.batch("collision", [(p["reference"], f'{p["reference"]}.bin') for p in selected])
    groups, doodads = set(), set()
    for p in selected:
        if p["kind"] != "wmo":
            continue
        try:
            root = w.root(job.asset(p["reference"]))
            _, indices = w.selected_doodads(root, p["doodadSet"])
        except ValueError as error:
            if str(error) not in ("WMO-LOD-or-group-count", "WMO-selected-set-range"):
                raise
            print(f"Retained unsupported root {p['reference']}: {error}; footprint must be excluded", flush=True)
            continue
        groups.update(root["groups"])
        doodads.update(root["doodads"][i]["reference"] for i in indices)
    job.batch("wmo-groups", [(ident, f"{ident}.bin") for ident in groups])
    job.batch("wmo-doodads", [(ident, f"{ident}.bin") for ident in doodads if ident])
    return len(placements), len(selected)


def receipts(job, mapping, counts):
    profile = copy.deepcopy(job.profile)
    profile["files"] = sorted(job.files.values(), key=lambda row: (row["layer"], row["fileDataID"]))
    profile["observedTiles"] = mapping
    profile["mappingEvidence"]["WDTTiles"] = mapping
    profile["navigationRegion"] = dict(regionID="dun-morogh-west-central-69913",
                                        tiles=[list(tile) for tile in TILES], navXZBounds=REGION)
    profile["limitations"] = ["Exact local source bytes, not native traversal proof.",
                               "Only explicit cropped west/central region; not all Dun Morogh.",
                               "Outside-region WMO placements excluded by raw MODF footprint; in-region unknowns stay explicit."]
    profile["acquisitionBounds"] = dict(maxFiles=MAX_FILES, maxBytes=MAX_BYTES, allPlacements=counts[0],
                                        selectedPlacements=counts[1])
    if a.digest(a.canonical(profile)) != west.PROFILE_SHA256:
        a.fail("west-acquisition-profile-pin")
    profile_path = job.output/"acquisition-profile-west.json"
    profile_path.write_text(json.dumps(profile, indent=2)+"\n", encoding="utf-8")
    # Receipts use the existing format; source pin explicitly names this newly acquired profile.
    a.PROFILE, a.PROFILE_HASH = profile_path, a.digest(a.canonical(profile))
    a.receipts(profile, job.output, "pinned-TACTTool-read-only-CASC-and-verified-reuse", job.source, job.tool)
    print(json.dumps(dict(output=str(job.output), files=len(job.files),
                          bytes=sum(r["bytes"] for r in job.files.values()), profileSHA256=a.PROFILE_HASH)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("existing", "game-root", "tact-tool", "output"):
        parser.add_argument("--"+name, required=True)
    job = Acquisition(parser.parse_args())
    mapping = terrain_sources(job)
    counts = collision_sources(job, mapping)
    receipts(job, mapping, counts)


if __name__ == "__main__":
    main()
