import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {execFileSync} from "node:child_process";
import {createEngine} from "./pack-engine.mjs";
export const sourcePaths=["src/core/profile-schema.lua","src/persistence/codec.lua","src/setup/setup.lua","src/setup/preset-schema.lua","src/setup/setup-pack.lua","src/configuration/options/sharing.lua"];
export const sources=sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8"));
test("Exact shared Lua resolves packs identically in browser VM and LuaJIT",()=>{
 const engine=createEngine([...sources,readFileSync(new URL("../tests/setup-pack-cases.lua",import.meta.url),"utf8")]);
 const actual=engine.call("Conformance");
 const native=Object.fromEntries(execFileSync("luajit",["tests/setup-pack-conformance.lua"],{cwd:new URL("../",import.meta.url),encoding:"utf8"}).trim().split(/\r?\n/).map(line=>{const i=line.indexOf("=");return [line.slice(0,i),line.slice(i+1)];}));
 assert.deepEqual({...actual},native);
});
test("User Lua and unbounded content cannot execute",()=>{
 const engine=createEngine(sources);
 assert.throws(()=>engine.call("Decode","return os.execute('x')"));
 assert.throws(()=>engine.call("Decode","x".repeat(16000)));
 assert.throws(()=>engine.call("Validate",{profile:{scale:Infinity}}));
});
