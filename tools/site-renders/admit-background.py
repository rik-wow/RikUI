"""Admit an explicitly supplied, inspected background by its exact reviewed hash.
Copies original bytes; never edits an image or updates addon render baselines.
"""
import argparse, hashlib, io, json
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--reviewed-sha256", required=True)
args = parser.parse_args()
raw = args.source.read_bytes()
digest = hashlib.sha256(raw).hexdigest()
if digest != args.reviewed_sha256:
    raise RuntimeError("Source differs from the exact reviewed screenshot")
image = Image.open(io.BytesIO(raw))
if image.format != "JPEG" or image.size != (3840, 2160):
    raise RuntimeError("Expected the supplied original 3840×2160 JPEG")
image.verify()
root = Path(__file__).resolve().parent / "worlds"
record = {"name": "studio-background", "file": "studio-background.jpg",
          "caption": "User-supplied game screenshot; shared by every Studio preview.",
          "width": 3840, "height": 2160, "sha256": digest, "reviewedSHA256": digest,
          "reviewedAt": datetime.now(timezone.utc).isoformat(),
          "source": {"kind": "user-provided-game-screenshot", "filename": args.source.name},
          "limitations": ["Fixed historical screenshot; no live camera, character or client-build claim.",
                          "Original character and overhead names are part of the supplied image."]}
(root / record["file"]).write_bytes(raw)
(root / "studio-background.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"width":3840,"height":2160,"sha256":digest,"bytes":len(raw)}))
