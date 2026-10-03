RikUI={Presets={},RegisterCommand=function()end,RegisterEvent=function()end}
for _,f in ipairs({"src/core/layout-metrics.lua","src/core/profile-schema.lua","src/persistence/codec.lua","src/setup/setup.lua","src/setup/preset-schema.lua","src/setup/setup-pack.lua","data/layouts.lua","src/setup/setup-pack-library.lua"})do dofile(f)end
local p,cases=RikUI.SetupPack,0
for _,name in ipairs(RikUI.Layouts.Order)do
 local source=assert(p.Bundled(name));local original=assert(p.Encode(source))
 for _,screen in ipairs({{width=1920,height=1080},{width=1366,height=768},{width=3440,height=1440},{width=1280,height=800}})do
  for _,activity in ipairs({"exploration","party","raid","town"})do
   for _,recipe in ipairs({"standard","readable","contrast","calm"})do
    local options={viewport=screen,device=screen.width==1280 and "handheld" or "desktop",activity=activity,accessibility=p.AccessibilityRecipe(recipe)}
    local r=assert(p.Resolve(source,options));local zone=r.groups[1]
    assert(zone.character and zone.rect.x+zone.rect.width/2==screen.width/2 and zone.rect.y+zone.rect.height/2==screen.height/2)
    if recipe=="standard" or recipe=="calm" then
     if screen.width==1366 and activity=="raid" then
      for _,c in ipairs(r.conflicts)do assert(c.key=="chat" and c.reason=="Crowded or off-screen")end
     else assert(#r.conflicts==0,name.." default presentation must fit")end
    end
    for _,g in ipairs(r.groups)do if source.groups[g.key] and not g.floating then
     local a,b=zone.rect,g.rect
     if a.x<b.x+b.width and a.x+a.width>b.x and a.y<b.y+b.height and a.y+a.height>b.y then
      local found=false;for _,c in ipairs(r.warnings)do if c.key==g.key and c.reason=="Covers character viewing area (advisory)" then found=true end end
      assert(found,"Obstructed character without an advisory: "..g.key)
     end
    end end
    if screen.width>=1920 and recipe=="standard" then
     for _,key in ipairs({"castplayer","combatresource","cooldowns"})do
      assert(math.abs(r.profile.positions[key].x-r.profile.positions.swingtimer.x)<0.01,"Combat column scattered: "..name.." "..screen.width.." "..activity.." "..key.." "..r.profile.positions[key].x.." vs "..r.profile.positions.swingtimer.x)
     end
    end
    assert(original==p.Encode(source),"fit rewrote source")
    assert(p.Equal(r,assert(p.Resolve(source,options))),"repeated fitting drifted")
    cases=cases+1
   end
  end
 end
end
print("OK: "..cases.." curated character-clearance/device/activity/readability cases")
