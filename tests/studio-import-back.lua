RikUI={Presets={},RegisterCommand=function()end,RegisterEvent=function()end}
for _,file in ipairs({"src/core/layout-metrics.lua","src/core/profile-schema.lua","src/persistence/codec.lua","src/setup/setup.lua","src/setup/preset-schema.lua","src/setup/setup-pack.lua","data/layouts.lua","src/setup/setup-pack-library.lua","src/configuration/options/sharing.lua"})do dofile(file)end
local value,reason=RikUI.SetupPack.Import(io.read("*a"));assert(value,reason)
assert(value.groups.chat and value.adjustments.positions.main)
print("OK: browser pack imported")
