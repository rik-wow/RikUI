// Public addon code only; no Blizzard source, private client data or submitted Lua.
export const sourcePaths=[
 "src/core/layout-metrics.lua","src/core/profile-schema.lua","src/persistence/codec.lua",
 "data/spells.lua",...["hunter","mage","rogue","priest","warlock","shaman","paladin","druid"].map(c=>"data/spells-"+c+".lua"),"data/racials.lua",
 "src/setup/setup.lua","src/setup/preset-schema.lua","src/setup/setup-pack.lua",
 "data/layouts.lua","src/setup/setup-pack-library.lua","src/configuration/options/sharing.lua"
];
