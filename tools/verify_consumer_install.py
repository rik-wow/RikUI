"""Exercise the public installer backend in a retained, isolated Windows game folder.

Uses a real currently verified PE/.build.info and completed local assembly.
No imported data is published. The source client and assembly stay untouched.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import zipfile
import forever_inputs as current
import local_assembly


def file_sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def verify_installed(bundle,addons):
    with zipfile.ZipFile(bundle) as archive:
        manifest=json.loads(archive.read("bundle.json"))
    for name,row in manifest["files"].items():
        target=Path(addons)/name
        if target.stat().st_size!=row["bytes"] or file_sha(target)!=row["sha256"]:
            raise ValueError("Installed bytes differ: "+name)
    return dict(files=len(manifest["files"]),roots=sorted({name.split("/")[0] for name in manifest["files"]}))


def verify(program,result,output):
    started=time.monotonic()
    program=current.regular(program).resolve()
    assembly=json.loads(current.regular(result).read_bytes())
    chosen=current.discover(assembly["resolution"]["installation"]["executable"])
    if chosen["fingerprint"]!=assembly["resolution"]["fingerprint"]:
        raise ValueError("Refresh the completed assembly for current inputs first")
    output=Path(output).absolute()
    if output.exists():raise ValueError("Verification requires a new retained output folder")
    output.mkdir(parents=True)
    storage=output/"game-storage";game=storage/"release-directory-fixture"
    game.mkdir(parents=True)
    executable=game/"WowRelease.exe"
    shutil.copyfile(chosen["installation"]["executable"],executable)
    shutil.copyfile(chosen["installation"]["buildInfo"],storage/".build.info")
    isolated=current.discover(executable)
    if isolated["fingerprint"]!=chosen["fingerprint"]:raise ValueError("Isolated client identity differs")
    addons=game/"Interface/AddOns"
    sentinels={
        game/"WTF/Account/fixture/settings.lua":b"preserved player settings\n",
        addons/"UnrelatedAddon/private.txt":b"preserved other addon\n",
        addons/"RikUI/generated/player-private/notes.txt":b"preserved local player data\n",
    }
    for path,raw in sentinels.items():
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
    appdata=output/"appdata";root=appdata/"RikUI";root.mkdir(parents=True)
    cache=output/"cache";job=cache/"job-verification";job.mkdir(parents=True)
    # Copies just the final local bundle. Geometry/corpus inputs are read-only and
    # remain byte-verified at their original separately acquired local paths.
    copied=job/"local-bundle.zip"
    shutil.copyfile(assembly["bundle"],copied)
    shutil.copyfile(Path(assembly["bundle"]).with_suffix(".receipt.json"),copied.with_suffix(".receipt.json"))
    ready=dict(assembly,bundle=str(copied))
    local_assembly.atomic(cache/"latest.json",ready)
    local_assembly.atomic(root/"preferences.json",dict(preparation_folder=str(cache)))
    environment=dict(os.environ,LOCALAPPDATA=str(appdata),PATH=os.environ["SystemRoot"]+"/System32;"+os.environ["SystemRoot"])
    runs=[]
    def run(expect_success,daily=False):
        phase=time.monotonic()
        arguments=["--daily-update"] if daily else ["--install-current",str(storage),"--no-schedule"]
        child=subprocess.run([str(program),*arguments],
            env=environment,cwd=output,timeout=900,creationflags=subprocess.CREATE_NO_WINDOW)
        error_path=root/("daily-update.json" if daily else "installation-error.json")
        error=json.loads(error_path.read_bytes()) if child.returncode and error_path.exists() else None
        runs.append(dict(action="paused-daily-check" if daily else "install-or-resume",exitCode=child.returncode,seconds=round(time.monotonic()-phase,1),error=error))
        if (child.returncode==0)!=expect_success:raise ValueError("Unexpected isolated installer result")
        for path,raw in sentinels.items():
            if path.read_bytes()!=raw:raise ValueError("Player or unrelated files changed")
    run(True)
    installed=verify_installed(copied,addons)
    first=json.loads((root/"installed.json").read_bytes())
    if Path(first["game"])!=game:raise ValueError("Relocated current client was not selected")
    history=game/"Interface/RikUI-backups"
    transactions=lambda:sorted(path.name for path in history.iterdir() if path.is_dir())
    before=transactions()
    run(True)
    verify_installed(copied,addons)
    if transactions()!=before:raise ValueError("Unchanged update created another backup")
    # The operating daily backend must still check current sources and actual
    # retained bytes while paused, without generating, installing or resuming.
    latest_sha=file_sha(cache/"latest.json")
    pause=cache/"cancel";pause.write_bytes(b"player paused")
    run(True,daily=True)
    status=json.loads((root/"status.json").read_bytes())
    daily=json.loads((root/"daily-update.json").read_bytes())
    if (status.get("state")!="paused" or status.get("resolution",{}).get("fingerprint")!=chosen["fingerprint"]
            or status.get("rebuild")!=[] or status.get("changed")!=[] or daily.get("state")!="checked"):
        raise ValueError("Paused daily compatibility/byte check did not report current unchanged inputs")
    if pause.read_bytes()!=b"player paused" or file_sha(cache/"latest.json")!=latest_sha:
        raise ValueError("Read-only daily check changed the pause marker or assembly")
    if transactions()!=before:raise ValueError("Paused daily check changed backups")
    verify_installed(copied,addons)
    run(True)
    if pause.exists():raise ValueError("Explicit resume did not clear the player's pause")
    if transactions()!=before:raise ValueError("Unchanged resume created another backup")
    verify_installed(copied,addons)
    # Corrupt only the isolated executable. Metadata failure must keep installation
    # and all completed inputs intact. Retain the bad fixture, then retry.
    held=executable.with_name("verified-executable-retained.exe")
    executable.rename(held);executable.write_bytes(b"invalid PE fixture")
    run(False)
    verify_installed(copied,addons)
    executable.rename(executable.with_name("invalid-executable-retained.bin"))
    shutil.copyfile(held,executable)
    run(True)
    verify_installed(copied,addons)
    if transactions()!=before:raise ValueError("Recovery created an unnecessary backup")
    proof=dict(format="rikui-isolated-consumer-proof-v1",programSHA256=file_sha(program),
        build=chosen["inputs"]["identity"]["build"],fingerprint=chosen["fingerprint"],
        bundleSHA256=file_sha(copied),installation=installed,runs=runs,
        settingsPreserved=True,privateDataPreserved=True,unrelatedAddonsPreserved=True,
        relocatedDirectoryVerified=True,repeatUpdateNoOp=True,failedClientRecovery=True,
        pausedDailyCurrentCheck=True,pausedDataPreserved=True,explicitResumeNoOp=True,
        seconds=round(time.monotonic()-started,1),output=str(output))
    local_assembly.atomic(output/"evidence.json",proof)
    return proof


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("program","result","output"):parser.add_argument("--"+name,required=True)
    args=parser.parse_args()
    print(json.dumps(verify(args.program,args.result,args.output)))
