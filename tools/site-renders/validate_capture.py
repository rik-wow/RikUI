"""Validate GPU captures and their native frame diagnostics, and composite UI layers over world plates."""
import re
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from schema import DEFAULT_SCREEN

NODE = re.compile(r'^(?P<indent> *)(?P<name>.+?) \[(?P<type>\w+)\] \((?P<w>[\d.]+)x(?P<h>[\d.]+)\).*? (?P<visible>visible|hidden) .*?x=(?P<x>[-\d.]+), y=(?P<y>[-\d.]+), alpha=(?P<alpha>[\d.]+)')
TEXT = re.compile(r' text="((?:\\.|[^"\\])*)"')
WORLD_QUALITY = 92

def screen_size(case):
    width, height = case.get("screen", DEFAULT_SCREEN).split("x")
    return int(width), int(height)

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
    screen_w, screen_h = screen_size(case)
    if x + width > screen_w or y + height > screen_h:
        raise RuntimeError(case["id"] + ": crop exceeds the screen")
    return root, width, height

def verify_pixels(case, image):
    """Reject empty output. A transparent UI layer is judged on its drawn pixels only, so a world plate
    can never hide a blank capture."""
    width, height = image.size
    if image.mode == "RGBA" and image.getchannel("A").getextrema()[0] == 0:
        alpha = image.getchannel("A")
        drawn = sum(count for count, value in alpha.getcolors(width * height) if value > 8)
        if drawn < width * height * 0.01:
            raise RuntimeError(case["id"] + ": empty or nearly blank capture")
        opaque = Image.composite(image.convert("RGB"), Image.new("RGB", image.size, "#ff00ff"), alpha.point(lambda a: 255 if a > 8 else 0))
        colors = [entry for entry in opaque.getcolors(width * height) if entry[1] != (255, 0, 255)]
    else:
        colors = image.convert("RGB").getcolors(width * height)
        if max(count for count, color in colors) > width * height * 0.985:
            raise RuntimeError(case["id"] + ": empty or nearly blank capture")
    if len(colors) < 30:
        raise RuntimeError(case["id"] + ": empty or nearly blank capture")
    return len(colors)

def validate_capture(case, image_path, log):
    nodes, texts = read_tree(case, log)
    root, width, height = verify_geometry(case, nodes)
    for expected in case.get("expectText", []):
        if not any(expected in text for text in texts):
            raise RuntimeError(case["id"] + ": missing visible text: " + expected)
    image = Image.open(image_path)
    if image.size != (width, height):
        raise RuntimeError(case["id"] + ": incorrect image dimensions")
    unique = verify_pixels(case, image)
    return {"visibleTextCount": len(texts), "root": {k: root[k] for k in ("x", "y", "w", "h")},
            "uniqueColors": unique}

def composite_world(layer_path, plate_path, case, output_path):
    """Put the premultiplied UI layer over the plate: out = layer + plate * (1 - alpha), then crop."""
    layer = Image.open(layer_path).convert("RGBA")
    width, height, x, y = map(int, re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", case["crop"]).groups())
    screen = screen_size(case)
    plate = Image.open(plate_path).convert("RGB")
    if plate.size != screen:
        plate = plate.resize(screen, Image.LANCZOS)
    plate = plate.crop((x, y, x + width, y + height))
    if layer.size != (width, height):
        raise RuntimeError(case["id"] + ": UI layer does not match the crop")
    alpha = layer.getchannel("A")
    keep = ImageChops.invert(alpha).convert("RGB")
    result = ImageChops.add(layer.convert("RGB"), ImageChops.multiply(plate, keep))
    result.save(output_path, format="WEBP", quality=WORLD_QUALITY, method=6)
    return result

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
