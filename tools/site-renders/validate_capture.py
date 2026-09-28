"""Validate GPU captures and their native frame diagnostics. This file's digest is part of every capture's provenance."""
import re
from pathlib import Path
from PIL import Image
from schema import DEFAULT_SCREEN

NODE = re.compile(r'^(?P<indent> *)(?P<name>.+?) \[(?P<type>\w+)\] \((?P<w>[\d.]+)x(?P<h>[\d.]+)\).*? (?P<visible>visible|hidden) .*?x=(?P<x>[-\d.]+), y=(?P<y>[-\d.]+), alpha=(?P<alpha>[\d.]+)')
TEXT = re.compile(r' text="((?:\\.|[^"\\])*)"')

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
    # The simulator lists a built-in placeholder before some Blizzard frames of the same name.
    candidates = [n for n in nodes if n["name"] == case["frame"] and not n["indent"]]
    root = next((n for n in candidates if n["visible"] == "visible"), candidates[0] if candidates else None)
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
        # A thin cue (two proc lines) covers under one percent of its crop; an empty layer covers none.
        drawn = sum(count for count, value in alpha.getcolors(width * height) if value > 8)
        if drawn < width * height * 0.002:
            raise RuntimeError(case["id"] + ": empty or nearly blank capture")
        # A drawn layer may be one colour (two gold proc lines); coverage is the blank test here.
        return len(image.getcolors(width * height))
    else:
        colors = image.convert("RGB").getcolors(width * height)
        if max(count for count, color in colors) > width * height * 0.985:
            raise RuntimeError(case["id"] + ": empty or nearly blank capture")
    # A flat control (five empty combo pips: backing, fill and edge) has three colours; an empty
    # capture has one or two, and the dominance check above catches a lone speck.
    if len(colors) < 3:
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
