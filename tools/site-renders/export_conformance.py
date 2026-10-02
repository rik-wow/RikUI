"""Extract representative native Export live output for browser conformance tests."""
import argparse, json, re
from pathlib import Path
def extract(root, output):
    root=Path(root)
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    capture=next(c for c in manifest["renders"] if c["id"]=="studio-live-export")
    code=None
    for line in (root/"studio-live-export.log").open(encoding="utf-8"):
        if "STUDIO_LIVE_EXPORT " in line:
            match=re.search(r"!RIKS1![0-9]+:[0-9a-f]{8}:[A-Za-z0-9_]+",line.split("STUDIO_LIVE_EXPORT ",1)[1])
            if match:code=match.group(0);break
    if not code or not code.startswith("!RIKS1!") or len(code)>12032:
        raise RuntimeError("Native live export missing or over capacity")
    record={"version":1,"description":"Public representative output of the actual addon Export live control; no player records.",
            "client":capture["inputs"]["client"],"fixtureScriptSha256":capture["inputs"]["script"],"code":code}
    Path(output).write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
    print("Captured native Export live conformance fixture: %d characters"%len(code))
if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--capture-root",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args();extract(args.capture_root,args.output)
