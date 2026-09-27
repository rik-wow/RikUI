"""Write a review report and fail when a capture differs from its baseline."""
import json
from pathlib import Path
import sys
from check import BASELINE, ROOT
from validate_capture import compare_images

def main():
    current = ROOT / "dist/ui-renders"
    manifest = json.loads((current / "manifest.json").read_text())
    previous_path = BASELINE / "manifest.json"
    previous = json.loads(previous_path.read_text()) if previous_path.exists() else {"renders": []}
    known = {r["id"]: r for r in previous["renders"]}
    results = []
    for capture in manifest["renders"]:
        old = known.get(capture["id"])
        result = {"changed": True, "reason": "new scenario"}
        if old:
            result = compare_images(current / capture["filename"], BASELINE / old["filename"],
                                    current / "diffs" / (capture["id"] + ".png"))
        results.append({"id": capture["id"], **result})
    (current / "comparison.json").write_text(json.dumps(results, indent=2) + "\n")
    changed = [r["id"] for r in results if r["changed"]]
    print("Changed captures: " + (", ".join(changed) or "none"))
    print("Report: " + str(current / "comparison.json"))
    return bool(changed)

if __name__ == "__main__":
    sys.exit(main())

