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

def collect(root, crop_out=None):
    if crop_out:
        crop_out = Path(crop_out).resolve()
        crop_out.mkdir(parents=True, exist_ok=True)
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
            paint = bounds(path)
            result[frame["filename"]] = paint
            if crop_out:
                image = Image.open(path).convert("RGBA")
                box = (paint["x"], paint["y"], paint["x"]+paint["width"], paint["y"]+paint["height"])
                cropped = image.crop(box)
                from io import BytesIO
                encoded = BytesIO()
                cropped.save(encoded, format="WEBP", lossless=True, exact=True)
                raw = encoded.getvalue()
                if Image.open(BytesIO(raw)).convert("RGBA").tobytes() != cropped.tobytes():
                    raise RuntimeError("Public sprite changed reviewed pixels")
                digest = hashlib.sha256(raw).hexdigest()
                filename = path.stem.replace("@", "-")+"-paint-"+digest[:12]+".webp"
                (crop_out/filename).write_bytes(raw)
                paint["bitmap"] = {"filename": filename, "sha256": digest, "width": cropped.width, "height": cropped.height}

    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--crop-out", type=Path)
    args = parser.parse_args()
    print(json.dumps(collect(args.root, args.crop_out)))
