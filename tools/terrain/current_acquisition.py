"""Discover and acquire current client topology and geometry into a private local job.

All bytes are freshly extracted under resolved product/configuration. Historical
acquisitions are not read. Unsupported maps/dependencies are explicit coverage.
"""
from __future__ import annotations
import argparse
import csv
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time
import urllib.request

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import forever_inputs as current
import terrain_probe
import wmo_probe

TABLES = ("Map", "UiMap", "UiMapAssignment", "LiquidType", "QuestV2",
          "TaxiNodes", "TaxiPath", "TaxiPathNode", "AreaTrigger", "TransportAnimation")
MAX_ASSETS = 32768
MAX_BYTES = 64 * 1024 * 1024
EXTRACTOR_SHA256 = "efbcf7c018310719328ca3cf101d366195a1d96d7fbc07871bdff70d88fe1945"


def atomic(path, value):
    target = Path(path)
    temporary = target.with_suffix(target.suffix + ".next")
    temporary.write_bytes(current.canonical(value) + b"\n")
    temporary.replace(target)


def topology(raw, world, ident):
    parts = {}
    for tag, a, b in terrain_probe.chunks(raw):
        if tag in parts:
            raise ValueError("Duplicate topology chunk")
        parts[tag] = raw[a:b]
    if (parts.get("MVER") != struct.pack("<I", 18)
            or len(parts.get("MPHD", b"")) != 32
            or struct.unpack_from("<I", parts["MPHD"])[0] & 1
            or parts.get("MODF") or parts.get("MWMO")):
        raise ValueError("Unsupported global-WMO or WDT framing")
    if len(parts.get("MAIN", b"")) != 32768 or len(parts.get("MAID", b"")) != 131072:
        raise ValueError("Unsupported MAIN/MAID framing")
    tiles = []
    for index in range(4096):
        active = bool(struct.unpack_from("<I", parts["MAIN"], index * 8)[0] & 1)
        refs = struct.unpack_from("<8I", parts["MAID"], index * 32)
        if active != bool(refs[0]):
            raise ValueError("MAIN/MAID disagree")
        if active:
            if not refs[1]:
                raise ValueError("Active tile lacks object data")
            tiles.append(dict(worldMapID=world, x=index % 64, y=index // 64,
                              rootADT=refs[0], obj0ADT=refs[1], tex0ADT=refs[3]))
    return tiles


class Acquisition:
    def __init__(self, executable, extractor, reader, output):
        self.resolution = current.discover(executable)
        self.output = Path(output).absolute()
        if self.output.exists():
            raise ValueError("Use a new acquisition directory; existing local data is preserved")
        self.tool = current.regular(extractor)
        if current.sha(self.tool.read_bytes()) != EXTRACTOR_SHA256:
            raise ValueError("Extractor differs from licensed/reviewed dependency")
        self.reader = Path(reader).absolute()
        self.node = os.environ.get("RIKUI_NODE") or shutil.which("node")
        if not self.node:
            raise ValueError("Packaged Node runtime missing")
        if not (self.reader / "src/js/db/WDCReader.js").is_file():
            raise ValueError("Separately acquired supported DB2 reader required")
        parent = self.output.parent
        while not parent.exists():
            parent = parent.parent
        if shutil.disk_usage(parent).free < 8 * 1024 ** 3:
            raise ValueError("Current acquisition requires at least 8 GiB free disk space")
        game = Path(self.resolution["installation"]["storageRoot"])
        if self.output.is_relative_to(game) or game.is_relative_to(self.output):
            raise ValueError("Acquisition output must not overlap the client")
        self.output.mkdir(parents=True)
        current.save_resolution(self.output / "resolution.json", self.resolution)
        self.rows, self.paths, self.missing, self.batches = {}, {}, [], 0
        self.start = time.monotonic()

    def cancelled(self):
        if (self.output / "cancel").exists():
            raise InterruptedError("Acquisition cancelled; current files preserved for inspection")

    def extract(self, identifiers, names=False):
        identity = self.resolution["inputs"]["identity"]
        for at in range(0, len(identifiers), 128):
            self.cancelled()
            if shutil.disk_usage(self.output).free<4*1024**3:
                raise ValueError("Less than 4 GiB remains on the acquisition drive. Existing data is retained; free space and retry.")
            self.batches += 1
            folder = self.output / ("extract-%04d" % self.batches)
            folder.mkdir()
            listing = folder / "files.list"
            listing.write_text("".join(str(value) + ";" + (str(value) + ".bin" if not names else
                               str(value).rsplit("/", 1)[-1]) + "\n"
                               for value in identifiers[at:at + 128]), encoding="utf-8")
            arguments = [str(self.tool), "-d", self.resolution["installation"]["storageRoot"],
                         "-p", identity["product"], "-b", identity["buildConfig"],
                         "-c", identity["cdnConfig"], "-l", "enUS",
                         "-m", "list", "-i", str(listing), "-o", str(folder / "assets")]
            with (folder / "extract.log").open("wb") as log:
                process = subprocess.Popen(arguments, cwd=folder, stdout=log,
                    stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                try:
                    deadline = time.monotonic() + 600
                    while process.poll() is None:
                        self.cancelled()
                        if time.monotonic() > deadline:
                            raise TimeoutError("Extractor batch timed out")
                        time.sleep(.1)
                except BaseException:
                    process.kill()
                    process.wait()
                    raise
            # TACTTool may return success despite absent inputs; inventory every file.
            for value in identifiers[at:at + 128]:
                name = str(value).rsplit("/", 1)[-1] if names else str(value) + ".bin"
                path = folder / "assets" / (str(value) if names else name)
                if path.is_file() and 0 < path.stat().st_size <= MAX_BYTES:
                    self.paths[value] = path
                else:
                    self.missing.append(value)
            if process.returncode:
                raise ValueError("Extractor batch failed; see " + str(folder / "extract.log"))
            atomic(self.output / "acquisition-progress.json",
                   dict(phase="extract",files=len(self.paths),missing=self.missing,
                        seconds=round(time.monotonic()-self.start, 1)))
            print(json.dumps(dict(phase="extract", files=len(self.paths), missing=len(self.missing))),flush=True)

    def tables(self):
        self.extract(["DBFilesClient/" + table + ".db2" for table in TABLES], names=True)
        folder = self.output / "db2"
        folder.mkdir()
        revision = self.resolution["inputs"]["sources"]["schemas"]["revision"]
        for table in TABLES:
            key = "DBFilesClient/" + table + ".db2"
            if key not in self.paths:
                raise ValueError("Required current client table unavailable: " + table)
            shutil.copyfile(self.paths[key], folder / (table + ".db2"))
            raw = current.download("https://raw.githubusercontent.com/wowdev/WoWDBDefs/"
                                   + revision + "/definitions/" + table + ".dbd")
            (folder / (table + ".dbd")).write_bytes(raw)
        subprocess.run([self.node, str(TOOLS / "client_db2.cjs"), str(self.reader), str(folder),
                        self.resolution["inputs"]["identity"]["build"], revision, *TABLES], check=True,timeout=180)
        self.table_receipt = json.loads((folder / "db2-inputs.json").read_bytes())
        return folder

    def want(self, ident, kind, world, tile=None):
        if type(ident) is not int or not 0 < ident < 2**31:
            raise ValueError("Invalid file data ID")
        row = self.rows.setdefault(ident,dict(fileDataID=ident,kind=kind,worldMapIDs=[]))
        if row["kind"] != kind:
            raise ValueError("Conflicting dependency kinds")
        row["worldMapIDs"] = sorted(set(row["worldMapIDs"] + [world]))
        if tile is not None:
            if row.get("tile",tile) != tile:
                raise ValueError("Conflicting tile namespace")
            row["tile"] = tile
        if len(self.rows) > MAX_ASSETS:
            raise ValueError("Geometry dependency inventory exceeds supported bound")

    def ensure(self):
        identifiers = sorted(set(self.rows)-set(self.paths)-set(self.missing))
        if identifiers:
            self.extract(identifiers)

    def run(self):
        db2 = self.tables()
        build = self.resolution["inputs"]["identity"]["build"]
        def rows(table):
            with (db2 / (table + "-" + build + ".csv")).open(encoding="utf-8-sig",newline="") as stream:
                return list(csv.DictReader(stream))
        maps = {int(row["ID"]):row for row in rows("Map")}
        worlds = sorted({int(row["MapID"]) for row in rows("UiMapAssignment")})
        self.extract(sorted({int(maps[world]["WdtFileDataID"]) for world in worlds
                             if int(maps[world]["WdtFileDataID"]) > 0}))
        tiles, evidence, gaps = [], [], []
        for world in worlds:
            ident = int(maps[world]["WdtFileDataID"])
            if ident not in self.paths:
                gaps.append(dict(worldMapID=world,reason="current topology unavailable"))
                continue
            path = self.paths[ident]
            try:
                selected = topology(path.read_bytes(), world, ident)
            except ValueError as error:
                gaps.append(dict(worldMapID=world,reason=str(error)))
                continue
            evidence.append(dict(worldMapID=world,fileDataID=ident,path=str(path),
                                 sha256=current.sha(path.read_bytes()),tiles=len(selected)))
            tiles.extend(selected)
        for row in tiles:
            for kind in ("rootADT", "obj0ADT", "tex0ADT"):
                if row[kind]:
                    self.want(row[kind],kind,row["worldMapID"],[row["x"],row["y"]])
        self.ensure()
        for row in list(self.rows.values()):
            if row["kind"] != "obj0ADT" or row["fileDataID"] not in self.paths:
                continue
            placed, _, names = terrain_probe.objects(self.paths[row["fileDataID"]].read_bytes())
            if names:
                raise ValueError("Current named ADT placements unsupported")
            for item in placed:
                for world in row["worldMapIDs"]:
                    self.want(item["reference"],"M2" if item["kind"]=="m2" else "WMO",world)
        self.ensure()
        for row in list(self.rows.values()):
            if row["kind"] != "WMO" or row["fileDataID"] not in self.paths:
                continue
            root = wmo_probe.root(self.paths[row["fileDataID"]].read_bytes())
            for world in row["worldMapIDs"]:
                for ident in root["groups"]:
                    self.want(ident,"WMOGroup",world)
                for item in root["doodads"]:
                    self.want(item["reference"],"M2",world)
        self.ensure()
        if current.discover(self.resolution["installation"]["executable"])["fingerprint"] != self.resolution["fingerprint"]:
            raise ValueError("Upstream or selected client changed during acquisition; do not admit outputs")
        records = []
        for ident,row in sorted(self.rows.items()):
            if ident in self.paths:
                path=self.paths[ident]
                records.append(dict(row,path=str(path),bytes=path.stat().st_size,sha256=current.sha(path.read_bytes())))
            else:
                gaps.append(dict(fileDataID=ident,kind=row["kind"],worldMapIDs=row["worldMapIDs"],
                                 reason="current dependency unavailable"))
        if self.missing:
            # Never admit a source inventory with unknown geometry holes.
            atomic(self.output/"coverage-failure.json",dict(gaps=gaps,missing=self.missing))
            raise ValueError("Current dependencies unavailable; see coverage-failure.json; prior data preserved")
        profile=dict(format="rikui-forever-world-acquisition-profile-v1",
                     identity=dict(self.resolution["inputs"]["identity"],locale="enUS"),
                     files=[r for r in records if r["kind"]!="tex0ADT"],nativeVerified=False)
        atomic(self.output/"acquisition-profile.json",profile)
        import verify_current_m2
        model_proof=verify_current_m2.build(self.reader,self.output/"acquisition-profile.json",self.output/"current-m2-proof.json")
        tilefile=db2/"all-projected-world-tile-worklist.csv"
        with tilefile.open("x",newline="",encoding="utf-8") as stream:
            writer=csv.DictWriter(stream,fieldnames=["worldMapID","x","y","rootADT","obj0ADT","tex0ADT"])
            writer.writeheader();writer.writerows(tiles)
        atomic(db2/"inventory.json",dict(topologyEvidence=evidence,gaps=gaps))
        atomic(self.output/"tex0-manifest.json",dict(files=[
            dict(path=str(Path(r["path"]).relative_to(self.output)),worldMapID=r["worldMapIDs"][0],
                 tile=r["tile"],fileDataID=r["fileDataID"],sha256=r["sha256"]) for r in records if r["kind"]=="tex0ADT"]))
        kinds={str(int(row["ID"])):{0:"water",1:"ocean",2:"magma",3:"slime"}.get(int(row["SoundBank"]),"unknown")
               for row in rows("LiquidType")}
        atomic(db2/"liquid-kinds.json",dict(kinds=kinds))
        receipt=dict(format="rikui-current-navigation-inputs-v1",resolution=self.resolution,
                     identity=profile["identity"],sourceHashes={k:self.table_receipt["tables"][k]["csvSHA256"]
                     for k in ("Map","UiMap","UiMapAssignment","LiquidType","QuestV2")},
                     tileWorklistSHA256=current.sha(tilefile.read_bytes()),
                     topology={str(r["worldMapID"]):[r["fileDataID"],r["sha256"]] for r in evidence},
                     liquidKindsSHA256=current.sha((db2/"liquid-kinds.json").read_bytes()),
                     sourceDirectory=str(db2),profileSHA256=current.sha((self.output/"acquisition-profile.json").read_bytes()),
                     m2Proof=dict(path=str(self.output/"current-m2-proof.json"),sha256=model_proof["sha256"]),
                     extractorSHA256=EXTRACTOR_SHA256,gaps=gaps,
                     seconds=round(time.monotonic()-self.start,1),files=len(records),tiles=len(tiles))
        atomic(self.output/"current-inputs.json",receipt)
        print(json.dumps(dict(phase="acquired",files=len(records),tiles=len(tiles),gaps=gaps,
                             seconds=receipt["seconds"],receipt=str(self.output/"current-inputs.json"))),flush=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("executable","extractor","reader","output"):
        parser.add_argument("--"+name,required=True)
    parser.add_argument("--tables-only",action="store_true")
    args=parser.parse_args()
    job=Acquisition(args.executable,args.extractor,args.reader,args.output)
    if args.tables_only:
        job.tables()
    else:
        job.run()
