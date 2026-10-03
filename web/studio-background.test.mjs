import test from "node:test";
import assert from "node:assert/strict";
import {coverCrop,paintBackground} from "./studio-background.mjs";
test("4K world cover-crops around its center without stretching across supported and portrait viewports",()=>{
 for(const [width,height]of [[3840,2160],[1920,1080],[2560,1440],[3440,1440],[1280,800],[1280,720],[390,844]]){
  const c=coverCrop(3840,2160,width,height);
  assert.ok(c.sx>=0&&c.sy>=0&&c.sw<=3840+1e-8&&c.sh<=2160+1e-8);
  assert.equal(c.sx+c.sw/2,1920);assert.equal(c.sy+c.sh/2,1080);
  assert.ok(Math.abs(c.sw/c.sh-width/height)<1e-9);
  assert.ok(Math.abs(width/c.sw-height/c.sh)<1e-9);
 }
 assert.deepEqual(coverCrop(3840,2160,1920,1080),{sx:0,sy:0,sw:3840,sh:2160,width:1920,height:1080});
 assert.throws(()=>coverCrop(3840,2160,0,100));
});
test("background failure and plain mode preserve editing without requiring image rendering",async()=>{
 let loads=0,draws=0;const ctx={canvas:{width:1280,height:800},fillRect(){},drawImage(){draws++;}};
 const load=async()=>{loads++;throw Error("offline");};
 assert.equal(await paintBackground(ctx,{url:"missing"},"plain",load),"plain");assert.equal(loads,0);
 assert.equal(await paintBackground(ctx,{url:"missing"},"world",load),"unavailable");assert.equal(draws,0);
 assert.equal(await paintBackground(ctx,{url:"ok"},"dim",async()=>({naturalWidth:3840,naturalHeight:2160})),"ready");assert.equal(draws,1);
 assert.equal(await paintBackground(ctx,{url:"late"},"world",async()=>({naturalWidth:3840,naturalHeight:2160}),()=>false),"superseded");assert.equal(draws,1);
});
