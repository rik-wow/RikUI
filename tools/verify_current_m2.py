"""Verify current version-274 M2 collision arrays against the packaged publisher reader."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

def node_path(value):
    value=str(value)
    if os.name=="nt" and value.startswith("\\\\?\\"):
        value=value[4:]
        if value.startswith("UNC\\"):value="\\\\"+value[4:]
    return value

HERE=Path(node_path(Path(__file__).resolve().parent))
sys.path.insert(0,str(HERE/"terrain"))
import collision_probe as collision


def sha(raw):return hashlib.sha256(raw).hexdigest()


def build(reader,profile,output):
    reader,profile,output=Path(reader).resolve(),Path(profile).resolve(),Path(output).absolute()
    document=json.loads(profile.read_bytes())
    rows=[]
    for row in document["files"]:
        if row["kind"]!="M2":continue
        raw=Path(row["path"]).read_bytes()
        if sha(raw)!=row["sha256"] or len(raw)!=row["bytes"]:raise ValueError("Current model changed")
        if len(raw)<16 or raw[:4]!=b"MD21" or struct.unpack_from("<I",raw,12)[0]!=274:continue
        # Decode bounded arrays independently of historical admission metadata.
        model=collision.m2(raw,validate_profile=False)
        result=subprocess.run([os.environ.get("RIKUI_NODE","node"),str(HERE/"client_m2_probe.cjs"),
            node_path(reader),node_path(row["path"]),row["sha256"]],cwd=node_path(HERE),check=True,stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,text=True,timeout=30,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name=="nt" else 0)
        if len(result.stdout)>16*1024*1024:raise ValueError("Current M2 reference output bound")
        proof=json.loads(result.stdout)
        def converted(values):
            return [value for at in range(0,len(values),3) for value in (values[at],values[at+2],-values[at+1])]
        if (proof["assetSHA256"]!=row["sha256"] or proof["version"]!=274
                or proof["collisionIndices"]!=model["indices"]
                or proof["collisionPositions"]!=converted(model["positions"])
                or proof["collisionNormals"]!=converted(model["normals"])):
            raise ValueError("Current M2 independent parser mismatch")
        rows.append(dict(fileDataID=row["fileDataID"],sha256=row["sha256"],bytes=len(raw),
                         vertices=len(model["positions"])//3,triangles=len(model["indices"])//3))
    result=dict(format="rikui-current-m2-proof-v1",sourceProfileSHA256=sha(profile.read_bytes()),
                readerSHA256=sha((reader/"src/js/3D/loaders/M2Loader.js").read_bytes()),
                genericsSHA256=sha((reader/"src/js/3D/loaders/M2Generics.js").read_bytes()),
                probeSHA256=sha((HERE/"client_m2_probe.cjs").read_bytes()),records=rows)
    if not 0<len(rows)<=32768:raise ValueError("Current M2 proof inventory bound")
    with output.open("xb") as stream:stream.write(json.dumps(result,sort_keys=True,indent=2).encode()+b"\n")
    return dict(records=len(rows),sha256=sha(output.read_bytes()),readerSHA256=result["readerSHA256"])


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("reader","profile","output"):parser.add_argument("--"+name,required=True)
    args=parser.parse_args()
    print(json.dumps(build(args.reader,args.profile,args.output)))
