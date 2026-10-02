"""Resolve current source heads and verify an already acquired exact-build client table."""
import argparse,json,hashlib,re,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import quest_data_refresh as refresh
parser=argparse.ArgumentParser()
parser.add_argument("--work",type=Path,required=True)
parser.add_argument("--acquisition",type=Path,required=True)
args=parser.parse_args()
work=args.work.resolve();work.mkdir(parents=True,exist_ok=True)
inputs={name:{"repository":repo,"revision":refresh.resolve_head(repo,ref)} for name,(repo,ref)in refresh.SOURCES.items()}
version=refresh.client_version(refresh.download("https://raw.githubusercontent.com/Gethe/wow-ui-source/"+inputs["ui"]["revision"]+"/version.txt"))
evidence=json.loads((args.acquisition/"comparison.json").read_text())
record=next(r for r in evidence if r["table"]=="QuestV2")
if record["url"]!="https://wago.tools/db2/QuestV2/csv?build="+version:raise RuntimeError("Acquisition is not the current build")
raw=(args.acquisition/"QuestV2.csv").read_bytes()
if hashlib.sha256(raw).hexdigest()!=record["sha256"]:raise RuntimeError("Acquisition hash differs")
index=work/"QuestV2.csv";index.write_bytes(raw)
refresh.corpus.load_client_index(index,record["sha256"])
inputs["client"]={"build":version,"sha256":record["sha256"]}
inputs["builderSHA256"]=refresh.builder_hash(Path.cwd())
fingerprint=refresh.corpus.sha(refresh.corpus.canonical(inputs).encode())
resolution={"schemaVersion":1,"inputs":inputs,"fingerprint":fingerprint,"tag":"quest-data-"+fingerprint[:24]}
refresh.write_json(work/"resolution.json",resolution)
print(json.dumps(resolution))
