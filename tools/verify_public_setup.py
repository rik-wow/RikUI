"""Verify downloaded setup artifacts, every checksum and the executable payload."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import forever_inputs as current

FILES=("RikUI-Setup.exe","RikUI-Setup-manifest.json","RikUI-Setup-NOTICES.txt")


def digest(path):
    with current.regular(path).open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def verify(directory,version,proof):
    directory=Path(directory).resolve()
    sums=current.regular(directory/"RikUI-Setup-SHA256SUMS").read_text(encoding="utf-8")
    entries={}
    for line in sums.splitlines():
        match=re.fullmatch(r"([a-f0-9]{64})  (RikUI-Setup[^/\\]+)",line)
        if not match or match[2] in entries:raise ValueError("Invalid published checksum inventory")
        entries[match[2]]=match[1]
    if set(entries)!=set(FILES):raise ValueError("Incomplete published checksum inventory")
    for name,sha in entries.items():
        if digest(directory/name)!=sha:raise ValueError("Published checksum mismatch: "+name)
    manifest=json.loads(current.read_metadata(directory/"RikUI-Setup-manifest.json"))
    if (manifest.get("format")!="rikui-public-installer-v1" or manifest.get("version")!=version
            or manifest.get("importedDatasetsIncluded") is not False
            or manifest.get("clientGeometryIncluded") is not False):
        raise ValueError("Published setup version or data boundary mismatch")
    artifact=manifest["artifact"]
    program=current.regular(directory/"RikUI-Setup.exe")
    if (artifact["filename"]!=program.name or artifact["bytes"]!=program.stat().st_size
            or artifact["sha256"]!=entries[program.name]
            or artifact["url"]!=f"https://github.com/rik-wow/RikUI/releases/download/v{version}/RikUI-Setup.exe"):
        raise ValueError("Published artifact manifest mismatch")
    if not 0<program.stat().st_size<=256*1024**2:raise ValueError("Published program size bound")
    if not 0<(directory/FILES[2]).stat().st_size<=4*1024**2:raise ValueError("Published notices missing or oversized")
    proof=Path(proof).absolute()
    if proof.exists():raise ValueError("Choose a new retained proof directory")
    proof.mkdir(parents=True)
    output=proof/"embedded.json"
    subprocess.run([str(program),"--verify-package",str(output)],check=True,timeout=120,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name=="nt" else 0)
    embedded=json.loads(output.read_bytes())
    expected=dict(format="rikui-embedded-package-proof-v1",version=version,
        programSHA256=entries[program.name],baseSHA256=manifest["baseSHA256"],
        runtimeSHA256=manifest["embeddedRuntimeSHA256"],runtimeManifestSHA256=manifest["runtimeManifestSHA256"])
    if any(embedded.get(key)!=value for key,value in expected.items()):
        raise ValueError("Downloaded executable embedded payload mismatch")
    result=dict(format="rikui-published-setup-verification-v1",version=version,
        directory=str(directory),checksums=entries,embedded=embedded,
        importedDatasetsIncluded=False,clientGeometryIncluded=False)
    (proof/"evidence.json").write_bytes(current.canonical(result)+b"\n")
    return result


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("directory","version","proof"):parser.add_argument("--"+name,required=True)
    args=parser.parse_args()
    print(json.dumps(verify(args.directory,args.version,args.proof)))
