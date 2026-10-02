"""Bounded capture diagnostics for review; images are still reviewed at original size."""
import argparse,json,re
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument("ids",nargs="+")
parser.add_argument("--directory",type=Path,default=ROOT/"dist/ui-renders")
args=parser.parse_args()
manifest=json.loads((args.directory/"manifest.json").read_text())
for name in args.ids:
 c=next((r for r in manifest["renders"] if r["id"]==name),None)
 print(json.dumps({k:c.get(k) for k in ("id","filename","sha256","components")} if c else {"id":name,"capture":"missing"},default=str)[:14000])
 log=args.directory/(name+".log")
 if log.exists():
  lines=log.read_text(encoding="utf-8").splitlines()
  from validate_capture import read_tree
  nodes,_=read_tree({},log.read_text(encoding="utf-8"))
  print("ROOTS",[{k:n[k] for k in ("name","visible","w","h")} for n in nodes if not n["indent"]][:6])
  print("VISIBLE TEXT",read_tree({},log.read_text(encoding="utf-8"))[1][:40])
  for line in lines:
   if "FIT " in line or "STUDIO_GROUP " in line or "[exec-lua] error:" in line:print(line[:500])
 if c:
  from validate_capture import read_tree
  nodes,_=read_tree(c,log.read_text(encoding="utf-8"))
  for n in sorted([n for n in nodes if n["type"]=="Texture" and n["visible"]=="visible" and n["alpha"]>0.5],key=lambda n:n["w"]*n["h"],reverse=True)[:10]:print("LARGE",n)
  im=Image.open(args.directory/c["filename"])
  print("IMAGE",im.size,im.mode,"alpha",im.getchannel("A").getextrema() if im.mode=="RGBA" else "opaque")
