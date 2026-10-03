"""Paint bounds are read from authenticated image alpha, never synthesized."""
import hashlib, json, tempfile, unittest
from pathlib import Path
from PIL import Image
from paint_bounds import bounds, collect
class PaintBoundsChecks(unittest.TestCase):
    def test_child_paint_beyond_holder_is_retained(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/"native.webp"
            image=Image.new("RGBA",(100,80))
            image.paste((255,255,255,255),(10,12,70,60))
            image.save(path,lossless=True)
            self.assertEqual(bounds(path),{"x":10,"y":12,"width":60,"height":48})
    def test_empty_sample_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/"empty.webp";Image.new("RGBA",(20,20)).save(path,lossless=True)
            with self.assertRaisesRegex(RuntimeError,"Empty"): bounds(path)
    def test_only_authenticated_component_bytes_are_accepted(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);path=root/"native.webp";Image.new("RGBA",(20,20),(1,2,3,255)).save(path,lossless=True)
            frame={"filename":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
            manifest={"renders":[{"id":"studio-extra-classic-standard","frames":[frame]}]}
            (root/"manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(collect(root)[path.name]["width"],20)
            frame["sha256"]="bad";(root/"manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(RuntimeError,"bytes changed"):collect(root)
    def test_paths_outside_capture_root_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/"captures";root.mkdir()
            manifest={"renders":[{"id":"studio-extra-test","frames":[{"filename":"../private.webp","sha256":"bad"}]}]}
            (root/"manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(RuntimeError,"bytes changed"):collect(root)
    def test_reviewed_crop_preserves_exact_pixels_geometry_and_safe_filename(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);source=Image.new("RGBA",(200,120),(0,0,0,0))
            # Generic encoder failure fixture, never a game UI baseline.
            source.putpixel((17,21),(210,44,99,123));source.putpixel((80,40),(31,152,224,255))
            path=root/"atlas@chat.webp";source.save(path,lossless=True,exact=True)
            manifest={"renders":[{"id":"studio-extra-test","frames":[{"filename":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}]}]}
            (root/"manifest.json").write_text(json.dumps(manifest))
            result=collect(root,root/"public")[path.name];bitmap=result["bitmap"]
            self.assertEqual((result["x"],result["y"],result["width"],result["height"]),(17,21,64,20))
            self.assertNotIn("@",bitmap["filename"])
            raw=(root/"public"/bitmap["filename"]).read_bytes();self.assertEqual(hashlib.sha256(raw).hexdigest(),bitmap["sha256"])
            cropped=Image.open(root/"public"/bitmap["filename"]).convert("RGBA")
            self.assertEqual(cropped.tobytes(),source.crop((17,21,81,41)).tobytes())
            self.assertEqual((root/"manifest.json").read_text(),json.dumps(manifest))
            path.write_bytes(b"tampered");self.assertRaises(RuntimeError,collect,root,root/"public")
if __name__=="__main__":unittest.main()
