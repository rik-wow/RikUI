"""Validate GPU captures and their native frame diagnostics."""
import re
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

NODE = re.compile(r'^(?P<indent> *)(?P<name>.+?) \[(?P<type>\w+)\] \((?P<w>[\d.]+)x(?P<h>[\d.]+)\).*? (?P<visible>visible|hidden) .*?x=(?P<x>[-\d.]+), y=(?P<y>[-\d.]+), alpha=(?P<alpha>[\d.]+)')
TEXT = re.compile(r' text="((?:\\.|[^"\\])*)"')

def read_tree(case, log):
    tree = log.split("=== Frame Tree ===", 1)[-1]
    nodes, texts = [], []
    for line in tree.splitlines():
        match = NODE.search(line)
        if not match:
            continue
        node = match.groupdict()
        for key in ("w", "h", "x", "y", "alpha"):
            node[key] = float(node[key])
        nodes.append(node)
        text = TEXT.search(line)
        if text and node["visible"] == "visible" and node["alpha"] > 0.05:
            if node["w"] <= 0 or node["h"] <= 0:
                raise RuntimeError(case["id"] + ": visible text has no area: " + text[1][:80])
            texts.append(text[1])
    return nodes, texts

def verify_geometry(case, nodes):
    root = next((n for n in nodes if n["name"] == case["frame"] and not n["indent"]), None)
    if not root or root["visible"] != "visible" or root["alpha"] < 0.5:
        raise RuntimeError(case["id"] + ": root missing or hidden in native diagnostics")
    width, height, x, y = map(int, re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", case["crop"]).groups())
    if root["w"] <= 0 or root["h"] <= 0:
        raise RuntimeError(case["id"] + ": root has no area")
    if root["x"] < x - 1 or root["y"] < y - 1 or root["x"] + root["w"] > x + width + 1 or root["y"] + root["h"] > y + height + 1:
        raise RuntimeError(case["id"] + ": crop clips the root")
    return root, width, height

def validate_capture(case, image_path, log):
    nodes, texts = read_tree(case, log)
    root, width, height = verify_geometry(case, nodes)
    for expected in case.get("expectText", []):
        if not any(expected in text for text in texts):
            raise RuntimeError(case["id"] + ": missing visible text: " + expected)
    image = Image.open(image_path).convert("RGB")
    if image.size != (width, height):
        raise RuntimeError(case["id"] + ": incorrect image dimensions")
    colors = image.getcolors(width * height)
    if len(colors) < 30 or max(count for count, color in colors) > width * height * 0.985:
        raise RuntimeError(case["id"] + ": empty or nearly blank capture")
    return {"visibleTextCount": len(texts), "root": {k: root[k] for k in ("x", "y", "w", "h")},
            "uniqueColors": len(colors)}

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

