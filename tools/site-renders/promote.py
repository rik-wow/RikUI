"""Promote reviewed captures; never accept changed images during tests.

An image identical to one already promoted keeps its review. Every other image (new, or changed since
the baseline) must be named with the hash that was viewed at full size."""
import argparse
import json
from pathlib import Path
import shutil
from check import BASELINE, ROOT, check
from dependencies import inventory_history, compact_inventories
from schema import frames_of, frame_id

def reviewed_baseline():
    path = BASELINE / "manifest.json"
    if not path.is_file():
        return {}
    manifest = json.loads(path.read_text(encoding="utf-8"))
    return {frame_id(capture, frame): frame.get("reviewedSha256")
            for capture in manifest.get("renders", []) for frame in frames_of(capture)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reviewed", nargs="*", default=[],
                        help="Scenario ID=SHA256 reviewed at full size; a sequence frame is ID@VALUE=SHA256")
    args = parser.parse_args()
    reviewed = dict(value.split("=", 1) for value in args.reviewed)
    already = reviewed_baseline()
    source = ROOT / "dist/ui-renders"
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    history = inventory_history(manifest)
    baseline_path = BASELINE / "manifest.json"
    if baseline_path.is_file():
        history.update(inventory_history(json.loads(baseline_path.read_text(encoding="utf-8"))))
    manifest["addonInventories"] = history
    compact_inventories(manifest)
    carried, fresh = 0, 0
    for capture in manifest["renders"]:
        for frame in frames_of(capture):
            name = frame_id(capture, frame)
            if already.get(name) == frame["sha256"]:
                carried += 1
            elif reviewed.get(name) == frame["sha256"]:
                fresh += 1
            else:
                raise RuntimeError("Missing exact image review: " + name)
            frame["reviewedSha256"] = frame["sha256"]
        if capture.get("frames"):
            capture["reviewedSha256"] = capture["sha256"]
    staging = ROOT / "dist/ui-renders-reviewed"
    staging.mkdir(parents=True, exist_ok=True)
    files = sorted({frame["filename"] for capture in manifest["renders"] for frame in frames_of(capture)})
    for name in files:
        shutil.copyfile(source / name, staging / name)
    (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    check(staging)
    BASELINE.mkdir(parents=True, exist_ok=True)
    for stale in BASELINE.glob("*.webp"):
        if stale.name not in files:
            stale.unlink()
    for name in files:
        shutil.copyfile(staging / name, BASELINE / name)
    shutil.copyfile(staging / "manifest.json", BASELINE / "manifest.json")
    print(f"Promoted {fresh} newly reviewed and {carried} unchanged images to {BASELINE}")

if __name__ == "__main__":
    main()
