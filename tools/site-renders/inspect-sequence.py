"""Bounded native-root diagnostics for a component sequence under development."""
import argparse,json
from pathlib import Path
from fixtures import load_modules,scenario_script
from provenance import text_digest,digest
from validate_capture import validate_capture,read_tree
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument("id");p.add_argument("--directory",type=Path,required=True);a=p.parse_args()
case=next(c for c in json.loads((Path(__file__).with_name("scenarios.json")).read_text()) if c["id"]==a.id)
manifest=json.loads((a.directory/"manifest.json").read_text());modules=load_modules()
for value in case["sequence"]["values"]:
    stem=a.directory/(a.id+"@"+str(value));script=stem.with_suffix(".lua");log=stem.with_suffix(".log");image=stem.with_suffix(".webp")
    if not log.exists():print(value,"missing");continue
    text=log.read_text(encoding="utf-8");effective={**case,"frame":case["sequence"].get("frames",{}).get(str(value),case["frame"])}
    status="current" if script.exists() and digest(script,normalized=True)==text_digest(scenario_script(case,modules,manifest["client"]["version"],value)) else "old fixture"
    nodes,_=read_tree(effective,text);root=next((n for n in nodes if not n["indent"]),{})
    try:validate_capture(effective,image,text);check="pass"
    except (RuntimeError,OSError) as e:check=str(e)
    print(value,status,check,{k:root.get(k) for k in ("name","visible","x","y","w","h")})
