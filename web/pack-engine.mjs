import { lua, lauxlib, lualib, to_luastring, to_jsstring } from "fengari";
// Only trusted repository Lua is loaded. Submitted content goes through Codec.Decode, never load().
export function createEngine(sources) {
 const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
 function execute(source) {
  if(lauxlib.luaL_loadstring(L,to_luastring(source))!==lua.LUA_OK || lua.lua_pcall(L,0,0,0)!==lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L,-1)));
 }
 execute("RikUI={Presets={},RegisterCommand=function() end,RegisterEvent=function() end}; unpack=table.unpack");
 for(const source of sources)execute(source);
 function push(value,depth=0) {
  if(depth>32)throw Error("Configuration nesting exceeds capacity");
  if(value===undefined || value===null)lua.lua_pushnil(L);
  else if(typeof value==="boolean")lua.lua_pushboolean(L,value);
  else if(typeof value==="number"){if(!Number.isFinite(value))throw Error("Invalid number");lua.lua_pushnumber(L,value);}
  else if(typeof value==="string")lua.lua_pushstring(L,to_luastring(value));
  else if(typeof value==="object"){lua.lua_newtable(L);for(const [key,v]of Object.entries(value)){if(["__proto__","constructor","prototype"].includes(key))throw Error("Invalid key");push(Array.isArray(value)?Number(key)+1:key,depth+1);push(v,depth+1);lua.lua_settable(L,-3);}}
  else throw Error("Configuration must be data");
 }
 function take(index,depth=0){
  if(depth>32)throw Error("Result nesting exceeds capacity");
  index=lua.lua_absindex(L,index);
  switch(lua.lua_type(L,index)){
   case lua.LUA_TNIL:return undefined;
   case lua.LUA_TBOOLEAN:return lua.lua_toboolean(L,index);
   case lua.LUA_TNUMBER:return lua.lua_tonumber(L,index);
   case lua.LUA_TSTRING:return to_jsstring(lua.lua_tostring(L,index));
   case lua.LUA_TTABLE:{
    const r=Object.create(null);lua.lua_pushnil(L);
    while(lua.lua_next(L,index)){const k=take(-2,depth+1);if(["__proto__","constructor","prototype"].includes(String(k)))throw Error("Invalid key");r[k]=take(-1,depth+1);lua.lua_pop(L,1);}
    const keys=Object.keys(r);if(keys.length && keys.every((k,i)=>String(i+1)===k))return keys.map(k=>r[k]);return r;
   }
   default:throw Error("Unexpected Lua output");
  }
 }
 const copyMemo=value=>Array.isArray(value)?value.map(copyMemo):value&&typeof value==="object"?Object.assign(Object.create(Object.getPrototypeOf(value)),Object.fromEntries(Object.entries(value).map(([k,v])=>[k,copyMemo(v)]))):value;
 const memo=new Map(),pure=new Set(["Theme","Equal","GroupEnabled","ModuleEnabled"]);
 return {call(method,...args){
  const cacheKey=pure.has(method)?JSON.stringify([method,...args]):undefined;
  if(cacheKey&&memo.has(cacheKey))return copyMemo(memo.get(cacheKey));
  lua.lua_settop(L,0);lua.lua_getglobal(L,to_luastring("RikUI"));lua.lua_getfield(L,-1,to_luastring("SetupPack"));lua.lua_getfield(L,-1,to_luastring(method));
  if(!lua.lua_isfunction(L,-1))throw Error("Unknown pack operation");
  for(const arg of args)push(arg);
  if(lua.lua_pcall(L,args.length,2,0)!==lua.LUA_OK){const reason=take(-1);lua.lua_settop(L,0);throw Error(reason);}
  const result=take(-2),reason=take(-1);lua.lua_settop(L,0);if(result===undefined)throw Error(reason||"Pack operation failed");
  if(cacheKey){if(memo.size>=256)memo.delete(memo.keys().next().value);memo.set(cacheKey,copyMemo(result));}
  return result;
 }};
}
