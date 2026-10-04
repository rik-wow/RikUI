"""Merge independently rendered current captures without reviewing or promoting them."""
import argparse,json,shutil
from pathlib import Path
from check import ROOT,current_addon_files,expected_tree_inputs,verify_capture,verify_environment
from dependencies import inventory_history,compact_inventories
from fixtures import load_modules,scenario_script
from provenance import digest,text_digest
from schema import frames_of
from validate_capture import validate_capture
def merge(source,destination,ids):
    if source.resolve()==destination.resolve():raise RuntimeError("Source and destination must differ")
    incoming=json.loads((source/"manifest.json").read_text(encoding="utf-8"))
    destination.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((destination/"manifest.json").read_text(encoding="utf-8")) if (destination/"manifest.json").exists() else {**incoming,"renders":[]}
    cases={c["id"]:c for c in json.loads(Path(__file__).with_name("scenarios.json").read_text(encoding="utf-8"))}
    records={c["id"]:c for c in incoming["renders"]}
    selected=[records[name] for name in ids] if ids else incoming["renders"]
    errors=[];verify_environment({"renders":selected},errors)
    current=current_addon_files(incoming,errors);modules=load_modules();hashes={}
    for capture in selected:
        case=cases[capture["id"]]
        if capture["inputs"]["client"]!=incoming["client"] and any(
            capture["inputs"]["client"].get(k)!=incoming["client"].get(k)
            for k in ("version","foreverCommit","executableSha256")):
            errors.append("Source client differs: "+case["id"])
        expected=expected_tree_inputs(case,incoming,modules,current)
        verify_capture(case,capture,expected,source,errors,hashes)
        for frame in frames_of(capture):
            value=frame.get("value");stem=case["id"]+("@"+str(value) if value is not None else "")
            script=source/(stem+".lua");log=source/(stem+".log")
            if not script.is_file() or digest(script,normalized=True)!=text_digest(
                    scenario_script(case,modules,capture["inputs"]["client"]["version"],value)):
                errors.append("Missing or stale frame fixture: "+stem);continue
            effective={**case,"frame":case.get("sequence",{}).get("frames",{}).get(str(value),case["frame"])}
            validate_capture(effective,source/frame["filename"],log.read_text(encoding="utf-8"))
    errors=[e for e in errors if not e.startswith("Image needs visual review: ")]
    if errors:raise RuntimeError("\n".join(errors))
    history=inventory_history(manifest);history.update(inventory_history(incoming))
    manifest["addonInventories"]=history
    by_id={c["id"]:c for c in manifest["renders"]}
    for capture in selected:
        by_id[capture["id"]]=capture
        for frame in frames_of(capture):
            filename=frame["filename"]
            if Path(filename).name!=filename:raise RuntimeError("Invalid capture filename")
            shutil.copyfile(source/filename,destination/filename)
            value=frame.get("value");stem=capture["id"]+("@"+str(value) if value is not None else "")
            for suffix in (".lua",".log"):
                shutil.copyfile(source/(stem+suffix),destination/(stem+suffix))
    manifest["renders"]=[by_id[key] for key in sorted(by_id)]
    compact_inventories(manifest)
    (destination/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print("Merged %d authenticated captures; review and promotion remain separate."%len(selected))
if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source",type=Path,required=True)
    p.add_argument("--destination",type=Path,default=ROOT/"dist/ui-renders")
    p.add_argument("--only",nargs="*",default=[])
    p.add_argument("--sim-root",type=Path,required=True);p.add_argument("--wow-root",type=Path,required=True)
    a=p.parse_args()
    from render import verify_client
    current=verify_client(a.sim_root,a.wow_root)
    incoming=json.loads((a.source/"manifest.json").read_text(encoding="utf-8"))
    if any(incoming["client"].get(k)!=current[k] for k in ("version","foreverCommit","executableSha256")):
        raise RuntimeError("Merge requires verified current client inputs")
    merge(a.source,a.destination,a.only)
