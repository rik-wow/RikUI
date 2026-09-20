"""Build RikUI's icons: media/icons/*.svg -> media/icons/*.tga.

The SVG files are the source of truth. The WoW client cannot load SVG (only TGA and BLP), so this
script rasterises them to white 32x32 BGRA TGA with the shape in the alpha channel; the addon tints
them with SetVertexColor. It renders the small SVG subset the icons use, so no SVG library is
needed, only Pillow for drawing and resampling:

  elements   path (M L H V C Q Z, absolute and relative), rect (rx), circle, line, polyline, polygon
  painting   fill, stroke, stroke-width, inherited from the <svg> element; caps and joins are round

Run:    python media/build_icons.py
Check:  python media/build_icons.py --check   (compares the committed bytes, writes nothing)
"""
from pathlib import Path
import re
import struct
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent / "icons"
SIZE, SUPERSAMPLE, CURVE_STEPS = 32, 8, 20
CANVAS = SIZE * SUPERSAMPLE
TOKEN = re.compile(r"([MmLlHhVvCcQqZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)")
ARGUMENTS = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "Q": 4, "Z": 0}


def cubic(p0, p1, p2, p3):
    points = []
    for step in range(1, CURVE_STEPS + 1):
        t = step / CURVE_STEPS
        u = 1 - t
        points.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                       u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return points


def quadratic(p0, p1, p2):
    return cubic(p0, (p0[0] + 2 / 3 * (p1[0] - p0[0]), p0[1] + 2 / 3 * (p1[1] - p0[1])),
                 (p2[0] + 2 / 3 * (p1[0] - p2[0]), p2[1] + 2 / 3 * (p1[1] - p2[1])), p2)


def segment(command, values, current, relative):
    """The points one path command adds, given the current point."""
    ox, oy = current if relative else (0.0, 0.0)
    if command == "H":
        return [(values[0] + ox, current[1])]
    if command == "V":
        return [(current[0], values[0] + oy)]
    pairs = [(values[i] + ox, values[i + 1] + oy) for i in range(0, len(values), 2)]
    if command == "C":
        return cubic(current, *pairs)
    if command == "Q":
        return quadratic(current, *pairs)
    return pairs


def parse_path(data):
    """Subpaths as (points, closed)."""
    tokens = [(match.group(1), match.group(2)) for match in TOKEN.finditer(data)]
    subpaths, points, index, command, current = [], [], 0, None, (0.0, 0.0)
    while index < len(tokens):
        letter, _ = tokens[index]
        if letter:
            command, index = letter, index + 1
        upper = command.upper()
        if upper == "Z":
            subpaths.append((points, True))
            current, points = (points[0] if points else current), []
            continue
        count = ARGUMENTS[upper]
        values = [float(tokens[index + offset][1]) for offset in range(count)]
        index += count
        if upper == "M":
            if points:
                subpaths.append((points, False))
            added = segment("M", values, current, command.islower())
            points, command = list(added), ("l" if command.islower() else "L")
        else:
            added = segment(upper, values, current, command.islower())
            points.extend(added)
        current = added[-1]
    if points:
        subpaths.append((points, False))
    return subpaths


def shapes(element):
    """The element as subpaths, or a ('circle' | 'rect', ...) primitive Pillow draws better itself."""
    tag = element.tag.split("}")[-1]
    number = lambda key, default=0.0: float(element.get(key, default))
    if tag == "path":
        return parse_path(element.get("d", ""))
    if tag == "line":
        return [([(number("x1"), number("y1")), (number("x2"), number("y2"))], False)]
    if tag in ("polyline", "polygon"):
        values = [float(value) for value in re.split(r"[\s,]+", element.get("points", "").strip()) if value]
        return [(list(zip(values[0::2], values[1::2])), tag == "polygon")]
    if tag == "circle":
        return [("circle", number("cx"), number("cy"), number("r"))]
    if tag == "rect":
        return [("rect", number("x"), number("y"), number("width"), number("height"), number("rx"))]
    return []


def paint(element, root):
    fill = element.get("fill", root.get("fill", "none"))
    stroke = element.get("stroke", root.get("stroke", "none"))
    width = float(element.get("stroke-width", root.get("stroke-width", 1)))
    return fill != "none", stroke != "none", width


def draw_primitive(draw, shape, scale, filled, stroked, width):
    half = width * scale / 2 if stroked else 0
    if shape[0] == "circle":
        _, cx, cy, radius = shape
        box = [(cx - radius) * scale - half, (cy - radius) * scale - half,
               (cx + radius) * scale + half, (cy + radius) * scale + half]
        draw.ellipse(box, fill=255 if filled else None, outline=255 if stroked else None, width=round(width * scale))
        return
    _, x, y, w, h, rx = shape
    box = [x * scale - half, y * scale - half, (x + w) * scale + half, (y + h) * scale + half]
    draw.rounded_rectangle(box, radius=rx * scale + half, fill=255 if filled else None,
                           outline=255 if stroked else None, width=round(width * scale))


def draw_subpath(draw, points, closed, scale, filled, stroked, width):
    scaled = [(x * scale, y * scale) for x, y in points]
    if filled and len(scaled) >= 3:
        draw.polygon(scaled, fill=255)
    if not stroked:
        return
    line = scaled + [scaled[0]] if closed else scaled
    pixels = width * scale
    draw.line(line, fill=255, width=round(pixels), joint="curve")
    for x, y in line:  # round caps and joins
        draw.ellipse([x - pixels / 2, y - pixels / 2, x + pixels / 2, y + pixels / 2], fill=255)


def render(path):
    root = ET.parse(path).getroot()
    view = [float(value) for value in root.get("viewBox", "0 0 24 24").split()]
    scale = CANVAS / view[2]
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(mask)
    for element in root.iter():
        if element is root:
            continue
        filled, stroked, width = paint(element, root)
        for shape in shapes(element):
            if isinstance(shape[0], str):
                draw_primitive(draw, shape, scale, filled, stroked, width)
            else:
                draw_subpath(draw, shape[0], shape[1], scale, filled, stroked, width)
    return mask.resize((SIZE, SIZE), Image.LANCZOS)


def tga(mask):
    """Uncompressed 32-bit BGRA, bottom-left origin like the other RikUI textures: white, alpha = shape."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    pixels = bytearray()
    for y in range(SIZE - 1, -1, -1):
        for x in range(SIZE):
            pixels.extend((255, 255, 255, mask.getpixel((x, y))))
    return header + bytes(pixels)


def main():
    check, sources = "--check" in sys.argv, sorted(ROOT.glob("*.svg"))
    assert sources, "No SVG sources in " + str(ROOT)
    for source in sources:
        data, target = tga(render(source)), source.with_suffix(".tga")
        if check:
            assert target.exists() and target.read_bytes() == data, "Out of date: " + target.name
        else:
            target.write_bytes(data)
    print(f"{len(sources)} icons " + ("verified" if check else "built") + f" at {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()
