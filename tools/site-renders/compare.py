"""Write a review report and fail when a capture differs from its baseline."""
import json
from pathlib import Path
import sys
from check import BASELINE, ROOT
from schema import frames_of, frame_id
from PIL import Image, ImageChops, ImageStat

def compare_images(actual, baseline, diff_path):
    current, old = Image.open(actual).convert("RGB"), Image.open(baseline).convert("RGB")
    if current.size != old.size:
        return {"changed": True, "reason": "dimensions"}
    diff = ImageChops.difference(current, old)
    mean = sum(ImageStat.Stat(diff).mean) / 3
    changed = bool(diff.getbbox())
    if changed:
        Path(diff_path).parent.mkdir(parents=True, exist_ok=True)
        diff.save(diff_path)
    return {"changed": changed, "meanChannelDifference": round(mean, 6)}

def main():
    current = ROOT / "dist/ui-renders"
    manifest = json.loads((current / "manifest.json").read_text())
    previous_path = BASELINE / "manifest.json"
    previous = json.loads(previous_path.read_text()) if previous_path.exists() else {"renders": []}
    known = {}
    for capture in previous["renders"]:
        for frame in frames_of(capture):
            known[frame_id(capture, frame)] = frame
    results = []
    for capture in manifest["renders"]:
        for frame in frames_of(capture):
            name = frame_id(capture, frame)
            old = known.get(name)
            result = {"changed": True, "reason": "new scenario"}
            if old:
                result = compare_images(current / frame["filename"], BASELINE / old["filename"],
                                        current / "diffs" / (name + ".png"))
            results.append({"id": name, **result})
    (current / "comparison.json").write_text(json.dumps(results, indent=2) + "\n")
    changed = [r["id"] for r in results if r["changed"]]
    print(f"{len(results) - len(changed)} captures unchanged")
    print("Changed captures: " + (", ".join(changed) or "none"))
    print("Report: " + str(current / "comparison.json"))
    return bool(changed)

if __name__ == "__main__":
    sys.exit(main())
