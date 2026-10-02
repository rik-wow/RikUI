RikUI={Presets={},RegisterCommand=function()end,RegisterEvent=function()end}
for _,f in ipairs({"src/core/profile-schema.lua","src/persistence/codec.lua","src/setup/setup.lua","src/setup/preset-schema.lua","src/setup/setup-pack.lua","data/layouts.lua","src/setup/setup-pack-library.lua"})do dofile(f)end
for _,name in ipairs(RikUI.Layouts.Order)do
 local source=assert(RikUI.SetupPack.Bundled(name));local original=assert(RikUI.SetupPack.Encode(source))
 for _,screen in ipairs({{width=1920,height=1080},{width=3440,height=1440},{width=1280,height=800}})do
  local r=assert(RikUI.SetupPack.Resolve(source,{viewport=screen,device=screen.width<1400 and "handheld" or "desktop"}))
  if screen.width>=1920 then assert(#r.conflicts==0,"desktop pack must fit") end
  print(name.." "..screen.width.."x"..screen.height.." "..#r.conflicts.." conflicts")
  assert(original==RikUI.SetupPack.Encode(source),"fit rewrote source")
  for _,c in ipairs(r.conflicts)do print("  "..c.key.." "..c.reason)end
 end
end
