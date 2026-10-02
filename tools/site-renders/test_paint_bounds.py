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
if __name__=="__main__":unittest.main()
