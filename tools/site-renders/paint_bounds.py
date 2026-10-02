"""Read actual reviewed sprite paint extents, including children outside native holder roots."""
import argparse, hashlib, json
from pathlib import Path
from PIL import Image

def bounds(path):
    image = Image.open(path).convert("RGBA")
    box = image.getchannel("A").getbbox()
    if box is None:
        raise RuntimeError("Empty native component: " + str(path))
    return dict(zip(("x", "y", "width", "height"), (box[0], box[1], box[2]-box[0], box[3]-box[1])))

def collect(root):
    root = Path(root).resolve()
    manifest = json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    result = {}
    for capture in manifest["renders"]:
        if capture.get("page") != "studio-atlas" and not capture["id"].startswith(("studio-atlas-", "studio-extra-")):
            continue
        for frame in capture.get("frames", []):
            path = (root/frame["filename"]).resolve()
            if root not in path.parents or hashlib.sha256(path.read_bytes()).hexdigest() != frame["sha256"]:
                raise RuntimeError("Native component bytes changed")
            result[frame["filename"]] = bounds(path)
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    print(json.dumps(collect(parser.parse_args().root)))
