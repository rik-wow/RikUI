"""Build the original RikUI flat textures as uncompressed, 32-bit TGA.
Run: python media/build_textures.py
--check compares committed bytes without writing.
"""
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parent
SIZE = 32


def texture(name):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            alpha = 255
            if name == "highlight":
                alpha = 32
            elif name == "ring":
                alpha = 255 if min(x, y, SIZE - x - 1, SIZE - y - 1) < 2 else 0
            pixels.extend((255, 255, 255, alpha))
    return header + pixels


for name in ("statusbar", "border", "ring", "highlight"):
    target = ROOT / (name + ".tga")
    data = texture(name)
    if "--check" in sys.argv:
        assert target.read_bytes() == data, "Unexpected texture bytes: " + str(target)
    else:
        target.write_bytes(data)
print("Four 32x32 BGRA textures " + ("verified" if "--check" in sys.argv else "built"))
