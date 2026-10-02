import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {execFileSync} from "node:child_process";
import {createEngine} from "./pack-engine.mjs";
import {sourcePaths} from "./pack-sources.mjs";
import {StudioModel} from "./studio-model.mjs";
const engine=()=>createEngine(sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8")));
const fixture=JSON.parse(readFileSync(new URL("../tests/studio-native-export.json",import.meta.url)));
test("actual native Export live output imports, preserves source and exports back into LuaJIT",()=>{
 const e=engine(),model=new StudioModel(e);model.choose("centered");model.import(fixture.code);
 assert.equal(model.source.title,"My RikUI setup");assert.ok(model.source.groups.chat);
 assert.deepEqual({...model.viewport},{height:1080,width:1920});
 const original=e.call("Encode",model.source);
 model.move("main",720,80);const result=model.export();
 assert.equal(e.call("Encode",model.source),original);
 // Feed the browser export as data on stdin; submitted content is never loaded as Lua.
 const native=execFileSync("luajit",["tests/studio-import-back.lua"],{cwd:new URL("../",import.meta.url),input:result,encoding:"utf8"});
 assert.match(native,/OK: browser pack imported/);
});
test("wrapped copy is accepted, incomplete copy explains missing characters and invalid data remains refused",()=>{
 const e=engine(),model=new StudioModel(e);model.choose("centered");
 model.import(fixture.code.match(/.{1,90}/g).join("\n"));
 assert.ok(model.source.groups.chat);
 assert.throws(()=>model.import(fixture.code.slice(0,-17)),/missing 17 characters/);
 const before=e.call("Encode",model.source);
 assert.throws(()=>model.import(fixture.code.slice(0,-1)+"x"));
 assert.equal(e.call("Encode",model.source),before);
});
