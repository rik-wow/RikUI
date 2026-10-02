"""Current corpus inputs and per-component filtering cannot silently fall back."""
import json,tempfile,unittest
from pathlib import Path
from current_corpus import verified_source
from provenance import digest
from fixtures import scenario_script
class CurrentInputs(unittest.TestCase):
    def test_current_corpus_provenance_and_tampering(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);folder=root/"generated/corpus";folder.mkdir(parents=True)
            (folder/"corpus.xml").write_text("<Ui/>")
            identity={"product":"forever","build":"1.60.1.99999","locale":"enUS"}
            (root/"catalog.json").write_text(json.dumps({"identity":identity}))
            manifest={"identity":identity,"clientIndex":{"build":identity["build"]},"files":{"generated/corpus/corpus.xml":{"sha256":digest(folder/"corpus.xml")}}}
            (root/"manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(verified_source(root,{"version":identity["build"]}),folder)
            with self.assertRaises(RuntimeError):verified_source(root,{"version":"1.60.1.88888"})
            (folder/"corpus.xml").write_text("changed")
            with self.assertRaises(RuntimeError):verified_source(root,{"version":identity["build"]})
    def test_each_sequence_checks_its_actual_native_root(self):
        case={"id":"sample","frame":"UIParent","sequence":{"apply":"local choice=VALUE","frames":{"party":"RikUIParty"}}}
        text=scenario_script(case,{"core":""},None,"party")
        self.assertIn("RikRenderCheck(RikUIParty)",text)
        self.assertNotIn("RikRenderCheck(UIParent)",text)
if __name__=="__main__":unittest.main()
