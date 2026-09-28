"""Put a transparent UI layer over a world plate. This file's digest is part of every world capture's provenance."""
import re
from PIL import Image, ImageChops
from validate_capture import screen_size

WORLD_QUALITY = 92

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
    # A premultiplied pixel never carries more light than its coverage. The lossless WebP encoder may
    # store any colour under alpha 0 (and round near it), so the layer's colour is clamped to its alpha.
    coverage = Image.merge("RGB", (alpha, alpha, alpha))
    light = ImageChops.darker(layer.convert("RGB"), coverage)
    keep = ImageChops.invert(alpha).convert("RGB")
    result = ImageChops.add(light, ImageChops.multiply(plate, keep))
    result.save(output_path, format="WEBP", quality=WORLD_QUALITY, method=6)
    return result
