"""List unreviewed authentic image hashes for explicit original-size review; never promotes."""
import argparse,json
from pathlib import Path
from provenance import digest
from schema import frames_of,frame_id
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument("--directory",type=Path,default=ROOT/"dist/ui-renders")
p.add_argument("--only",default="")
a=p.parse_args()
manifest=json.loads((a.directory/"manifest.json").read_text())
baseline=json.loads((ROOT/"web/ui-renders/manifest.json").read_text())
known={frame_id(c,f):f.get("reviewedSha256") for c in baseline["renders"] for f in frames_of(c)}
wanted=set(a.only.split(",")) if a.only else None
result=[]
for c in manifest["renders"]:
    if wanted and c["id"] not in wanted:continue
    for f in frames_of(c):
        name=frame_id(c,f)
        if digest(a.directory/f["filename"])!=f["sha256"]:raise RuntimeError("Image bytes changed: "+name)
        if known.get(name)!=f["sha256"]:
            result.append({"id":name,"filename":f["filename"],"sha256":f["sha256"]})
print(json.dumps(result))
