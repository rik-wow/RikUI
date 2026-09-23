-- Offline persistence regression using actual SavedVariables as isolated data.
-- Usage: lua tests/store-client-replay.lua <account.lua> <character.lua>
package.path="tests/?.lua;"..package.path
local env=require("wow_stub")
local loader=dofile("tests/load_addon.lua").Loadfile
local function database(path,key)
    local fn=assert(loadfile(assert(path,"SavedVariables path required")))
    local values={};setfenv(fn,values)
    if jit then jit.off(fn,true) end
    debug.sethook(function() error("SavedVariables instruction limit") end,"",1000000)
    local ok,why=pcall(fn);debug.sethook();assert(ok,why)
    return assert(values[key],"Missing database")
end
local account=database(arg[1],"RikUIDB")
local character=database(arg[2],"RikUICharDB")
local macros,cvars={},{}
C_CVar={RegisterCVar=function(name,value) if cvars[name]==nil then cvars[name]=value end end,
    GetCVar=function(name) return cvars[name] end,SetCVar=function(name,value) cvars[name]=value;return true end}
GetMacroInfo=function(name) if macros[name] then return name,"icon",macros[name] end end
CreateMacro=function(name,_,body) macros[name]=body;return 1 end
EditMacro=function(name,_,_,body) macros[name]=body;return 1 end
DeleteMacro=function(name) macros[name]=nil end
UnitName=function() return "Replay character" end;GetRealmName=function() return "Replay realm" end
local function boot(db,char)
    env.frames,env.printed,env.inCombat={}, {},false
    RikUI,RikUIDB,RikUICharDB=nil,db,char
    for _,file in ipairs({"src/core/core.lua","src/platform/hooks.lua","src/platform/hide.lua","src/ui/media.lua",
        "src/setup/setup.lua","src/setup/setup-apply.lua","src/layout/layout-geometry.lua","data/layouts.lua",
        "src/layout/layout-audit.lua","src/layout/layout.lua","src/layout/layout-rects.lua","src/ui/motion.lua",
        "src/ui/skin.lua","src/layout/layout-unlock.lua","src/layout/layout-drag.lua","src/layout/layout-presets.lua",
        "src/persistence/store.lua","src/persistence/store-macros.lua"}) do assert(loader(file))("RikUI",{}) end
    env.fire("ADDON_LOADED","RikUI");env.fire("PLAYER_LOGIN")
end
boot(account,character)
local store=RikUI.Store
local expectedAccount=store.Encode(store.Prune(account.profiles,RikUI.Defaults.profiles))
local expectedCharacter={}
for k,v in pairs(character) do if k~="questPlanMemory" then expectedCharacter[k]=v end end
local expected=assert(store.Encode(store.Prune(expectedCharacter,RikUI.Defaults.character)))
local memory=store.Encode(character.questPlanMemory)
local before=assert(store.Encode(store.Prune(character,RikUI.Defaults.character)))
store.Flush();store.FlushMacros()
assert(store.MacroStatus().used>0,"Restart backup was not written")
assert(store.Encode(store.Load(store.CharacterKey()).questPlanMemory)==memory,"Reload-tier memory changed")
assert(store.Encode(character.questPlanMemory)==memory,"Live learning was modified")
local used,reduced=store.MacroStatus().used,store.MacroStatus().learningReduced
local bytes=0;for _,body in pairs(macros) do assert(#body<=255);bytes=bytes+#body end
cvars={};boot(nil,nil)
assert(RikUI.Store.MacroStatus().restored,"Restart backup failed to restore")
local restored={}
for k,v in pairs(RikUI.CharDB) do if k~="questPlanMemory" then restored[k]=v end end
assert(RikUI.Store.Encode(RikUI.Store.Prune(restored,RikUI.Defaults.character))==expected,"Character settings changed")
assert(RikUI.Store.Encode(RikUI.Store.Prune(RikUI.DB.profiles,RikUI.Defaults.profiles))==expectedAccount,"Account profiles changed")
for _,line in ipairs(env.printed) do assert(not line:find("Settings store:",1,true),line) end
io.write("Original character delta bytes="..#before.."\n")
io.write("Actual settings survived macro save and restart; macros="..used..", body bytes="..bytes..", compacted learning="..reduced.."\n")
io.write("Original live learning unchanged; full reload-tier memory retained; no startup restore warnings\n")
