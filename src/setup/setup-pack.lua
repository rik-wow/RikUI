-- Shared data-only Setup Pack contract. Also bundled unchanged into the browser Lua VM.
local pack = { Version = 1, Limit = 12000 }
RikUI.SetupPack = pack
local function fail(message) error(message, 0) end
local function plain(t) if type(t) ~= "table" or getmetatable(t) then fail("Expected plain pack data") end end
local function fields(t, allowed)
    plain(t)
    for k in pairs(t) do if not allowed[k] then fail("Unknown pack field: " .. tostring(k)) end end
end
local function text(s, maximum)
    if type(s) ~= "string" or #s < 1 or #s > maximum or s:find("[%c|]") then fail("Invalid pack text") end
    return s
end
local function id(s) text(s, 64); if not s:match("^[%w_.-]+$") then fail("Invalid pack identity") end; return s end
local function number(n, low, high)
    if type(n) ~= "number" or n ~= n or n < low or n > high then fail("Invalid pack number") end
    return n
end
local function integer(n, low, high) number(n, low, high); if n % 1 ~= 0 then fail("Expected pack integer") end end
local function count(t, maximum)
    plain(t); local n = 0; for _ in pairs(t) do n = n + 1 end
    if n > maximum then fail("Pack capacity exceeded") end
end
function pack.Copy(t)
    if type(t) ~= "table" then return t end
    local r = {}; for k,v in pairs(t) do r[k] = pack.Copy(v) end; return r
end
function pack.Equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k,v in pairs(a) do if not pack.Equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
pack.Components = { appearance=true, hud=true, nameplates=true, group=true, navigation=true, inventory=true, character=true }
pack.Modules = {
    hud={"bars","unitframes","castbars","auras","cooldowns","swingtimer","combopoints","totems","personalresource","combatresource","druidmana","classauras","unitauras","procoverlay","hudframes","xpbar"},
    nameplates={"nameplates"}, group={"unitframes"}, navigation={"minimap","questtracker","questplanner","worldmap","questtimers"},
    inventory={"bags","micromenu","loot","durability"}, appearance={"wizard","panels","controls","dialogs","popups","tooltip","menus","chat","alerts","banners","widgets","screentext","toasts","chatbubbles","damagemeter","combattext","combattimer","lossofcontrol","extrabuttons","mirrortimers"},
}
pack.Activities = { exploration=true, party=true, raid=true, town=true }
pack.Devices = { desktop=true, ultrawide=true, handheld=true }
pack.Themes = {
    classic={borderColor={0.25,0.28,0.32},font="bundled",theme={accent="gold",border=1,texture="bundled",spacing="standard"}},
    ocean={borderColor={0.18,0.65,0.85},font="bundled",theme={accent="blue",border=1,texture="flat",spacing="standard"}},
    ink={borderColor={0.85,0.85,0.85},font="game",theme={accent="white",border=2,texture="flat",spacing="relaxed"}},
}
pack.Readability={standard={},readable={scale=1.15,textScale=1.15,nonColor=true},contrast={scale=1.15,textScale=1.15,contrast=true,nonColor=true,reducedMotion=true},calm={reducedMotion=true,nonColor=true}}
function pack.AccessibilityRecipe(name) if not pack.Readability[name] then return nil,"Unsupported readability recipe" end;return pack.Copy(pack.Readability[name]) end
function pack.Theme(name) if not pack.Themes[name] then return nil,"Unsupported theme" end;return pack.Copy(pack.Themes[name]) end
local knownModules = {}
for _,list in pairs(pack.Modules) do for _,name in ipairs(list) do knownModules[name] = true end end
local function profile(t)
    local result = RikUI.ProfileSchema.Project(t, false)
    -- Removed by the unified cooldown strip (5a8b6f1); stale saved flags have no current effect.
    if result.modules then result.modules.classcooldowns=nil;result.modules.cooldownviewer=nil end
    for name in pairs(result.modules or {}) do if not knownModules[name] then fail("Unsupported pack module: " .. name) end end
    -- Personal records and observations are absent from the schema. Do not include pinned quest identities.
    if result.questtracker and result.questtracker.pins ~= nil then fail("Quest pins are personal; remove them from this pack") end
    return result
end
-- Shared module-to-frame ownership drives both browser controls and fitting.
pack.GroupModules = {
    main="bars",bar2="bars",bar3="bars",bar4="bars",bar5="bars",stance="bars",pet="bars",
    player="unitframes",target="unitframes",tot="unitframes",focus="unitframes",petframe="unitframes",party="unitframes",raid="unitframes",
    castplayer="castbars",casttarget="castbars",castfocus="castbars",castpet="castbars",buffs="auras",debuffs="auras",
    cooldowns="cooldowns",swingtimer="swingtimer",combatresource="combatresource",combopoints="combopoints",totems="totems",xpbar="xpbar",
    chat="chat",damagemeter="damagemeter",bags="bags",bagspace="bags",loot="loot",minimap="minimap",questtracker="questtracker",
    questtimers="questtimers",micromenu="micromenu",durability="durability",
}
-- The browser loads only the data contract. Native fixtures verify this fallback
-- against the actual registered dependency graph before publication.
local MODULE_DEPENDENCIES={unitauras={"unitframes"}}
function pack.ModuleRequirements(name)
    if not knownModules[name] then return nil,"Unsupported pack module" end
    if RikUI.GetModuleRequirements then return RikUI:GetModuleRequirements(name) end
    return pack.Copy(MODULE_DEPENDENCIES[name] or {})
end
function pack.ModuleChoices()
    local choices={}
    for name in pairs(knownModules) do
        local components,groups={},{}
        for component,list in pairs(pack.Modules) do for _,key in ipairs(list) do
            if key==name then components[#components+1]=component end
        end end
        for key,owner in pairs(pack.GroupModules) do if owner==name then groups[#groups+1]=key end end
        table.sort(components);table.sort(groups)
        choices[#choices+1]={key=name,components=components,groups=groups,dependencies=assert(pack.ModuleRequirements(name))}
    end
    table.sort(choices,function(a,b)return a.key<b.key end)
    return choices
end
function pack.ModuleEnabled(p,name)
    if p.modules and p.modules[name]==false then return false end
    local requirements=pack.ModuleRequirements(name)
    if not requirements then return false end
    for _,required in ipairs(requirements) do if p.modules and p.modules[required]==false then return false end end
    return true
end
function pack.GroupEnabled(key,p)
    local owner=pack.GroupModules[key]
    return not owner or pack.ModuleEnabled(p,owner)
end
function pack.SetModule(p,name,on)
    if not knownModules[name] or type(on)~="boolean" then return nil,"Unsupported module choice" end
    local result=profile(p);result.modules=result.modules or {};result.modules[name]=on
    if on then
        local requirements,reason=pack.ModuleRequirements(name);if not requirements then return nil,reason end
        for _,required in ipairs(requirements) do result.modules[required]=true end
    end
    return profile(result)
end
local function viewport(v)
    fields(v,{width=true,height=true}); number(v.width,640,8192); number(v.height,360,4320)
end
local function validate(value)
    local encoded, reason = RikUI.Codec.Encode(value,true)
    if not encoded or #encoded > pack.Limit then fail(reason or "Setup Pack exceeds 12000 encoded bytes") end
    fields(value,{version=true,id=true,revision=true,title=true,creator=true,ancestry=true,components=true,ownership=true,profile=true,
        adjustments=true,groups=true,viewport=true,activities=true,devices=true,capabilities=true,integration=true,character=true,defaultActivity=true,defaultDevice=true,accessibilityRecipe=true})
    if value.accessibilityRecipe and not pack.Readability[value.accessibilityRecipe] then fail("Invalid readability recipe") end
    if value.defaultActivity and not pack.Activities[value.defaultActivity] then fail("Invalid default activity") end
    if value.defaultDevice and not pack.Devices[value.defaultDevice] then fail("Invalid default device") end
    if value.version ~= pack.Version then fail("Unsupported Setup Pack version") end
    id(value.id); integer(value.revision,1,1000000); text(value.title,80); text(value.creator,80)
    fields(value.ancestry or {},{id=true,revision=true,creator=true})
    if value.ancestry and next(value.ancestry) then id(value.ancestry.id); integer(value.ancestry.revision,1,1000000); text(value.ancestry.creator,80) end
    count(value.components,7)
    for k,v in pairs(value.components) do if not pack.Components[k] or type(v) ~= "boolean" then fail("Invalid component choice") end end
    count(value.ownership,7)
    for k,v in pairs(value.ownership) do if not pack.Components[k] or (v ~= "rikui" and v ~= "specialist" and v ~= "stock") then fail("Invalid interface owner") end end
    profile(value.profile);if value.adjustments then profile(value.adjustments) end; viewport(value.viewport); count(value.groups,64)
    for k,g in pairs(value.groups) do
        id(k); fields(g,{component=true,width=true,height=true,priority=true,exclusive=true,minimum=true,floating=true,activity=true})
        if g.floating~=nil and type(g.floating)~="boolean" then fail("Invalid floating group") end
        if g.activity and not pack.Activities[g.activity] then fail("Invalid group activity") end
        if not pack.Components[g.component] or g.component == "character" then fail("Invalid frame component") end
        number(g.width,1,2048); number(g.height,1,2048); integer(g.priority,1,1000)
        if g.minimum then number(g.minimum,0.5,2) end
        if g.exclusive then id(g.exclusive) end
        if not value.profile.positions or not value.profile.positions[k] then fail("Frame group needs source anchor: " .. k) end
    end
    for _,kind in ipairs({"activities","devices"}) do
        count(value[kind] or {},kind == "activities" and 4 or 3)
        local known = kind == "activities" and pack.Activities or pack.Devices
        for k,p in pairs(value[kind] or {}) do if not known[k] then fail("Unsupported presentation") end; profile(p)
            if p.modules or p.font or p.textScale or p.reducedMotion or p.theme then fail("Variants must not require a reload") end
        end
    end
    count(value.capabilities or {},8)
    local caps={layout=true,themes=true,readability=true,gamepadLegend=true,character=true}
    for k,v in pairs(value.capabilities or {}) do if not caps[k] or type(v) ~= "boolean" then fail("Unknown capability") end end
    if value.integration ~= nil and value.integration ~= "questtogether" then fail("Unsupported integration recipe") end
    if value.character then
        fields(value.character,{preset=true,bindings=true})
        if value.character.preset then
            if not RikUI.Setup or not RikUI.Setup.ValidateSharedPreset then fail("Character preset validation unavailable") end
            local issues = RikUI.Setup.ValidateSharedPreset(value.character.preset)
            if #issues > 0 then fail(table.concat(issues,"; ")) end
            for _,macro in pairs(value.character.preset.macros or {}) do
                for command in (macro.body or ""):gmatch("/([%a]+)") do
                    if command:lower()=="run" or command:lower()=="script" then fail("Script macros are not portable") end
                end
            end
        end
        count(value.character.bindings or {},24)
        for key,action in pairs(value.character.bindings or {}) do
            text(key,32); text(action,64)
            if not key:match("^[%w%-]+$") or not action:match("^ACTIONBUTTON%d+$") or tonumber(action:match("%d+$"))<1 or tonumber(action:match("%d+$"))>12 then fail("Only explicit standard action-button bindings are portable") end
        end
    end
    local clean=pack.Copy(value)
    clean.profile=profile(value.profile)
    if value.adjustments then clean.adjustments=profile(value.adjustments) end
    for _,kind in ipairs({"activities","devices"})do for name,p in pairs(clean[kind] or {})do clean[kind][name]=profile(p) end end
    return clean
end
function pack.Validate(value)
    local ok,result=pcall(validate,value); if ok then return result end; return nil,tostring(result)
end
function pack.Encode(value)
    local clean,reason=pack.Validate(value); if not clean then return nil,reason end
    local body=RikUI.Codec.Encode({kind="setup",data=clean},true)
    if not body or #body > pack.Limit then return nil,"Setup Pack exceeds encoded capacity" end
    return "!RIKS1!" .. #body .. ":" .. RikUI.Codec.ChecksumHex(body) .. ":" .. body
end
function pack.Decode(code)
    if type(code)~="string" or #code > pack.Limit+32 then return nil,"Setup code exceeds capacity" end
    local length,sum,body=code:match("^!RIKS1!(%d+):(%x+):([%w_]+)$")
    if not length or #length>5 or #sum~=8 or tonumber(length)~=#body or RikUI.Codec.ChecksumHex(body)~=sum:lower() then return nil,"Invalid Setup Pack header or checksum" end
    local value,reason=RikUI.Codec.Decode(body)
    if not value then return nil,reason end
    if value.kind~="setup" then return nil,"Expected Setup Pack" end
    for k in pairs(value) do if k~="kind" and k~="data" then return nil,"Unknown setup envelope field" end end
    return pack.Validate(value.data)
end
function pack.Merge(target,source)
    for k,v in pairs(source or {}) do
        if type(v)=="table" then
            if type(target[k])~="table" then target[k]={} end
            pack.Merge(target[k],v)
        else target[k]=v end
    end
    return target
end
local points={TOPLEFT={0,1},TOP={0.5,1},TOPRIGHT={1,1},LEFT={0,0.5},CENTER={0.5,0.5},RIGHT={1,0.5},BOTTOMLEFT={0,0},BOTTOM={0.5,0},BOTTOMRIGHT={1,0}}
local function rect(anchor,g,scale,screen)
    local a,b=points[anchor.point],points[anchor.relativePoint]
    local w,h=g.width*scale,g.height*scale
    return {x=b[1]*screen.width+anchor.x*scale-a[1]*w,y=b[2]*screen.height+anchor.y*scale-a[2]*h,width=w,height=h}
end
local function overlap(a,b)
    -- Anchors are quantized to .001 source units; tolerate that rounding at an 8-unit gap.
    return a.x < b.x+b.width+7.998 and a.x+a.width+7.998 > b.x and a.y < b.y+b.height+7.998 and a.y+a.height+7.998 > b.y
end
-- A viewport-relative viewing corridor, independent of UI density and source anchors.
-- This reserves room for the character and nearby ground cues, not a model's measured bounds.
-- Floating windows may cover it temporarily; persistent movers may not.
function pack.CharacterArea(screen)
    local width,height=math.min(360,screen.width*0.24),math.min(300,screen.height*0.30)
    return {x=(screen.width-width)/2,y=(screen.height-height)/2,width=width,height=height}
end
local function resolve(value,options)
    local clean,reason=pack.Validate(value); if not clean then return nil,reason end
    options=options or {}
    local encoded,capacity=RikUI.Codec.Encode(options,true);if not encoded then return nil,capacity end
    fields(options,{viewport=true,activity=true,device=true,components=true,accessibility=true,reservations=true,overrides=true})
    if options.overrides then profile(options.overrides) end
    count(options.reservations or {},16)
    fields(options.accessibility or {},{scale=true,textScale=true,reducedMotion=true,contrast=true,nonColor=true})
    for key,v in pairs(options.accessibility or {}) do
        if key=="scale" then number(v,0.85,1.3) elseif key=="textScale" then number(v,0.85,1.3)
        elseif type(v)~="boolean" then fail("Invalid accessibility choice") end
    end
    if options.components then count(options.components,7);for key,v in pairs(options.components)do if not pack.Components[key] or type(v)~="boolean" then fail("Invalid selected component") end end end
    local screen=options.viewport or clean.viewport
    local ok,problem=pcall(viewport,screen); if not ok then return nil,problem end
    local activity,device=options.activity or clean.defaultActivity or "exploration",options.device or clean.defaultDevice or "desktop"
    if not pack.Activities[activity] or not pack.Devices[device] then return nil,"Unsupported presentation" end
    local p=pack.Merge(pack.Copy(clean.profile),clean.activities and clean.activities[activity])
    pack.Merge(p,clean.devices and clean.devices[device])
    pack.Merge(p,clean.adjustments)
    pack.Merge(p,options.overrides)
    if p.theme and p.theme.spacing=="relaxed" then p.scale=math.max(p.scale or 1,1.1) end
    local access=options.accessibility or (clean.accessibilityRecipe and pack.Readability[clean.accessibilityRecipe]) or {}
    if access.scale then p.scale=math.max(p.scale or 1,access.scale) end
    if access.textScale then p.textScale=math.max(p.textScale or 1,access.textScale) end
    if access.reducedMotion then p.reducedMotion=true end
    if access.contrast then p.borderColor={0.85,0.85,0.85} end
    if access.nonColor then p.unitframes={healthText="both",powerText="both"}; p.nameplates=p.nameplates or {}; p.nameplates.threatText=true; p.showHotkeys=true end
    local projected,err=pcall(profile,p); if not projected then return nil,err end
    p=err; local scale=p.scale or 1; p.positions=p.positions or {}
    local keys,disabledGroups={},{}; local selected=options.components or clean.components
    for k,g in pairs(clean.groups) do if selected[g.component] and clean.ownership[g.component]=="rikui" and (not g.activity or g.activity==activity)
        and not (p.presentation and p.presentation.hidden and p.presentation.hidden[k]) then
        if pack.GroupEnabled(k,p) then keys[#keys+1]=k
        else disabledGroups[#disabledGroups+1]={key=k,rect=rect(p.positions[k],g,scale,screen),disabled=true,module=pack.GroupModules[k],floating=g.floating} end
    end end
    table.sort(disabledGroups,function(a,b)return a.key<b.key end)
    table.sort(keys,function(a,b) return clean.groups[a].priority==clean.groups[b].priority and a<b or clean.groups[a].priority<clean.groups[b].priority end)
    local placed,conflicts={{rect=pack.CharacterArea(screen),key="Character viewing area",character=true}},{}
    local reservations=options.reservations or {}
    for _,r in ipairs(reservations) do
        fields(r,{x=true,y=true,width=true,height=true}); number(r.x,0,8192); number(r.y,0,4320); number(r.width,1,8192); number(r.height,1,4320)
        placed[#placed+1]={rect=r,key="Reserved specialist area"}
    end
    for _,key in ipairs(keys) do
        local g=pack.Copy(clean.groups[key])
        if key=="questtracker" and p.questtracker and p.questtracker.collapsed then g.height=24 end
        local original=rect(p.positions[key],g,scale,screen)
        local r=pack.Copy(original)
        r.x=math.max(8,math.min(screen.width-r.width-8,r.x)); r.y=math.max(8,math.min(screen.height-r.height-8,r.y))
        local fixed=(options.overrides and options.overrides.positions and options.overrides.positions[key]) or (clean.adjustments and clean.adjustments.positions and clean.adjustments.positions[key])
        local function clear(candidate)
            if candidate.x<7.998 or candidate.y<7.998 or candidate.x+candidate.width>screen.width-7.998 or candidate.y+candidate.height>screen.height-7.998 then return false end
            for _,other in ipairs(placed) do if not g.floating and not other.floating and (not g.exclusive or g.exclusive~=other.exclusive) and overlap(candidate,other.rect) then return false end end
            return true
        end
        if fixed then r=original
        elseif not clear(r) then
            local best,distance
            for _,other in ipairs(placed) do
                for _,xy in ipairs({{other.rect.x-r.width-8,r.y},{other.rect.x+other.rect.width+8,r.y},{r.x,other.rect.y-r.height-8},{r.x,other.rect.y+other.rect.height+8}}) do
                    local c={x=xy[1],y=xy[2],width=r.width,height=r.height}; local d=(c.x-original.x)^2+(c.y-original.y)^2
                    if clear(c) and (not distance or d<distance) then best,distance=c,d end
                end
            end
            if not best then
                -- Try intersections of all free edges when a single-axis move is insufficient.
                local xs,ys={8,screen.width-r.width-8,r.x},{8,screen.height-r.height-8,r.y}
                for _,other in ipairs(placed)do
                    xs[#xs+1]=other.rect.x-r.width-8;xs[#xs+1]=other.rect.x+other.rect.width+8
                    ys[#ys+1]=other.rect.y-r.height-8;ys[#ys+1]=other.rect.y+other.rect.height+8
                end
                for _,x in ipairs(xs)do for _,y in ipairs(ys)do
                    local c={x=x,y=y,width=r.width,height=r.height};local d=(x-original.x)^2+(y-original.y)^2
                    if (not distance or d<distance) and clear(c) then best,distance=c,d end
                end end
            end
            if best then r=best end
        end
        if scale<(g.minimum or 0.85) then conflicts[#conflicts+1]={key=key,reason="Below readable minimum"} end
        if not clear(r) then
            local characterConflict=not g.floating and overlap(r,placed[1].rect)
            conflicts[#conflicts+1]={key=key,reason=characterConflict and "Obstructs character viewing area" or (fixed and "Personal position conflicts" or "Crowded or off-screen")}
        end
        p.positions[key]={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=math.floor(r.x/scale*1000+0.5)/1000,y=math.floor(r.y/scale*1000+0.5)/1000}
        placed[#placed+1]={key=key,rect=r,exclusive=g.exclusive,floating=g.floating}
    end
    for name in pairs(knownModules) do if p.modules and p.modules[name]~=false then
        local adopted=false
        for component,list in pairs(pack.Modules) do if selected[component] and clean.ownership[component]=="rikui" then
            for _,key in ipairs(list) do if key==name then adopted=true end end
        end end
        if adopted then for _,required in ipairs(assert(pack.ModuleRequirements(name))) do
            if p.modules[required]==false then conflicts[#conflicts+1]={key="module."..name,reason="Requires enabled module: "..required} end
        end end
    end end
    if p.modules and p.modules.unitframes==false and (selected.hud or selected.group)
        and not (selected.hud and selected.group and clean.ownership.hud=="rikui" and clean.ownership.group=="rikui") then
        conflicts[#conflicts+1]={key="module.unitframes",reason="Unit frames are shared: adopt both Combat HUD and Party & raid to disable them together"}
    end
    return {profile=p,groups=placed,disabledGroups=disabledGroups,conflicts=conflicts,activity=activity,device=device}
end

function pack.Resolve(value,options)
    local ok,result,reason=pcall(resolve,value,options)
    if not ok then return nil,tostring(result) end
    return result,reason
end

pack.GroupComponents = {
    main="hud",bar2="hud",bar3="hud",bar4="hud",bar5="hud",stance="hud",pet="hud",player="hud",target="hud",tot="hud",focus="hud",petframe="hud",
    castplayer="hud",casttarget="hud",castfocus="hud",castpet="hud",buffs="hud",debuffs="hud",cooldowns="hud",swingtimer="hud",
    combatresource="hud",combopoints="hud",totems="hud",xpbar="hud",party="group",raid="group",minimap="navigation",
    questtracker="navigation",questtimers="navigation",chat="appearance",damagemeter="appearance",bags="inventory",loot="inventory",micromenu="inventory",durability="inventory",
}
local ROOT_COMPONENT={nameplates="nameplates",minimap="navigation",questtracker="navigation",worldmap="navigation",
    bags="inventory",tooltip="appearance",chat="appearance",panels="appearance",castbars="hud",unitframes="hud",barFade="hud",
    swingtimer="hud",druidmana="hud",classes="hud",xpbar="hud",combattimer="appearance",durability="inventory"}
function pack.Adopt(current,wanted,value,selected,accessibility)
    local copy=pack.Copy;local result=copy(current);selected=selected or value.components
    for k,v in pairs(wanted) do
        if k=="positions" then
            result.positions=result.positions or {}
            for key,pos in pairs(v) do
                local g=value.groups[key]; if g and selected[g.component] and value.ownership[g.component]=="rikui" then result.positions[key]=copy(pos) end
            end
        elseif k=="presentation" then
            result.presentation=result.presentation or {};result.presentation.hidden=result.presentation.hidden or {}
            for key,component in pairs(pack.GroupComponents)do if selected[component] and value.ownership[component]=="rikui" then
                result.presentation.hidden[key]=(v.hidden or {})[key]
            end end
        elseif k=="modules" then
            result.modules=result.modules or {}
            local choice={}
            for component,list in pairs(pack.Modules) do if selected[component] then for _,name in ipairs(list) do
                local on=value.ownership[component]=="rikui" and (v[name]~=false)
                choice[name]=choice[name]==true or on
            end end end
            for name,on in pairs(choice) do result.modules[name]=on end
        else
            local component=ROOT_COMPONENT[k] or "appearance"
            if selected[component] and value.ownership[component]=="rikui" then result[k]=copy(v) end
        end
    end
    result.interfaceOwners=copy(current.interfaceOwners or {})
    for _,component in ipairs({"hud","group"})do if selected[component] then result.interfaceOwners[component]=value.ownership[component] end end
    local hudOwner=result.interfaceOwners.hud;local groupOwner=result.interfaceOwners.group
    if selected.hud or selected.group then
        local function enabled(component,owner)
            local modules=selected[component] and wanted.modules or current.modules
            return (owner==nil or owner=="rikui") and not (modules and modules.unitframes==false)
        end
        result.modules=result.modules or {};result.modules.unitframes=enabled("hud",hudOwner) or enabled("group",groupOwner)
    end
    -- Accessibility always wins, even when appearance is not adopted.
    local a=accessibility or {}
    if a.scale then result.scale=math.max(result.scale or 1,a.scale) end
    if a.textScale then result.textScale=math.max(result.textScale or 1,a.textScale) end
    if a.reducedMotion then result.reducedMotion=true end
    if a.contrast then result.borderColor={0.85,0.85,0.85} end
    if a.nonColor then result.showHotkeys=true;result.unitframes={healthText="both",powerText="both"};result.nameplates=result.nameplates or {};result.nameplates.threatText=true end
    return result
end

function pack.FromProfile(p,meta,groups)
    meta=meta or {}
    local clean=RikUI.ProfileSchema.Project(p,true)
    if clean.questtracker then clean.questtracker.pins=nil end
    local result={version=1,id=meta.id or "personal-setup",revision=meta.revision or 1,title=meta.title or "My setup",
        creator=meta.creator or "Anonymous",profile=clean,viewport=meta.viewport or {width=1920,height=1080},groups=groups or {},
        components={},ownership={},capabilities={layout=true,themes=true,readability=true}}
    for c in pairs(pack.Components) do result.components[c]=c~="character"; result.ownership[c]="rikui" end
    for c,owner in pairs(clean.interfaceOwners or {})do result.ownership[c]=owner end
    return pack.Validate(result)
end
function pack.Import(code,meta)
    if type(code)=="string" and code:sub(1,7)=="!RIKS1!" then return pack.Decode(code) end
    local p,reason=RikUI.Sharing.Decode(code,"profile")
    if p then return pack.FromProfile(p,meta,{}) end
    local preset=RikUI.Sharing.Decode(code,"preset")
    if preset then
        local result=pack.FromProfile({},meta,{})
        result.components={character=true}; result.character={preset=preset}
        return pack.Validate(result)
    end
    return nil,reason or "Unsupported sharing code"
end


function pack.Diff(before,after)
    local changes={}
    local function visit(a,b,path)
        if pack.Equal(a,b) then return end
        if type(a)=="table" and type(b)=="table" then
            local keys={};for k in pairs(a) do keys[k]=true end;for k in pairs(b) do keys[k]=true end
            for k in pairs(keys) do local child=pack.Copy(path);child[#child+1]=k;visit(a[k],b[k],child) end
        else changes[#changes+1]={path=pack.Copy(path),before=pack.Copy(a),after=pack.Copy(b)} end
    end
    visit(before,after,{})
    return changes
end
function pack.At(root,path)
    local value=root
    for _,key in ipairs(path) do if type(value)~="table" then return nil end;value=value[key] end
    return value
end
function pack.Set(root,path,value)
    local target=root
    for i=1,#path-1 do local key=path[i];if type(target[key])~="table" then target[key]={} end;target=target[key] end
    target[path[#path]]=pack.Copy(value)
end

-- Three-way leaf comparison preserves edits and explains concurrent creator changes.
function pack.Update(previous,incoming,current,accept)
    local out,changes,conflicts=pack.Copy(current),{},{}
    local function walk(old,new,live,target,path)
        local keys={}; for k in pairs(old or {}) do keys[k]=true end; for k in pairs(new or {}) do keys[k]=true end
        local order={}; for k in pairs(keys) do order[#order+1]=k end; table.sort(order,function(a,b)return tostring(a)<tostring(b)end)
        for _,k in ipairs(order) do
            local a,b,c=old and old[k],new and new[k],live and live[k]; local name=path=="" and tostring(k) or path.."."..tostring(k)
            if type(a)=="table" and type(b)=="table" and type(c)=="table" then walk(a,b,c,target[k],name)
            elseif not pack.Equal(a,b) then
                local edited=not pack.Equal(a,c)
                if edited then conflicts[#conflicts+1]={path=name,previous=pack.Copy(a),incoming=pack.Copy(b),personal=pack.Copy(c)} end
                if (not edited and (not accept or accept[name]~=false)) or (accept and accept[name]==true) then
                    target[k]=pack.Copy(b); changes[#changes+1]=name
                end
            end
        end
    end
    walk(previous,incoming,current,out,"")
    return {profile=out,changes=changes,conflicts=conflicts}
end
