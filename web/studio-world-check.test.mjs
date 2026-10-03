import test from "node:test";
import assert from "node:assert/strict";
import {reviewedWorld,validateWorld} from "./studio-world-check.mjs";
test("only the exact reviewed user-supplied screenshot with honest source provenance is distributable",async()=>{
 const {record,raw}=await reviewedWorld();assert.equal(validateWorld(record,raw).raw,raw);
 assert.equal(record.sha256,"212b21a4c6745595bbb84f1bb2e84845c851bfcf4ff39221f71bd6ec687edd7d");
 assert.equal(record.source.filename,"WoWScrnShot_092726_120706.jpg");
 for(const mutate of [
  r=>r.reviewedSHA256="0".repeat(64),r=>r.source.kind="world-renderer",r=>delete r.reviewedAt,
  r=>r.width=1920,r=>delete r.source.filename,r=>r.file="../private.jpg"
 ]){const altered=structuredClone(record);mutate(altered);assert.throws(()=>validateWorld(altered,raw));}
 const altered=Buffer.from(raw);altered[0]^=1;assert.throws(()=>validateWorld(record,altered),/bytes changed/);
});
