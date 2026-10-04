"""Retain a development junction and materialize its game runtime before setup.

This migration is for an existing development installation. Public setup rejects
linked addon roots; the source checkout and every generated file are preserved.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import time
import forever_inputs as current
import package_addon


def normal_directory(path):
    path=Path(path).absolute()
    for part in (path,*path.parents):
        info=part.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info,"st_file_attributes",0)&0x400:
            raise ValueError("Linked migration directory: "+str(part))
    if not path.is_dir():raise ValueError("Expected migration directory")
    return path


def digest(path):
    with current.regular(path).open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def migrate(executable,source,proof):
    if os.name!="nt":raise ValueError("Windows development junction migration only")
    resolution=current.discover(executable)
    game=normal_directory(resolution["installation"]["directory"])
    source=normal_directory(source)
    interface=normal_directory(game/"Interface")
    addons=normal_directory(interface/"AddOns")
    target=addons/"RikUI"
    if not target.is_junction() or target.resolve()!=source:
        raise ValueError("Selected addon is not the exact source-checkout junction")
    proof=Path(proof).absolute()
    if proof.exists():raise ValueError("Choose a new retained migration proof")
    paths,_=package_addon.inventory(source)
    paths=dict(paths)
    for path in (source/"generated").rglob("*"):
        if path.is_symlink() or path.is_junction():raise ValueError("Linked generated data")
        if path.is_file():paths[path.relative_to(source).as_posix()]=current.regular(path)
    total=sum(path.stat().st_size for path in paths.values())
    if shutil.disk_usage(interface).free<total*2+1024**3:
        raise ValueError("Insufficient space for retained migration and installation")
    history=interface/"RikUI-source-links"
    if history.exists():normal_directory(history)
    else:history.mkdir()
    transaction=history/str(time.time_ns());transaction.mkdir()
    stage=transaction/"materialized";stage.mkdir()
    held=transaction/"retained-junction"
    rows=[]
    for name,path in sorted(paths.items()):
        current.regular(path)
        destination=stage/name;destination.parent.mkdir(parents=True,exist_ok=True)
        expected=digest(path)
        shutil.copyfile(path,destination)
        if digest(destination)!=expected:raise ValueError("Migration copy changed: "+name)
        rows.append(dict(path=name,bytes=path.stat().st_size,sha256=expected))
    refreshed=current.discover(executable)
    if refreshed["fingerprint"]!=resolution["fingerprint"]:
        raise ValueError("Current inputs changed before migration")
    names=subprocess.check_output(["tasklist.exe","/FO","CSV","/NH"],text=True)
    image=Path(executable).name.casefold()
    if any(line.split(",")[0].strip('"').casefold()==image for line in names.splitlines()):
        raise ValueError("Close World of Warcraft before addon migration")
    # Rename only the junction entry, never its source tree. Both destinations are
    # checked absolute children of this game Interface directory on the same drive.
    for destination in (held,stage,target):
        if not destination.absolute().is_relative_to(interface):raise ValueError("Migration path escaped game Interface")
    if not target.is_junction() or target.resolve()!=source:
        raise ValueError("Source junction changed during migration")
    target.rename(held)
    try:
        stage.rename(target)
        normal_directory(target)
        for row in rows:
            if digest(target/row["path"])!=row["sha256"]:raise ValueError("Materialized addon bytes changed")
    except BaseException:
        if target.exists():target.rename(transaction/"failed-materialized")
        held.rename(target)
        raise
    result=dict(format="rikui-development-junction-migration-v1",resolution=resolution,
        source=str(source),addon=str(target),retainedJunction=str(held),files=rows,
        generatedDataPreserved=True,sourceCheckoutPreserved=True,settingsUntouched=True)
    proof.parent.mkdir(parents=True,exist_ok=True)
    proof.write_bytes(current.canonical(result)+b"\n")
    return dict(proof=str(proof),files=len(rows),bytes=total,addon=str(target),retainedJunction=str(held))


if __name__=="__main__":
    import json
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("executable","source","proof"):parser.add_argument("--"+name,required=True)
    args=parser.parse_args()
    print(json.dumps(migrate(args.executable,args.source,args.proof)))
