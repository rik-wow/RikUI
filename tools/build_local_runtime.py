"""Package licensed Windows build dependencies and authored local assembly tools.

No provider snapshot, generated quest data, extracted asset or generated mesh
can enter this allowlisted runtime payload. Ordinary users need no tool setup.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[1]
PYTHON_VERSION="3.13.9"
NODE_VERSION="24.3.0"
WHEELS={"lupa":"2.8","numpy":"2.4.2"}
READER_FILES=("src/js/db/WDCReader.js","src/js/db/DBDParser.js","src/js/db/FieldType.js",
              "src/js/db/CompressionType.js","src/js/buffer.js","src/js/crc32.js",
              "src/js/3D/loaders/M2Loader.js","src/js/3D/loaders/M2Generics.js","LICENSE")
TOP_TOOLS=("forever_inputs.py","current_refresh.py","source_archive.py","export_forever.py",
           "export_forever.lua","quest_corpus.py","client_db2.cjs","local_assembly.py","build_installer_bundle.py",
           "package_addon.py","update_quest_data.py","verify_current_m2.py","client_m2_probe.cjs","update_setup.py")
# Source modules can contain historical review evidence; acquisition/admission only
# uses current_acquisition and client_build. No acquisition profiles enter payloads.
METADATA=()
MAX_ARCHIVE=256*1024*1024


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def download(url):
    with urllib.request.urlopen(urllib.request.Request(url,headers={"User-Agent":"RikUI-runtime-build/1"}),timeout=90) as response:
        raw=response.read(MAX_ARCHIVE+1)
    if not raw or len(raw)>MAX_ARCHIVE:
        raise ValueError("Runtime dependency download bound")
    return raw


def unpack(raw,folder,prefix="",allow=None):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        total=0
        for row in archive.infolist():
            if row.is_dir():continue
            name=row.filename
            if prefix:
                if not name.startswith(prefix):raise ValueError("Dependency archive layout")
                name=name[len(prefix):]
            if not name or "\\" in name or ":" in name or ".." in Path(name).parts or Path(name).is_absolute():
                raise ValueError("Dependency archive path")
            if allow is not None and name not in allow:continue
            total+=row.file_size
            if total>512*1024*1024:raise ValueError("Dependency expansion bound")
            target=folder/name
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(archive.read(row))


def build(reader,extractor,output):
    output=Path(output).absolute()
    if output.exists():raise ValueError("Runtime output must be a new directory")
    reader,extractor=Path(reader).resolve(),Path(extractor).resolve()
    sys.path.insert(0,str(ROOT/"tools/terrain"))
    from current_acquisition import EXTRACTOR_SHA256
    if sha(extractor.read_bytes())!=EXTRACTOR_SHA256:raise ValueError("Extractor dependency hash")
    revision=subprocess.check_output(["git","-C",str(reader),"rev-parse","HEAD"],text=True).strip()
    if subprocess.check_output(["git","-C",str(reader),"status","--porcelain","--untracked-files=no"],text=True).strip():
        raise ValueError("DB2 reader source must be clean")
    output.mkdir(parents=True)
    runtime=output/"runtime";runtime.mkdir()
    provenance=[]
    py_url="https://www.python.org/ftp/python/"+PYTHON_VERSION+"/python-"+PYTHON_VERSION+"-embed-amd64.zip"
    raw=download(py_url);unpack(raw,runtime/"python")
    provenance.append(dict(name="Python",version=PYTHON_VERSION,url=py_url,sha256=sha(raw),license="PSF"))
    pth=runtime/"python/python313._pth"
    pth.write_text("python313.zip\n.\nsite-packages\n../tools\n../tools/terrain\nimport site\n",encoding="utf-8")
    # Publisher hashes bind the exact Node archive before it is packaged.
    node_name="node-v"+NODE_VERSION+"-win-x64.zip"
    base="https://nodejs.org/dist/v"+NODE_VERSION+"/"
    sums=download(base+"SHASUMS256.txt").decode()
    expected=next(line.split()[0] for line in sums.splitlines() if line.split()[-1]==node_name)
    raw=download(base+node_name)
    if sha(raw)!=expected:raise ValueError("Node publisher checksum")
    unpack(raw,runtime/"node","node-v"+NODE_VERSION+"-win-x64/",allow={"node.exe","LICENSE"})
    provenance.append(dict(name="Node",version=NODE_VERSION,url=base+node_name,sha256=expected,license="MIT and bundled notices"))
    site=runtime/"python/site-packages";site.mkdir()
    for name,version in WHEELS.items():
        metadata=json.loads(download("https://pypi.org/pypi/"+name+"/"+version+"/json"))
        wheel=next(row for row in metadata["urls"] if row["filename"].endswith("cp313-cp313-win_amd64.whl"))
        raw=download(wheel["url"])
        if sha(raw)!=wheel["digests"]["sha256"]:raise ValueError("Wheel publisher checksum")
        unpack(raw,site)
        provenance.append(dict(name=name,version=version,url=wheel["url"],sha256=sha(raw),
                               license=metadata["info"].get("license_expression") or metadata["info"].get("license")))
    tool=runtime/"extractor";tool.mkdir()
    shutil.copyfile(extractor,tool/"TACTTool.exe")
    license_raw=download("https://raw.githubusercontent.com/wowdev/TACTSharp/c12f9fa3c4ceeb619b0453947cee86fccad6774a/LICENSE")
    (tool/"LICENSE.txt").write_bytes(license_raw)
    provenance.append(dict(name="TACTSharp",version="0.2.0-alpha1",sha256=EXTRACTOR_SHA256,license="MIT",
                           source="https://github.com/wowdev/TACTSharp"))
    for name in READER_FILES:
        target=runtime/"reader"/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(reader/name,target)
    provenance.append(dict(name="wow.export DB2 reader",revision=revision,license="MIT",
                           source="https://github.com/Kruithne/wow.export"))
    for name in TOP_TOOLS:
        target=runtime/"tools"/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/"tools"/name,target)
    shutil.copyfile(ROOT/"tests/check_manifest.py",runtime/"tools/check_manifest.py")
    terrain=runtime/"tools/terrain";terrain.mkdir()
    for path in (ROOT/"tools/terrain").iterdir():
        if path.is_file() and ((path.suffix in (".py",".mjs") and not path.name.startswith("test_")) or path.name in METADATA):
            shutil.copyfile(path,terrain/path.name)
    shutil.copytree(ROOT/"tools/terrain/licenses",terrain/"licenses")
    shutil.copytree(ROOT/"tools/terrain/node_modules",terrain/"node_modules",
                    ignore=shutil.ignore_patterns(".cache","__pycache__"))
    shutil.copyfile(ROOT/"LICENSE",runtime/"LICENSE.txt")
    inventory=[]
    for path in sorted(runtime.rglob("*")):
        if path.is_symlink() or (hasattr(path,"is_junction") and path.is_junction()):raise ValueError("Linked runtime file")
        if path.is_file():
            raw=path.read_bytes()
            inventory.append(dict(path=path.relative_to(runtime).as_posix(),bytes=len(raw),sha256=sha(raw)))
    manifest=dict(format="rikui-local-runtime-v1",dependencies=provenance,files=inventory)
    (runtime/"runtime.json").write_text(json.dumps(manifest,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    target=output/"runtime.zip"
    with zipfile.ZipFile(target,"x",compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for path in sorted(runtime.rglob("*")):
            if path.is_file():
                info=zipfile.ZipInfo(path.relative_to(runtime).as_posix(),date_time=(1980,1,1,0,0,0))
                info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
                archive.writestr(info,path.read_bytes())
    result=dict(archive=str(target),sha256=sha(target.read_bytes()),bytes=target.stat().st_size,
                files=len(inventory),dependencies=provenance)
    (output/"runtime-build.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    return result


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("reader","extractor","output"):parser.add_argument("--"+name,required=True)
    args=parser.parse_args()
    print(json.dumps(build(args.reader,args.extractor,args.output),indent=2))
