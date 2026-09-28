"""Promote only explicitly reviewed captures; never accept changed images during tests."""
import argparse
import json
from pathlib import Path
import shutil
from check import BASELINE, ROOT, check
from schema import frames_of, frame_id

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reviewed", nargs="+", required=True,
                        help="Scenario ID=SHA256 reviewed at full size; a sequence frame is ID@VALUE=SHA256")
    args = parser.parse_args()
    reviewed = dict(value.split("=", 1) for value in args.reviewed)
    source = ROOT / "dist/ui-renders"
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    for capture in manifest["renders"]:
        for frame in frames_of(capture):
            if reviewed.get(frame_id(capture, frame)) != frame["sha256"]:
                raise RuntimeError("Missing exact image review: " + frame_id(capture, frame))
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
    for name in files:
        shutil.copyfile(staging / name, BASELINE / name)
    shutil.copyfile(staging / "manifest.json", BASELINE / "manifest.json")
    print("Promoted reviewed captures to " + str(BASELINE))

if __name__ == "__main__":
    main()
