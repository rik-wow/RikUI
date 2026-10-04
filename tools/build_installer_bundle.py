"""Build a deterministic all-in-one installer payload without changing installed data."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tempfile
import zipfile

import package_addon
import quest_corpus
from update_quest_data import unpack

ROOT = Path(__file__).resolve().parents[1]


def add_tree(files, source, prefix):
    source = Path(source)
    for path in sorted(source.rglob("*")):
        if path.is_symlink() or getattr(path, "is_junction", lambda: False)():
            raise ValueError("Reparse point in data input: " + str(path))
        if path.is_file():
            name = prefix + path.relative_to(source).as_posix()
            package_addon.install_path(name)
            if name in files:
                raise ValueError("Duplicate payload: " + name)
            files[name] = path.read_bytes()


def build(version, output, corpus=None, addons=None):
    files = package_addon.payload(ROOT, version)
    components = ["RikUI interface"]
    if corpus:
        with tempfile.TemporaryDirectory(prefix="rikui-bundle-corpus-") as folder:
            folder = Path(folder)
            unpack(corpus, folder)
            manifest = quest_corpus.verify(folder)
            add_tree(files, folder / "generated/corpus", "RikUI/generated/corpus/")
            components.append("quest corpus " + manifest["corpusRevision"][:12])
    if addons:
        addons = Path(addons)
        roads = addons / "RikUI/generated/roads"
        if not roads.is_dir():
            raise ValueError("Missing generated road data")
        add_tree(files, roads, "RikUI/generated/roads/")
        packs = sorted(p for p in addons.iterdir() if re.fullmatch(r"RikUIQuestRoads_W[0-9]+_P[0-9]{3}", p.name))
        if not packs:
            raise ValueError("Missing road patch packs")
        for pack in packs:
            add_tree(files, pack, pack.name + "/")
        components.append("local road data (" + str(len(packs)) + " patch packs)")
    return write_payload(version, output, files, components)


def write_payload(version, output, files, components):
    metadata = {"format": 1, "version": version, "components": components, "files": {
        name: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        for name, data in sorted(files.items())}}
    if sum(len(data) for data in files.values()) > 2 * 1024 ** 3:
        raise ValueError("Payload exceeds installer size limit")
    files["bundle.json"] = (json.dumps(metadata, sort_keys=True, indent=2) + "\n").encode()
    output = Path(output)
    if output.exists():
        raise ValueError("Output exists; choose a new bundle filename")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as stream, zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    return {"path": str(output), "bytes": output.stat().st_size,
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "components": components}


def verify_bundle(path, public=False):
    """Validate every archived byte before admitting a resumed local payload."""
    with zipfile.ZipFile(path) as archive:
        entries=archive.infolist()
        names=[entry.filename for entry in entries]
        if (len(entries)>65536 or len(names)!=len(set(name.casefold() for name in names))
                or sum(entry.file_size for entry in entries)>2*1024**3):
            raise ValueError("Bundle inventory bound or duplicate")
        for entry in entries:
            mode=entry.external_attr>>16
            if (entry.orig_filename!=entry.filename or entry.is_dir() or entry.flag_bits&1
                    or mode&0o170000 not in (0,0o100000)):
                raise ValueError("Invalid bundle archive member")
            if entry.filename!="bundle.json":
                package_addon.install_path(entry.filename)
                root=entry.filename.split("/")[0]
                if (not entry.filename.isascii() or "/" not in entry.filename
                        or not re.fullmatch(r"RikUI|RikUIQuestRoads_W[0-9]+_P[0-9]{3}",root)):
                    raise ValueError("Unexpected bundle addon path")
        if "bundle.json" not in names or archive.getinfo("bundle.json").file_size>16*1024**2:
            raise ValueError("Missing or oversized bundle manifest")
        metadata=json.loads(archive.read("bundle.json"))
        if (set(metadata)!={"format","version","components","files"} or metadata["format"]!=1
                or not isinstance(metadata["version"],str) or not 0<len(metadata["version"])<=64
                or not isinstance(metadata["components"],list) or not isinstance(metadata["files"],dict)
                or set(names)!={"bundle.json",*metadata["files"]}):
            raise ValueError("Invalid bundle manifest")
        folded=set(name.casefold() for name in names)
        for name,row in metadata["files"].items():
            package_addon.install_path(name)
            if public and name.startswith(("RikUI/generated/corpus/","RikUI/generated/roads/","RikUIQuestRoads_")):
                raise ValueError("Public base must exclude imported data")
            if set(row)!={"bytes","sha256"} or archive.getinfo(name).file_size!=row["bytes"]:
                raise ValueError("Bundle entry size mismatch")
            for parent in Path(name).parents:
                if parent.as_posix().casefold() in folded:raise ValueError("Bundle file/directory collision")
            with archive.open(name) as stream:
                actual=hashlib.file_digest(stream,"sha256").hexdigest()
            if actual!=row["sha256"]:raise ValueError("Bundle entry checksum mismatch")
        for name in ("RikUI/RikUI.toc","RikUI/LICENSE","RikUI/generated/index.xml"):
            if name not in metadata["files"]:raise ValueError("Missing required bundle file")
        return metadata


def assemble_local(base_bundle, corpus, roads, output):
    """Consumer-side payload only; never a public release artifact."""
    verify_bundle(base_bundle,public=True)
    raw=Path(base_bundle).read_bytes()
    with zipfile.ZipFile(__import__("io").BytesIO(raw)) as archive:
        names=archive.namelist()
        if len(names)!=len(set(name.casefold() for name in names)):
            raise ValueError("Duplicate base payload")
        metadata=json.loads(archive.read("bundle.json"))
        files={}
        for name,row in metadata["files"].items():
            package_addon.install_path(name)
            body=archive.read(name)
            if len(body)!=row["bytes"] or hashlib.sha256(body).hexdigest()!=row["sha256"]:
                raise ValueError("Base payload hash mismatch")
            if name.startswith(("RikUI/generated/corpus/","RikUI/generated/roads/","RikUIQuestRoads_")):
                raise ValueError("Public base must exclude imported data")
            files[name]=body
        if set(names)!={"bundle.json",*files}:
            raise ValueError("Uninventoried base payload")
    corpus_manifest=quest_corpus.verify(corpus)
    add_tree(files,Path(corpus)/"generated/corpus","RikUI/generated/corpus/")
    from terrain.install_roads import source_pack, digest
    roads=Path(roads)
    road_hash=digest((roads/"road-network-receipt.json").read_bytes())
    _,_,packs=source_pack(roads,road_hash)
    add_tree(files,roads/"generated/roads","RikUI/generated/roads/")
    for pack in sorted(packs):add_tree(files,roads/pack,pack+"/")
    return write_payload(metadata["version"],output,files,
                         ["RikUI interface","locally assembled quest guide","locally assembled navigation"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, help="Verified private quest-data.zip")
    parser.add_argument("--local-roads", type=Path, help="Existing AddOns folder; preserves all input data")
    args = parser.parse_args()
    print(json.dumps(build(args.version, args.output, args.corpus, args.local_roads), indent=2))
