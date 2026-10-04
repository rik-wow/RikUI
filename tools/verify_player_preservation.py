"""Record and verify private file preservation around an actual client installation.

The receipt stays outside the checkout and contains only paths, sizes and hashes.
This helper observes the installer transaction; it does not modify the game.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import forever_inputs as current
import local_assembly
from verify_consumer_install import verify_installed


def digest(path):
    with current.regular(path).open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def tree(root,area):
    root=Path(root)
    if not root.exists():return []
    rows=[]
    for path in sorted(root.rglob("*")):
        if path.is_symlink() or (hasattr(path,"is_junction") and path.is_junction()):
            raise ValueError("Linked preservation input: "+str(path))
        if path.is_file():
            rows.append(dict(area=area,path=path.relative_to(root).as_posix(),
                             bytes=path.stat().st_size,sha256=digest(path)))
    return rows


def save_new(path,receipt):
    path=Path(path).absolute()
    if path.exists():raise ValueError("Choose a new retained proof path")
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open("xb") as stream:stream.write(current.canonical(receipt)+b"\n")


def snapshot(executable,migration,output):
    resolution=current.discover(executable)
    game=Path(resolution["installation"]["directory"])
    source=json.loads(current.regular(migration).read_bytes())
    roots=dict(addons=str(game/"Interface/AddOns"),settings=str(game/"WTF"),source=source["source"])
    files=tree(roots["addons"],"addons")+tree(roots["settings"],"settings")
    for row in source["files"]:
        path=Path(roots["source"])/row["path"]
        if digest(path)!=row["sha256"]:raise ValueError("Migration source bytes changed")
        files.append(dict(row,area="source"))
    history=game/"Interface/RikUI-backups"
    transactions=sorted(path.name for path in history.iterdir() if path.is_dir()) if history.exists() else []
    receipt=dict(format="rikui-player-preservation-snapshot-v1",recordedAt=time.time(),
                 resolution=resolution,roots=roots,files=files,transactions=transactions,
                 retainedJunction=source["retainedJunction"])
    save_new(output,receipt)
    return dict(snapshot=str(output),files=len(files),bytes=sum(row["bytes"] for row in files),
                areas={area:sum(row["area"]==area for row in files) for area in roots})


def verify(snapshot_path,installed_path,result_path,output,backup=None):
    before=json.loads(current.regular(snapshot_path).read_bytes())
    installed=json.loads(current.regular(installed_path).read_bytes())
    assembly=json.loads(current.regular(result_path).read_bytes())
    resolution=current.discover(installed["resolution"]["installation"]["executable"])
    if resolution["fingerprint"]!=assembly["resolution"]["fingerprint"] or installed["resolution"]["fingerprint"]!=resolution["fingerprint"]:
        raise ValueError("Installed inputs are no longer current")
    if Path(installed["game"]).resolve()!=Path(before["resolution"]["installation"]["directory"]).resolve():
        raise ValueError("Preservation snapshot belongs to another game")
    import zipfile
    with zipfile.ZipFile(current.regular(assembly["bundle"])) as archive:
        manifest=json.loads(archive.read("bundle.json"))
    addons=Path(before["roots"]["addons"])
    installation=verify_installed(assembly["bundle"],addons)
    transaction=Path(backup or installed.get("backup") or "")
    if not transaction.is_absolute() or not (transaction/"complete").is_file():
        raise ValueError("Retained completed installation backup is required")
    roots={name.split("/")[0] for name in manifest["files"]}
    preserved={area:0 for area in before["roots"]};backed_up=0
    for row in before["files"]:
        path=Path(before["roots"][row["area"]])/row["path"]
        if row["area"]!="addons" or row["path"] not in manifest["files"]:
            if path.stat().st_size!=row["bytes"] or digest(path)!=row["sha256"]:
                raise ValueError("Preserved file changed: "+row["area"]+"/"+row["path"])
            preserved[row["area"]]+=1
        if row["area"]=="addons" and row["path"].split("/")[0] in roots:
            old=transaction/"previous"/row["path"]
            if old.stat().st_size!=row["bytes"] or digest(old)!=row["sha256"]:
                raise ValueError("Previous owned-root bytes were not retained: "+row["path"])
            backed_up+=1
    held=Path(before["retainedJunction"])
    if not held.is_junction() or held.resolve()!=Path(before["roots"]["source"]).resolve():
        raise ValueError("Retained source junction changed")
    if digest(assembly["bundle"])!=installed["bundleSHA256"]:
        raise ValueError("Installed bundle receipt differs")
    receipt=dict(format="rikui-actual-client-preservation-proof-v1",build=resolution["inputs"]["identity"]["build"],
                 fingerprint=resolution["fingerprint"],installation=installation,
                 preservedFiles=preserved,previousRootFilesVerified=backed_up,backup=str(transaction),
                 retainedJunction=str(held),settingsPreserved=True,privateDataPreserved=True,
                 sourceCheckoutPreserved=True,unrelatedAddonsPreserved=True,
                 snapshot=str(Path(snapshot_path).absolute()),installed=str(Path(installed_path).absolute()))
    save_new(output,receipt)
    return receipt


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode",choices=["snapshot","verify"])
    for name in ("executable","migration","snapshot","installed","result","output","backup"):
        parser.add_argument("--"+name)
    args=parser.parse_args()
    if not args.output:parser.error("--output is required")
    if args.mode=="snapshot":
        if not args.executable or not args.migration:parser.error("--executable and --migration are required")
        receipt=snapshot(args.executable,args.migration,args.output)
    else:
        if not all((args.snapshot,args.installed,args.result)):parser.error("--snapshot --installed --result are required")
        receipt=verify(args.snapshot,args.installed,args.result,args.output,args.backup)
    print(json.dumps(receipt))
