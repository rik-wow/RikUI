"""Exercise actual completed compressed terrain jobs through the packaged resume CLI.

This is private delivery verification, not gameplay acceptance or a consumer setup.
It preserves original job bytes and writes new evidence only at an unused path.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import forever_inputs as current
import local_assembly as local

sys.path.insert(0,str(Path(__file__).resolve().parent/"terrain"))
import world_stitch as stitch
import world_export_graph as graph


def verify(runtime,acquisition,bakes,output,count=2):
    started=time.monotonic()
    runtime,acquisition,bakes=map(lambda value:Path(value).absolute(),(runtime,acquisition,bakes))
    output=Path(output).absolute()
    if output.exists() or not 1<=count<=8:
        raise ValueError("Choose a new evidence path and a bounded job count")
    original=json.loads((acquisition/"current-inputs.json").read_bytes())
    resolution=current.discover(original["resolution"]["installation"]["executable"])
    receipt=local.verify_acquisition(acquisition,resolution)
    index=acquisition/"placements.sqlite"
    indexed=local.verify_index(index,receipt,runtime/"tools/terrain")
    environment=dict(os.environ,RIKUI_CURRENT_INPUTS=str(acquisition/"current-inputs.json"),
        RIKUI_CLIENT_BUILD=resolution["inputs"]["identity"]["build"],
        PATH=str(runtime/"node")+os.pathsep+str(runtime/"python")+os.pathsep+
             os.environ["SystemRoot"]+"/System32"+os.pathsep+os.environ["SystemRoot"])
    checked=[]
    for path in sorted(bakes.glob("w*/w*/receipt.json")):
        directory=path.parent
        raw=path.read_bytes();value=json.loads(raw)
        if value.get("status")!="derived-pending-seam-validation":
            continue
        manifest=directory/"bake/manifest.json"
        batch=stitch.load(manifest.parent,local.digest(manifest))
        if not batch["polygons"] or not batch["witnesses"]:
            continue
        if {row["filename"] for row in value["files"]}&{"geometry.json","bake/polygons.json"}:
            raise ValueError("Current preparation retained uncompressed geometry")
        graph.validate_receipt(dict(receiptPath=str(path),receiptSHA256=current.sha(raw),
                                    directory=str(manifest.parent)),batch)
        before=local.inventory(directory)
        job=batch["manifest"]["job"]
        command=[str(runtime/"python/python.exe"),"-B",str(runtime/"tools/terrain/world_bake.py"),
            "--profile",str(acquisition/"acquisition-profile.json"),"--expected-sha256",receipt["profileSHA256"],
            "--source-directory",str(acquisition/"db2"),
            "--tile-csv",str(acquisition/"db2/all-projected-world-tile-worklist.csv"),
            "--topology-inventory",str(acquisition/"db2/inventory.json"),
            "--placement-index",str(index),"--index-sha256",indexed["sha256"],
            "--world",str(job["worldMapID"]),"--batch",*map(str,job["batchGrid"]),
            "--output",str(directory.parent),"--resume"]
        completed=subprocess.run(command,env=environment,text=True,stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
        if completed.returncode:
            raise ValueError("Packaged resume failed: "+completed.stdout[-4000:])
        if local.inventory(directory)!=before:
            raise ValueError("Verified compressed job bytes changed during resume")
        checked.append(dict(job=job["id"],files=len(before),ownedPolygons=len(batch["polygons"]),
                            boundaryWitnesses=len(batch["witnesses"]),output=completed.stdout))
        if len(checked)==count:
            break
    if len(checked)!=count:
        raise ValueError("Not enough completed jobs with actual owned and boundary geometry")
    refreshed=current.discover(resolution["installation"]["executable"])
    if refreshed["fingerprint"]!=resolution["fingerprint"]:
        raise ValueError("Inputs changed during resume verification")
    proof=dict(format="rikui-actual-compact-resume-proof-v1",resolution=resolution,jobs=checked,
        exactStoredBytesPreserved=True,geometryAndPolygonEvidenceVerified=True,
        partialVerification=True,installationComplete=False,seconds=round(time.monotonic()-started,1))
    with output.open("xb") as stream:
        stream.write(current.canonical(proof)+b"\n")
    return proof


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("runtime","acquisition","bakes","output"):
        parser.add_argument("--"+name,required=True)
    args=parser.parse_args()
    print(json.dumps(verify(args.runtime,args.acquisition,args.bakes,args.output)))
