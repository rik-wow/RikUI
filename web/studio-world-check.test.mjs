import test from "node:test";
import assert from "node:assert/strict";
import {reviewedWorld,validateWorld} from "./studio-world-check.mjs";
test("only the exact reviewed UI-free 4K world with renderer and current-input provenance is distributable",async()=>{
 const {record,raw}=await reviewedWorld();assert.equal(validateWorld(record,raw).raw,raw);
 for(const mutate of [
  r=>r.reviewedSHA256="0".repeat(64),r=>r.request.realm=true,r=>r.app.dirty.push("src/native/scene.ts"),
  r=>r.width=1920,r=>delete r.inputs.identity.uiHead,r=>delete r.inputs.manifestSHA256,r=>r.file="../private.jpg"
 ]){const altered=structuredClone(record);mutate(altered);assert.throws(()=>validateWorld(altered,raw));}
 const altered=Buffer.from(raw);altered[0]^=1;assert.throws(()=>validateWorld(record,altered),/bytes changed/);
});
