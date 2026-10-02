import test from "node:test";
import assert from "node:assert/strict";
import {paintPlacement,fitDetails,sampleShown,sampleEnabled} from "./studio-preview.mjs";
test("paint extents retain native children beyond a holder without stretching its root",()=>{
 const c={x:100,y:100,width:200,height:18,atlasHeight:300,paint:{x:98,y:180,width:204,height:34}};
 const p=paintPlacement(c,{x:600,y:80,width:230,height:21},1.15,800);
 assert.equal(p.sx,98);assert.equal(p.sy,180);assert.equal(p.width,204);assert.equal(p.height,34);
 for(const [key,value] of Object.entries({x:597.7,y:697,drawWidth:234.6,drawHeight:39.1}))assert.ok(Math.abs(p[key]-value)<1e-9,key);
 // Reputation below the XP holder is retained; paint size never follows the declared reserve.
 assert.ok(p.y+p.drawHeight>800-80);
});
test("fit annotations explain invisible footprints, safe gaps and specialist reservations",()=>{
 const viewport={width:1000,height:700};
 const groups=[{key:"Reserved specialist area",rect:{x:8,y:500,width:320,height:180}},{key:"chat",rect:{x:16,y:16,width:438,height:214}},{key:"castfocus",rect:{x:450,y:30,width:160,height:22}}];
 const details=fitDetails({groups,conflicts:[{key:"castfocus",reason:"Personal position conflicts"}]},viewport);
 assert.deepEqual(details[0].with,["chat"]);assert.match(details[0].reason,/Chat/);
 const reserved=fitDetails({groups:[groups[0],{key:"player",rect:{x:16,y:600,width:220,height:44}}],conflicts:[{key:"player",reason:"Crowded or off-screen"}]},viewport);
 assert.match(reserved[0].reason,/Reserved specialist area/);
 const outside=fitDetails({groups:[{key:"main",rect:{x:-10,y:5,width:498,height:36}}],conflicts:[{key:"main",reason:"Personal position conflicts"}]},viewport);
 assert.match(outside[0].reason,/safe edge/);
 const floating=fitDetails({groups:[groups[1],{...groups[2],floating:true}],conflicts:[{key:"castfocus",reason:"Below readable minimum"}]},viewport);
 assert.deepEqual(floating[0].with,[]);assert.match(floating[0].reason,/readable/);
});
test("scene visibility keeps inventory and inactive samples out of exploration while retaining selected previews",()=>{
 assert.equal(sampleShown("bags","exploration","main"),false);
 assert.equal(sampleShown("bags","town","main"),true);
 assert.equal(sampleShown("casttarget","exploration","main"),false);
 assert.equal(sampleShown("casttarget","exploration","casttarget"),true);
 assert.equal(sampleShown("loot","exploration","main",true),true);
 assert.equal(sampleShown("chat","exploration","main"),true);
 assert.equal(sampleEnabled("chat",{modules:{chat:false}}),false);
 assert.equal(sampleEnabled("main",{modules:{bars:false}}),false);
 assert.equal(sampleEnabled("main",{presentation:{hidden:{main:true}}}),false);
});
