"""Release-build dependencies only; never acquires provider or client datasets."""
import argparse
import json
from pathlib import Path
import subprocess
import build_local_runtime as runtime
import forever_inputs as current

READER_REVISION="51c57c6862f2fa059d18d613744260321d27c2bc"
EXTRACTOR_ARCHIVE_SHA256="3bcb6bfd29d5f9a56f9e6ceaa97009894ab0dbba9451bf24ba915226eb27ddd9"
EXTRACTOR_URL="https://github.com/wowdev/TACTSharp/releases/download/0.2.0-alpha1/TACTTool-Release-win-x64.zip"

def acquire(output):
    output=Path(output).absolute()
    if output.exists():raise ValueError("Dependency output must be new")
    # Resolve current client metadata before building; this is not client testing.
    sources=current.resolve_upstreams()
    output.mkdir(parents=True)
    reader=output/"reader"
    subprocess.run(["git","clone","--no-checkout","https://github.com/Kruithne/wow.export.git",str(reader)],check=True,timeout=180)
    # The reviewed reader hashes include its Windows checkout line endings.
    subprocess.run(["git","-C",str(reader),"config","core.autocrlf","true"],check=True,timeout=30)
    subprocess.run(["git","-C",str(reader),"checkout","--detach",READER_REVISION],check=True,timeout=60)
    raw=runtime.download(EXTRACTOR_URL)
    if runtime.sha(raw)!=EXTRACTOR_ARCHIVE_SHA256:raise ValueError("Extractor publisher archive changed")
    runtime.unpack(raw,output/"extractor",allow={"TACTTool.exe"})
    result=dict(reader=str(reader),extractor=str(output/"extractor/TACTTool.exe"),
                reviewedReaderRevision=READER_REVISION,extractorArchiveSHA256=EXTRACTOR_ARCHIVE_SHA256,
                currentMetadata=sources,clientTested=False)
    (output/"dependency-receipt.json").write_bytes(current.canonical(result)+b"\n")
    return result

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--output",required=True)
    args=parser.parse_args();print(json.dumps(acquire(args.output)))
