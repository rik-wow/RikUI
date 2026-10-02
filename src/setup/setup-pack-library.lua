-- Curated launch packs, derived from the existing audited layout recipes.
local pack=RikUI.SetupPack
function pack.Bundled(name)
    local layouts=RikUI.Layouts
    if not layouts or not layouts[name] then return nil,"Unknown bundled setup" end
    local profile={scale=1,font="bundled",positions=pack.Copy(layouts[name].positions),modules={}}
    pack.Merge(profile,pack.Themes.classic)
    -- Reviewed native sample footprints include the minimap card and expanding tracker.
    local footprints={minimap={width=200,height=270},questtracker={width=240,height=320},chat={width=438,height=214},
        raid={width=604,height=166},target={width=220,height=76},focus={width=160,height=70}}
    profile.chat={size={width=430,height=136}}
    local groups={}
    for key,nominal in pairs(layouts.Sizes) do
        local size=footprints[key] or nominal
        local component=pack.GroupComponents[key]
        if component and profile.positions[key] then groups[key]={component=component,width=size.width,height=size.height,
            priority=(key=="main" and 1 or key=="player" and 2 or key=="target" and 3 or 20),minimum=0.85,exclusive=layouts.Exclusive[key],floating=layouts.Floating[key],activity=(key=="party" and "party" or key=="raid" and "raid" or nil)} end
    end
    local value=assert(pack.FromProfile(profile,{id="rikui-"..name,title=layouts[name].label or name,creator="RikUI",viewport={width=1920,height=1080}},groups))
    value.activities={exploration={questtracker={collapsed=false}},party={questtracker={collapsed=true}},raid={questtracker={collapsed=true}},town={questtracker={collapsed=false}}}
    value.devices={desktop={scale=1},ultrawide={scale=1},handheld={scale=1.15,showHotkeys=true,showCooldownNumbers=true,questtracker={collapsed=true},
        presentation={hidden={bar4=true,bar5=true,chat=true,damagemeter=true,focus=true,castfocus=true,buffs=true,debuffs=true,questtimers=true}}}}
    return pack.Validate(value)
end
