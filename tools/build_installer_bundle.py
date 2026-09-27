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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, help="Verified private quest-data.zip")
    parser.add_argument("--local-roads", type=Path, help="Existing AddOns folder; preserves all input data")
    args = parser.parse_args()
    print(json.dumps(build(args.version, args.output, args.corpus, args.local_roads), indent=2))
