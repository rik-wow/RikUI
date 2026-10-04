"""Verify a completed current navigation pack and replay actual addon Lua routes."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import forever_inputs as current
import local_assembly as assembly
import quest_corpus
ROOT=Path(str(Path(__file__).resolve().parents[1]).removeprefix("\\\\?\\"))
sys.path.insert(0,str(ROOT/"tools/terrain"))
from install_roads import source_pack

ROUTES=(
    (1426,.30,.73,.46,.52),
    (1429,.48,.42,.42,.65),
    (1411,.43,.69,.52,.42),
    (1438,.58,.45,.56,.60),
)


def verify(roads,acquisition,corpus,travel,network_input,output):
    start=time.monotonic()
    roads,acquisition,corpus=map(Path,(roads,acquisition,corpus))
    receipt=json.loads((acquisition/"current-inputs.json").read_bytes())
    resolution=current.discover(receipt["resolution"]["installation"]["executable"])
    acquisition_receipt=assembly.verify_acquisition(acquisition,resolution)
    quest_corpus.verify(corpus)
    source,files,packs=source_pack(roads,assembly.digest(roads/"road-network-receipt.json"))
    network=json.loads((roads/"road-network-receipt.json").read_bytes())
    for key,path in (("inputSHA256",network_input),("semanticSHA256",corpus/"audit/semantic-quests.json"),
                     ("travelSHA256",travel),("compilerSHA256",ROOT/"tools/terrain/road_network.py")):
        if network[key]!=assembly.digest(path):raise ValueError("Current road input changed: "+key)
    if {row["worldMapID"] for row in network["worlds"]}!=set(map(int,acquisition_receipt["topology"])):
        raise ValueError("Supported current worlds incomplete")
    environment=dict(os.environ,RIKUI_CLIENT_BUILD=resolution["inputs"]["identity"]["build"])
    replays=[]
    for values in ROUTES:
        command=["luajit","tests/quest-roads-navigate-real.lua",str(source),*map(str,values)]
        result=subprocess.run(command,cwd=ROOT,env=environment,text=True,
                              stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=300)
        replays.append(dict(map=values[0],exitCode=result.returncode,output=result.stdout))
        print(result.stdout,flush=True)
        if result.returncode:raise ValueError("Actual current Lua route replay failed on map "+str(values[0]))
    refreshed=current.discover(resolution["installation"]["executable"])
    if refreshed["fingerprint"]!=resolution["fingerprint"]:raise ValueError("Current inputs changed during navigation verification")
    proof=dict(format="rikui-current-navigation-verification-v1",resolution=resolution,
        receiptSHA256=assembly.digest(roads/"road-network-receipt.json"),
        verifiedFiles=len(files),patchPacks=len(packs),worlds=network["worlds"],replays=replays,
        nativeAcceptance="User accepts native gameplay and reports regressions",
        nativeObserved=False,seconds=round(time.monotonic()-start,1))
    assembly.atomic(output,proof)
    return proof


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("roads","acquisition","corpus","travel","network-input","output"):
        parser.add_argument("--"+name,required=True)
    args=parser.parse_args()
    result=verify(args.roads,args.acquisition,args.corpus,args.travel,args.network_input,args.output)
    print(json.dumps({key:result[key] for key in ("format","receiptSHA256","verifiedFiles","patchPacks","seconds")}))
