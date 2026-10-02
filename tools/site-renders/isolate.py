"""Create a separate renderer scratch session while sharing verified read-only source/binary."""
import argparse,subprocess
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument("--sim-root",type=Path,required=True)
parser.add_argument("--source-root",type=Path,required=True)
args=parser.parse_args();root=args.sim_root.resolve();source=args.source_root.resolve()
if root==source or root in source.parents or source in root.parents or len(root.parts)<3:raise RuntimeError("Use a dedicated independent renderer directory")
root.mkdir(parents=True,exist_ok=True)
for name in ("source","forever-source"):
    target=source/name;link=root/name
    if not target.is_dir():raise RuntimeError("Verified renderer source missing: "+name)
    if link.exists():
        if link.resolve()!=target.resolve():raise RuntimeError("Existing renderer link differs")
    else:subprocess.run(["cmd","/c","mklink","/J",str(link),str(target)],check=True,capture_output=True)
(root/"addons").mkdir(exist_ok=True);(root/"WTF").mkdir(exist_ok=True)
if not (root/"AddOns.txt").exists():(root/"AddOns.txt").write_text("RikUI: enabled\nA_RikUIPreview: enabled\n")
print("Isolated renderer scratch session: "+str(root))
