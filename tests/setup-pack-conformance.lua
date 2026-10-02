RikUI={Presets={},RegisterCommand=function() end,RegisterEvent=function() end}
for _,file in ipairs({"src/core/profile-schema.lua","src/persistence/codec.lua","src/setup/setup.lua","src/setup/preset-schema.lua","src/setup/setup-pack.lua","src/configuration/options/sharing.lua","tests/setup-pack-cases.lua"}) do dofile(file) end
local result=RikUI.SetupPack.Conformance()
for _,key in ipairs({"canonical","code","fitted","readable","update"}) do print(key.."="..result[key]) end
