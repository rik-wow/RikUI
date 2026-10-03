"""Composite an authentic capture for visual review; never modifies/promotes its source."""
import argparse
from pathlib import Path
from PIL import Image
from provenance import digest
p=argparse.ArgumentParser();p.add_argument("images",nargs="+",type=Path);p.add_argument("--output",type=Path,required=True);p.add_argument("--crop-alpha",action="store_true")
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
for source in a.images:
    layer=Image.open(source).convert("RGBA")
    background=Image.new("RGBA",layer.size,(11,18,22,255))
    background.alpha_composite(layer)
    if a.crop_alpha:
        bounds=layer.getchannel("A").getbbox()
        if bounds:background=background.crop(bounds) # exact source pixels; never scale
    target=a.output/(source.stem+".png");background.convert("RGB").save(target)
    print(source.name,digest(source),target)
