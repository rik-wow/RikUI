"""Promote only explicitly reviewed captures; never accept changed images during tests."""
import argparse
import json
from pathlib import Path
import shutil
from check import BASELINE, ROOT, check

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reviewed", nargs="+", required=True, help="Scenario ID=SHA256 reviewed at full size")
    args = parser.parse_args()
    reviewed = dict(value.split("=", 1) for value in args.reviewed)
    source = ROOT / "dist/ui-renders"
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    for capture in manifest["renders"]:
        if reviewed.get(capture["id"]) != capture["sha256"]:
            raise RuntimeError("Missing exact image review: " + capture["id"])
        capture["reviewedSha256"] = capture["sha256"]
    staging = ROOT / "dist/ui-renders-reviewed"
    staging.mkdir(parents=True, exist_ok=True)
    for capture in manifest["renders"]:
        shutil.copyfile(source / capture["filename"], staging / capture["filename"])
    (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    check(staging)
    BASELINE.mkdir(parents=True, exist_ok=True)
    for capture in manifest["renders"]:
        shutil.copyfile(staging / capture["filename"], BASELINE / capture["filename"])
    shutil.copyfile(staging / "manifest.json", BASELINE / "manifest.json")
    print("Promoted reviewed captures to " + str(BASELINE))

if __name__ == "__main__":
    main()

