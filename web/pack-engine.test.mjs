import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync,readdirSync} from "node:fs";
import {execFileSync} from "node:child_process";
import {createEngine} from "./pack-engine.mjs";
import {sourcePaths} from "./pack-sources.mjs";
export const sources=sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8"));
test("Exact shared Lua resolves packs identically in browser VM and LuaJIT",()=>{
 const engine=createEngine([...sources,readFileSync(new URL("../tests/setup-pack-cases.lua",import.meta.url),"utf8")]);
 const actual=engine.call("Conformance");
 const native=Object.fromEntries(execFileSync("luajit",["tests/setup-pack-conformance.lua"],{cwd:new URL("../",import.meta.url),encoding:"utf8"}).trim().split(/\r?\n/).map(line=>{const i=line.indexOf("=");return [line.slice(0,i),line.slice(i+1)];}));
 assert.deepEqual({...actual},native);
});
test("Every registered addon module can round-trip; only proven retired flags are canonicalized",()=>{
 const engine=createEngine(sources),root=new URL("../src/",import.meta.url),modules={};
 function scan(path){for(const entry of readdirSync(path,{withFileTypes:true})){const file=new URL(entry.name+(entry.isDirectory()?"/":""),path);if(entry.isDirectory())scan(file);else if(entry.name.endsWith(".lua"))for(const m of readFileSync(file,"utf8").matchAll(/core:RegisterModule\("([^"]+)"/g))modules[m[1]]=true;}}
 scan(root);assert.ok(Object.keys(modules).length>40);
 const p=engine.call("Bundled","centered");p.profile.modules=modules;
 p.profile.modules.classcooldowns=false;p.profile.modules.cooldownviewer=true;p.profile.modules.cooldowns=false;
 const code=engine.call("Encode",p),clean=engine.call("Decode",code);
 assert.equal(clean.profile.modules.classcooldowns,undefined);assert.equal(clean.profile.modules.cooldownviewer,undefined);
 assert.equal(clean.profile.modules.cooldowns,false);assert.equal(p.profile.modules.classcooldowns,false);
 clean.profile.modules.futureUnknown=true;assert.throws(()=>engine.call("Validate",clean));
});
test("User Lua and unbounded content cannot execute",()=>{
 const engine=createEngine(sources);
 assert.throws(()=>engine.call("Decode","return os.execute('x')"));
 assert.throws(()=>engine.call("Decode","x".repeat(16000)));
 assert.throws(()=>engine.call("Validate",{profile:{scale:Infinity}}));
});
