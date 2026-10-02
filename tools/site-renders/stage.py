"""Stage unchanged addon inputs in the isolated renderer, without touching game/player files."""
import argparse
from pathlib import Path
import shutil
from render import ROOT, addon_inventory, verify_addon
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--sim-root", type=Path, required=True)
    args=parser.parse_args()
    root=args.sim_root.resolve()
    destination=(root/"addons"/"RikUI").resolve()
    if destination.parent.parent != root:
        raise RuntimeError("Renderer destination escapes simulator root")
    for name in addon_inventory():
        source=ROOT/name
        target=destination/name
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
    verify_addon(destination)
    print("Staged verified unchanged addon: "+str(destination))
if __name__=="__main__":main()
