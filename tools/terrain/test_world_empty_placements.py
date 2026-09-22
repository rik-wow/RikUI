"""Adversarial empty-placement proofs and optional pinned real-source audit."""
import argparse,json,pathlib,sys,unittest
from unittest.mock import patch
import world_empty_placements as policy
import world_placements as placements
from test_m2_world import fixture,chunk,PROFILE_SHA
class Tests(unittest.TestCase):
    def test_exact_empty_only(self):
        data=fixture(empty=True)
        with patch.dict(policy.PINS,{1:(policy.terrain.digest(data),(96,))},clear=True):
            self.assertTrue(policy.empty_mddf(dict(reference=1,flags=96),data))
            for row,payload in ((dict(reference=2,flags=96),data),(dict(reference=1,flags=100),data),(dict(reference=1,flags=96),data+b"x")):
                with self.assertRaisesRegex(ValueError,"unsupported-world-MDDF"):policy.empty_mddf(row,payload)
    def test_arrays_and_each_physics_chunk_rejected(self):
        for data in [fixture()]+[fixture(empty=True,extras=chunk(tag,b"")) for tag in policy.collision.EXTRA_PHYSICS]:
            with patch.dict(policy.PINS,{1:(policy.terrain.digest(data),(96,))},clear=True):
                with self.assertRaisesRegex(ValueError,"proof-contradiction"):policy.empty_mddf(dict(reference=1,flags=96),data)
    def test_index_binds_policy(self):
        self.assertEqual(placements.decoder_hashes()["emptyPlacements"],policy.terrain.digest(pathlib.Path(policy.__file__).read_bytes()))
    def test_unknown_does_not_gain_extent(self):
        data=fixture(empty=True)
        with patch.dict(policy.PINS,{},clear=True):
            with self.assertRaises(ValueError):policy.empty_mddf(dict(reference=1,flags=96),data)
def audit(profile_path,reference_path):
    raw=pathlib.Path(profile_path).read_bytes()
    if policy.terrain.digest(raw)!=PROFILE_SHA:raise ValueError("source profile changed")
    refraw=pathlib.Path(reference_path).read_bytes()
    if policy.terrain.digest(refraw)!=policy.REFERENCE_SHA:raise ValueError("reference changed")
    reference=json.loads(refraw);refs={r["fileDataID"]:r for r in reference["records"]}
    if reference["failed"] or reference["total"]!=17 or set(refs)!=set(policy.PINS) or reference["referenceCommit"]!=policy.terrain.PIN:
        raise ValueError("reference scope mismatch")
    files={r["fileDataID"]:r for r in json.loads(raw)["files"]}
    checks=0
    for ident,(digest,flags) in policy.PINS.items():
        source=files[ident];ref=refs[ident];data=pathlib.Path(source["path"]).read_bytes()
        if source["sha256"]!=digest or ref["sha256"]!=digest or ref["remainingBytes"] or len(data)!=ref["bytes"]:
            raise ValueError("source identity mismatch")
        if ref["collisionPositions"] or ref["collisionIndices"] or ref["collisionNormals"]:
            raise ValueError("reference is not empty")
        for flag in flags:
            policy.empty_mddf(dict(reference=ident,flags=flag),data);checks+=1
    return dict(exactModels=len(refs),exactModelFlagPairs=checks,referenceSHA256=policy.REFERENCE_SHA,nativeVerified=False)
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--profile");p.add_argument("--reference");args=p.parse_args()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
    if not result.wasSuccessful():sys.exit(1)
    if args.profile or args.reference:
        if not args.profile or not args.reference:p.error("profile and reference required together")
        print(json.dumps(audit(args.profile,args.reference)))
