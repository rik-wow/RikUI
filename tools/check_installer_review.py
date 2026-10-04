"""Check reviewed native UI source hashes; this never promotes captures."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def check():
    review=json.loads((ROOT/"installer/ui-review.json").read_bytes())
    if review.get("format")!="rikui-installer-visual-review-v1" or len(review["images"])!=13 or "file-verification" not in {row["state"] for row in review["images"]}:
        raise ValueError("Native installer review is incomplete")
    for name,expected in review["sourceInputs"].items():
        raw=(ROOT/name).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=expected:
            # Git checkout line-ending conversion does not change UI output.
            normalized=raw.replace(b"\r\n",b"\n")
            if hashlib.sha256(normalized).hexdigest()!=expected:
                raise ValueError("Native installer UI review is stale: "+name)
    print("Native installer review: thirteen exact inspected hashes; UI inputs unchanged.")

if __name__=="__main__":check()
