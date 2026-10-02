"""Verify and stage exact-current private corpus inputs, without historical road caches."""
import json, shutil
from pathlib import Path
from provenance import digest
def verified_source(root, client):
    root=Path(root).resolve()
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    catalog=json.loads((root/"catalog.json").read_text(encoding="utf-8"))
    expected={"product":"forever","build":client["version"],"locale":"enUS"}
    if manifest.get("identity")!=expected or catalog.get("identity")!=expected:
        raise RuntimeError("Corpus identity is not the verified current client")
    if manifest.get("clientIndex",{}).get("build")!=client["version"]:
        raise RuntimeError("Corpus client membership provenance is missing")
    for name,row in manifest["files"].items():
        path=root/name
        if root not in path.resolve().parents or not path.is_file() or digest(path)!=row["sha256"]:
            raise RuntimeError("Corpus input changed: "+name)
    source=root/"generated/corpus"
    if not (source/"corpus.xml").is_file():raise RuntimeError("Current corpus include missing")
    return source
def stage(source, destination):
    destination=Path(destination)
    if destination.exists():shutil.rmtree(destination)
    if source is not None:shutil.copytree(source,destination)
