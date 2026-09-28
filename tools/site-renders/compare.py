"""Write a review report and fail when a capture differs from its baseline."""
import json
from pathlib import Path
import sys
from check import BASELINE, ROOT
from schema import frames_of, frame_id
from validate_capture import compare_images

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
    print("Changed captures: " + (", ".join(changed) or "none"))
    print("Report: " + str(current / "comparison.json"))
    return bool(changed)

if __name__ == "__main__":
    sys.exit(main())
