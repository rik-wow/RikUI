"""Check packaged authored bytes against the committed Windows checkout policy."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(str(Path(__file__).resolve().parents[1]).removeprefix("\\\\?\\"))


def verify(runtime):
    runtime=Path(runtime).resolve()
    manifest=json.loads((runtime/"runtime.json").read_bytes())
    rows=[row for row in manifest["files"] if row["path"].startswith("tools/") and "/node_modules/" not in row["path"]]
    rows+= [row for row in manifest["files"] if row["path"]=="LICENSE.txt"]
    source=lambda name:"tests/check_manifest.py" if name=="tools/check_manifest.py" else "LICENSE" if name=="LICENSE.txt" else name
    paths=[source(row["path"]) for row in rows]
    raw=subprocess.check_output(["git","check-attr","-z","eol","text","--",*paths],cwd=ROOT)
    values=raw.decode().split("\0");attributes={}
    for offset in range(0,len(values)-1,3):
        path,key,value=values[offset:offset+3]
        attributes.setdefault(path,{})[key]=value
    differences=[]
    for row in rows:
        name=source(row["path"])
        blob=subprocess.check_output(["git","show","HEAD:"+name],cwd=ROOT)
        attrs=attributes[name]
        if attrs["text"]!="unset":
            normalized=blob.replace(b"\r\n",b"\n")
            if attrs["eol"]=="lf":blob=normalized
            elif attrs["eol"]=="crlf":blob=normalized.replace(b"\n",b"\r\n")
            elif b"\0" not in blob:blob=normalized.replace(b"\n",b"\r\n")
        expected=hashlib.sha256(blob).hexdigest()
        if expected!=row["sha256"]:
            differences.append(dict(path=row["path"],checkoutSHA256=expected,runtimeSHA256=row["sha256"],attributes=attrs))
    result=dict(format="rikui-runtime-authored-checkout-verification-v1",files=len(rows),differences=differences)
    print(json.dumps(result))
    if differences:raise ValueError("Packaged authored bytes differ from the committed Windows checkout")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime",required=True)
    verify(parser.parse_args().runtime)
