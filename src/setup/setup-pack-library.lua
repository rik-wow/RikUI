-- Curated launch packs, derived from the existing audited layout recipes.
local pack=RikUI.SetupPack
function pack.Bundled(name)
    local layouts=RikUI.Layouts
    if not layouts or not layouts[name] then return nil,"Unknown bundled setup" end
    local profile={scale=1,font="bundled",positions=pack.Copy(layouts[name].positions),modules={}}
    pack.Merge(profile,pack.Themes.classic)
    -- Keep the combat column together beside the character corridor rather than
    -- letting individual rows scatter when its upper rows reach screen center.
    for _,key in ipairs({"castplayer","combatresource","cooldowns","swingtimer","combopoints","totems","druidmana","classbuffs","classeffects"})do
        if profile.positions[key] then profile.positions[key].x=profile.positions[key].x-340 end
    end
    if name=="healer" then
        for _,key in ipairs({"party","raid"})do profile.positions[key]={point="TOPLEFT",relativePoint="TOPLEFT",x=16,y=-120} end
    end
    if name=="centered" or name=="hud" then
        profile.positions.player.x=-300;profile.positions.target.x=300;profile.positions.casttarget.x=300
    end
    -- Reviewed native sample footprints include the minimap card and expanding tracker.
    local footprints={minimap={width=200,height=270},questtracker={width=240,height=320},chat={width=438,height=214},
        raid={width=604,height=166},target={width=220,height=76},focus={width=160,height=70}}
    profile.chat={size={width=430,height=136}}
    -- Protect the bar stack and large edge panels before fitting smaller combat displays.
    -- Group frames must get a viable side/top location before smaller frames consume it.
    local priorities={main=1,xpbar=2,bar2=3,bar3=3,bar4=3,bar5=3,stance=3,pet=3,
        chat=5,party=4,raid=4,damagemeter=6,micromenu=3,minimap=4,buffs=8,debuffs=8,questtracker=4,questtimers=4,swingtimer=9,player=10,target=11,cooldowns=12,castplayer=13,combatresource=14}
    local groups={}
    for key,nominal in pairs(layouts.Sizes) do
        local size=footprints[key] or nominal
        local component=pack.GroupComponents[key]
        if component and profile.positions[key] then groups[key]={component=component,width=size.width,height=size.height,
            native=RikUI.LayoutMetrics.IsBar(key) or key:match("^cast")~=nil,cells=key=="stance" and 3 or nil,
            priority=priorities[key] or 20,minimum=0.85,exclusive=layouts.Exclusive[key],floating=layouts.Floating[key],activity=(key=="party" and "party" or key=="raid" and "raid" or nil)} end
    end
    local value=assert(pack.FromProfile(profile,{id="rikui-"..name,title=layouts[name].label or name,creator="RikUI",revision=3,viewport={width=1920,height=1080}},groups))
    value.activities={exploration={questtracker={collapsed=false}},party={questtracker={collapsed=true}},raid={questtracker={collapsed=true}},town={questtracker={collapsed=false}}}
    value.devices={desktop={scale=1},ultrawide={scale=1},handheld={scale=1.15,showHotkeys=true,showCooldownNumbers=true,questtracker={collapsed=true},
        presentation={hidden={bar4=true,bar5=true,chat=true,damagemeter=true,buffs=true,debuffs=true,questtimers=true}}}}
    return pack.Validate(value)
end
