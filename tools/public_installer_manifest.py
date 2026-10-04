"""Manifest and notices for public setup; local guide data cannot enter these files."""
import argparse
import hashlib
import json
import subprocess
import tempfile
import os
from pathlib import Path
import build_installer_bundle as bundle
import package_addon
import current_refresh
import forever_inputs as current

def create(version, program, base, runtime, output):
    package_addon.validate_version(version)
    bundle.verify_bundle(current.regular(base),public=True)
    runtime=Path(runtime)
    manifest=json.loads((runtime/"runtime.json").read_bytes())
    current_refresh.verify_files(runtime,manifest["files"])
    for row in manifest["files"]:
        path=row["path"]
        if not path.startswith(("python/","node/","extractor/","reader/","tools/")) and path!="LICENSE.txt":
            raise ValueError("Unexpected public runtime path")
        if path.endswith((".sqlite",".bin",".adt",".db2",".csv",".npy",".pickle")) and not (path.startswith("python/site-packages/numpy/") and "/tests/data/" in path):
            raise ValueError("Data file in public preparation runtime")
    program=current.regular(program)
    if not 0<program.stat().st_size<=256*1024**2:raise ValueError("Public program byte bound")
    with program.open("rb") as stream:sha=hashlib.file_digest(stream,"sha256").hexdigest()
    base_sha=hashlib.sha256(Path(base).read_bytes()).hexdigest()
    runtime_sha=hashlib.sha256((runtime/"runtime.json").read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="rikui-public-proof-") as proof_folder:
        proof=Path(proof_folder)/"package.json"
        subprocess.run([str(program.resolve()),"--verify-package",str(proof)],check=True,timeout=120,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name=="nt" else 0)
        verified=json.loads(proof.read_bytes())
        expected=dict(format="rikui-embedded-package-proof-v1",version=version,programSHA256=sha,
                      baseSHA256=base_sha,runtimeManifestSHA256=runtime_sha,runtimeFiles=len(manifest["files"]))
        if any(verified.get(key)!=value for key,value in expected.items()):
            raise ValueError("Executable embedded package does not match reviewed public inputs")
    value=dict(format="rikui-public-installer-v1",version=version,
        artifact=dict(filename="RikUI-Setup.exe",bytes=program.stat().st_size,sha256=sha,
            url=f"https://github.com/rik-wow/RikUI/releases/download/v{version}/RikUI-Setup.exe"),
        baseSHA256=base_sha,runtimeManifestSHA256=runtime_sha,
        embeddedRuntimeSHA256=verified["runtimeSHA256"],
        included="RikUI interface, licensed preparation tools and notices; guide and navigation generated locally",
        importedDatasetsIncluded=False,clientGeometryIncluded=False,
        dependencies=manifest["dependencies"])
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    target=output/"RikUI-Setup-manifest.json"
    target.write_bytes(current.canonical(value)+b"\n")
    sums=output/"RikUI-Setup-SHA256SUMS"
    notices=["RikUI preparation dependency notices","\nAll imported quest information and extracted client geometry remain separate local inputs.\n"]
    for row in manifest["dependencies"]:notices.append(json.dumps(row,sort_keys=True))
    for path in sorted(runtime.rglob("*")):
        if path.is_file() and ("license" in path.name.lower() or path.name.upper() in ("COPYING","NOTICE")):
            if path.stat().st_size>1024**2:raise ValueError("Notice byte bound")
            notices.extend(["\n--- "+path.relative_to(runtime).as_posix()+" ---\n",path.read_text(encoding="utf-8",errors="replace")])
    notice_file=output/"RikUI-Setup-NOTICES.txt"
    notice_file.write_text("\n".join(notices)+"\n",encoding="utf-8")
    sums.write_text(f"{sha}  RikUI-Setup.exe\n{hashlib.sha256(target.read_bytes()).hexdigest()}  {target.name}\n"
                    f"{hashlib.sha256(notice_file.read_bytes()).hexdigest()}  {notice_file.name}\n",encoding="utf-8")
    return value

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("version","program","base","runtime","output"):parser.add_argument("--"+name,required=True)
    args=parser.parse_args();print(json.dumps(create(args.version,args.program,args.base,args.runtime,args.output)))
