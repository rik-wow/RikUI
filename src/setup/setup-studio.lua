-- Selective Setup Studio transactions. Creator source, personal edits and restore points stay separate.
local core,pack=RikUI,RikUI.SetupPack
local studio={Selected={appearance=true,hud=true,nameplates=true,group=true,navigation=true,inventory=true},Device="desktop",Activity="exploration",Pinned=true}
core.Studio=studio
local copy=pack.Copy
local state,loaded,preview,capture,presentationBaseline

local function portable()
    local p=core.ProfileSchema.Project(core.Profile,true)
    if p.questtracker then p.questtracker.pins=nil end
    return p
end
function studio.State()
    if not loaded then
        state=type(RikUIStudioDB)=="table" and RikUIStudioDB or (core.Store and core.Store.Load("studio")) or {}
        if type(state)~="table" then state={} end
        state.version=1; if type(state.accessibility)~="table" then state.accessibility={} end
        if type(state.restoreIndex)~="number" or state.restoreIndex%1~=0 or state.restoreIndex<1 or state.restoreIndex>3 then state.restoreIndex=nil end
        studio.Device=pack.Devices[state.device] and state.device or "desktop"
        studio.Activity=pack.Activities[state.activity] and state.activity or "exploration";studio.Pinned=state.pinned~=false
        loaded=true; RikUIStudioDB=state
    end
    return state
end
local function persist(value)
    local encoded,reason=core.Codec.Encode(value,true)
    if not encoded then return nil,"Studio storage capacity: "..tostring(reason) end
    if not core.Store or not core.Store.Available() then return nil,"Studio storage unavailable" end
    if core.Store and core.Store.Available() then
        local ok,failure=core.Store.Save("studio",value); if not ok then return nil,"Studio save failed: "..tostring(failure) end
    end
    state=value; RikUIStudioDB=state; return true
end
local function safe()
    if not core.Profile then return nil,"Still loading" end
    if InCombatLockdown() then return nil,"Setup Studio changes wait until out of combat" end
    if core.Setup.IsApplying() or (core.Setup.IsUndoing and core.Setup.IsUndoing()) then return nil,"Finish the character Setup operation first" end
    if preview then return nil,"Exit try-on before applying or importing" end
    return true
end
function studio.Export(meta)
    if not core.Profile then return nil,"Still loading" end
    local groups={}
    for key,group in pairs(core.Layout.Groups) do
        if pack.GroupComponents[key] and group.frames[1] then
            local frame=group.frames[1]
            groups[key]={component=pack.GroupComponents[key],width=frame:GetWidth(),height=frame:GetHeight(),
                native=(core.LayoutMetrics.IsBar(key) and type(frame.buttons)=="table") or key:match("^cast")~=nil,
                cells=core.LayoutMetrics.IsBar(key) and type(frame.buttons)=="table" and (key=="stance" and math.max(1,frame.formCount or 1) or #frame.buttons) or nil,
                priority=key=="main" and 1 or 20,exclusive=group.exclusive,minimum=0.85,floating=core.Layout.Floats(group),
                activity=key=="party" and "party" or key=="raid" and "raid" or nil}
        end
    end
    -- Saved anchors may be partial; live layout already fills them from defaults.
    -- Normalize the export copy before strict projection, without changing the live profile.
    local source=copy(core.Profile);source.positions=source.positions or {}
    for key in pairs(core.Layout.Groups) do
        if source.positions[key] then source.positions[key]=core.Layout.GetPosition(key) end
    end
    local p=core.ProfileSchema.Project(source,true)
    if p.questtracker then p.questtracker.pins=nil end
    for key in pairs(groups) do p.positions[key]=core.Layout.GetPosition(key) end
    meta=meta or {id="personal-"..core.Codec.Checksum(core.CharDB.profile or "Default"),title="My RikUI setup",creator="Anonymous"}
    meta.viewport=core.Layout.Screen() or {width=1920,height=1080}
    local value,reason=pack.FromProfile(p,meta,groups)
    if not value then return nil,reason end
    local installed=studio.State().installed
    if installed then local parent=pack.Decode(installed); if parent then value.ancestry={id=parent.id,revision=parent.revision,creator=parent.creator} end end
    return pack.Encode(value)
end
-- Explicit live character capture. Only chosen action pages and bindings enter portable data.
function studio.ExportCharacter(pages,includeBindings)
    local ok,reason=safe();if not ok then return nil,reason end
    local _,class=UnitClass("player")
    local wanted={bars={}}
    for _,page in ipairs(pages or {"main","bar2","bar3","bar4","bar5"}) do
        if not core.Setup.SlotToAction(page,1) then return nil,"Unsupported action page" end
        wanted.bars[page]={};for i=1,12 do wanted.bars[page][i]={} end
    end
    local snapshot,failure=core.Setup.CaptureSnapshot(wanted,{macros=false,binds=false,cvars=false,layout=false},core.Profile,core.CharDB)
    if not snapshot then return nil,failure end
    local preset={class=class,version=1,author="Anonymous",roles={live={label="Live setup",trees={1}}},roleOrder={"live"},bars={},macros={}}
    local catalog=core.Spells.Catalog(class)
    for page,slots in pairs(wanted.bars) do
        preset.bars[page]={}
        for index in pairs(slots) do
            local action=snapshot.bars[core.Setup.SlotToAction(page,index)]
            if action.kind=="spell" then
                local name
                for spell,data in pairs(catalog)do for _,id in ipairs(data.ranks or {})do if id==action.id then name=spell end end end
                if not name then return nil,"Unverified spell in "..page.." "..index.."; export a supported selection instead" end
                preset.bars[page][index]={spell=name}
            elseif action.kind=="item" then
                local item=C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(action.id) or (GetItemInfo and GetItemInfo(action.id))
                if type(item)~="string" then return nil,"Item data unavailable in "..page.." "..index end
                preset.bars[page][index]={item=item}
            elseif action.kind=="macro" then
                local macro=action.macro
                if not macro or type(macro.name)~="string" then return nil,"Macro unreadable in "..page.." "..index end
                local existing=preset.macros[macro.name]
                if existing and existing.body~=macro.body then return nil,"Duplicate macro names are ambiguous" end
                preset.macros[macro.name]={body=macro.body,icon=macro.icon,scope="character"}
                preset.bars[page][index]={macro=macro.name}
            elseif action.kind then return nil,"Unsupported live action" end
        end
    end
    local code,why=studio.Export();if not code then return nil,why end
    local value=assert(pack.Decode(code));value.character={preset=preset};value.components.character=true;value.capabilities.character=true
    if includeBindings then
        value.character.bindings={}
        for i=1,12 do
            local command="ACTIONBUTTON"..i
            local read,keys=pcall(function()return {GetBindingKey(command)}end)
            if not read then return nil,"Binding reader unavailable" end
            for _,key in ipairs(keys)do value.character.bindings[key]=command end
        end
    end
    return pack.Encode(value)
end

function studio.Import(code)
    local ok,reason=safe(); if not ok then return nil,reason end
    local value,problem=pack.Import(code)
    if not value then return nil,problem end
    studio.Draft=value; studio.Selected=copy(value.components); studio.Selected.character=false
    if value.defaultDevice then studio.Device=value.defaultDevice end
    if value.defaultActivity then studio.Activity=value.defaultActivity;studio.Pinned=true end
    return true,"Imported for review; nothing applied"
end
function studio.CurrentAccessibility()
    local s=studio.State()
    if s.accessibilityRecipe or not (studio.Draft and studio.Draft.accessibilityRecipe) then return s.accessibility end
    return pack.AccessibilityRecipe(studio.Draft.accessibilityRecipe)
end
local function currentOptions()
    local s=studio.State()
    local reservations={}
    if studio.Draft and studio.Draft.integration=="questtogether" and studio.IntegrationAvailable() then
        local screen=core.Layout.Screen(); reservations={{x=8,y=screen.height-200,width=320,height=180}}
    end
    local overrides
    if not studio.Selected.appearance then overrides={scale=core.Profile.scale,font=core.Profile.font,textScale=core.Profile.textScale,theme=copy(core.Profile.theme),borderColor=copy(core.Profile.borderColor)} end
    return {overrides=overrides,viewport=core.Layout.Screen(),activity=studio.Activity,device=studio.Device,components=studio.Selected,
        accessibility=studio.CurrentAccessibility(),reservations=reservations}
end
function studio.FitOptions() return copy(currentOptions()) end
function studio.Resolve()
    if not studio.Draft then return nil,"Choose or import a setup first" end
    local value=copy(studio.Draft)
    if value.integration=="questtogether" and not studio.IntegrationAvailable() then
        value.ownership.nameplates="rikui";value.profile.modules=value.profile.modules or {};value.profile.modules.nameplates=true
    end
    local result,problem=pack.Resolve(value,currentOptions());if result then result.effectivePack=value end
    return result,problem
end
function studio.Review(accept)
    local resolved,reason=studio.Resolve(); if not resolved then return nil,reason end
    local wanted=pack.Adopt(portable(),resolved.profile,resolved.effectivePack or studio.Draft,studio.Selected,studio.CurrentAccessibility())
    local creatorBaseline=copy(wanted)
    local s=studio.State(); local update
    if s.installed and s.profileName==core.CharDB.profile then
        local previous=pack.Decode(s.installed)
        if previous and previous.id==studio.Draft.id then
            if studio.Draft.revision<=previous.revision then return nil,"Choose a newer revision of this installed pack" end
            update=pack.Update(s.applied or {},wanted,portable(),accept)
            wanted=update.profile
        end
    end
    local auditOptions=currentOptions();auditOptions.overrides=wanted
    local finalFit,fitError=pack.Resolve(resolved.effectivePack or studio.Draft,auditOptions);if not finalFit then return nil,fitError end
    return {profile=wanted,baseline=creatorBaseline,fit=finalFit,conflicts=update and update.conflicts or {},changes=update and update.changes or {},
        reload=not pack.Equal(wanted.modules,core.Profile.modules) or wanted.font~=core.Profile.font or wanted.textScale~=core.Profile.textScale or not pack.Equal(wanted.theme,core.Profile.theme) or not pack.Equal(wanted.interfaceOwners,core.Profile.interfaceOwners),
        integration=studio.Draft.integration}
end
local function restorePoint()
    local s=copy(studio.State()); local index=(s.restoreIndex or 0)%3+1
    local point={profile=portable(),state=copy(s),profileName=core.CharDB.profile,changed={}}
    local text,reason=core.Codec.Encode(point,true)
    if not text then return nil,"Restore point exceeds capacity: "..tostring(reason) end
    if not core.Store or not core.Store.Available() then return nil,"Verified restore storage is unavailable" end
    local ok,failure=core.Store.Save("studio_restore_"..index,point)
    if not ok then return nil,"Could not create restore point: "..tostring(failure) end
    return point,index
end
local function refreshChat(before)
    if core.Chat and core.Chat.enabled and core.Chat.Restore and not pack.Equal(before.chat,core.Profile.chat) then core.Chat.Restore() end
end
local function assign(p)
    -- Resize the owned chat holder before applying its validated full footprint.
    local before=portable()
    for _,entry in ipairs(pack.Diff(before,p))do pack.Set(core.Profile,entry.path,entry.after) end
    refreshChat(before)
    if core.Bags and core.Bags.ApplyColumns and not pack.Equal(before.bags,core.Profile.bags) then core.Bags.ApplyColumns() end
    if core.QuestTracker and core.QuestTracker.Refresh and not pack.Equal(before.questtracker,core.Profile.questtracker) then core.QuestTracker.Refresh() end
    core:Changed(); core.Layout.Apply()
end
function studio.Apply(accept)
    local ok,reason=safe(); if not ok then return nil,reason end
    local review,problem=studio.Review(accept); if not review then return nil,problem end
    if #review.fit.conflicts>0 then return nil,"Resolve fitting conflicts before Apply" end
    local point,index=restorePoint(); if not point then return nil,index end
    local nextState=copy(studio.State())
    nextState.installed=assert(pack.Encode(studio.Draft));nextState.profileName=core.CharDB.profile
    nextState.applied=copy(review.baseline);nextState.restoreIndex=index;nextState.device=studio.Device;nextState.activity=studio.Activity
    nextState.accessibility=copy(studio.CurrentAccessibility());nextState.accessibilityRecipe=nextState.accessibilityRecipe or studio.Draft.accessibilityRecipe
    nextState.selected=copy(studio.Selected); nextState.pinned=studio.Pinned;nextState.presentationBaseline=nil;nextState.presentationOverrides=nil
    local saved,failure=persist(nextState);if not saved then return nil,failure end
    local changed=pack.Diff(point.profile,review.profile)
    point.changed=changed
    local journalOK,journalError=core.Store.Save("studio_restore_"..index,point)
    if not journalOK then persist(point.state);return nil,"Recovery journal failed before changes: "..tostring(journalError) end
    local applied,err=pcall(assign,review.profile)
    presentationBaseline=copy(review.profile)
    studio.LastResult={changed=changed,status=applied and "applied" or "partial",error=not applied and tostring(err) or nil,restore=index,reload=review.reload}
    -- Actual setting writes preceded any frame refresh; a refresh failure remains recoverable.
    return applied and true or nil,studio.LastResult
end
function studio.Restore(index)
    local ok,reason=safe();if not ok then return nil,reason end
    index=index or studio.State().pendingRestore or studio.State().restoreIndex
    if type(index)~="number" or index%1~=0 or index<1 or index>3 then return nil,"Choose restore point1..3" end
    local point,failure=core.Store.Load("studio_restore_"..index)
    if not point or point.profileName~=core.CharDB.profile then return nil,failure or "Restore point belongs to another profile" end
    local clean,err=pcall(core.ProfileSchema.Project,point.profile,false);if not clean then return nil,err end
    for _,entry in ipairs(point.changed or {}) do
        local current=pack.At(core.Profile,entry.path)
        if not pack.Equal(current,entry.after) and not pack.Equal(current,entry.before) then return nil,"A changed area has newer personal edits; export it before restoration" end
    end
    local oldState=copy(studio.State())
    local restoredState=copy(point.state);restoredState.pendingRestore=index
    local restored,problem=persist(restoredState);if not restored then return nil,problem end
    if point.bindings then
        local restoredBindings,bindingReason
        core.Combat.Queue(function()restoredBindings,bindingReason=core.Bindings.Restore(point.bindings)end)
        if not restoredBindings then
            persist(oldState)
            studio.LastResult={status="partial",error=bindingReason or "Binding restoration did not finish",restore=index}
            return nil,studio.LastResult.error
        end
    end
    presentationBaseline=nil
    local before=portable()
    local applied,refreshError=pcall(function()
        for _,entry in ipairs(point.changed or {}) do pack.Set(core.Profile,entry.path,entry.before) end
        refreshChat(before)
    if core.Bags and core.Bags.ApplyColumns and not pack.Equal(before.bags,core.Profile.bags) then core.Bags.ApplyColumns() end
    if core.QuestTracker and core.QuestTracker.Refresh and not pack.Equal(before.questtracker,core.Profile.questtracker) then core.QuestTracker.Refresh() end
        core:Changed();core.Layout.Apply()
    end)
    if applied then
        local finished=copy(studio.State());finished.pendingRestore=nil
        local saved,saveError=persist(finished);if not saved then applied=false;refreshError=saveError end
    end
    studio.LastResult={status=applied and "restored" or "partial",changed=pack.Diff(before,portable()),error=not applied and tostring(refreshError) or nil,restore=index}
    return applied and true or nil,studio.LastResult
end
function studio.Accessibility(recipe)
    local choices={standard={},readable={scale=1.15,textScale=1.15,nonColor=true},
        contrast={scale=1.15,textScale=1.15,contrast=true,nonColor=true,reducedMotion=true},
        calm={reducedMotion=true,nonColor=true}}
    if not choices[recipe] then return nil,"Choose standard, readable, contrast or calm" end
    local ok,reason=safe();if not ok then return nil,reason end
    local nextState=copy(studio.State());nextState.accessibility=copy(choices[recipe]);nextState.accessibilityRecipe=recipe
    return persist(nextState)
end
function studio.Presentation(activity,device,pinned)
    if not pack.Activities[activity] or not pack.Devices[device] then return nil,"Unsupported presentation" end
    studio.Activity,studio.Device,studio.Pinned=activity,device,pinned~=false
    core.Combat.Queue(function()
        local s=studio.State();if not s.installed or s.profileName~=core.CharDB.profile or preview then return end
        local value=pack.Decode(s.installed);if not value then return end
        if core.Setup.IsApplying() or (core.Setup.IsUndoing and core.Setup.IsUndoing()) then studio.PresentationIssue="Finish character Setup before changing presentation";return end
        local baseline=presentationBaseline or s.presentationBaseline or s.applied or {};local personal=portable()
        local overrides=copy(s.presentationOverrides or {positions={}});overrides.positions=overrides.positions or {}
        for key,pos in pairs(personal.positions or {}) do if not pack.Equal(pos,(baseline.positions or {})[key]) then overrides.positions[key]=copy(pos) end end
        if not pack.Equal(personal.scale,baseline.scale) or not s.selected.appearance then overrides.scale=personal.scale end
        if value.integration=="questtogether" and not studio.IntegrationAvailable() then
            value.ownership.nameplates="rikui";value.profile.modules=value.profile.modules or {};value.profile.modules.nameplates=true
        end
        local screen=core.Layout.Screen()
        local reservations=value.integration=="questtogether" and studio.IntegrationAvailable() and {{x=8,y=screen.height-200,width=320,height=180}} or {}
        local resolved=pack.Resolve(value,{viewport=screen,activity=activity,device=device,components=s.selected,
            overrides=overrides,accessibility=s.accessibility,reservations=reservations})
        if not resolved or #resolved.conflicts>0 then studio.PresentationIssue="Presentation has unresolved fit conflicts";return end
        -- Save the prospective state before changing any settings.
        local nextProfile=portable()
        for _,entry in ipairs(resolved.groups) do
            if value.groups[entry.key] then nextProfile.positions[entry.key]=copy(resolved.profile.positions[entry.key]) end
        end
        nextProfile.scale=resolved.profile.scale or nextProfile.scale
        if s.selected.navigation and value.ownership.navigation=="rikui" and resolved.profile.questtracker then nextProfile.questtracker=pack.Merge(nextProfile.questtracker or {},resolved.profile.questtracker) end
        nextProfile.presentation=pack.Adopt(nextProfile,{presentation=resolved.profile.presentation or {}},value,s.selected,{}).presentation
        local nextState=copy(s);nextState.device=device;nextState.activity=activity;nextState.pinned=pinned~=false;nextState.presentationBaseline=copy(nextProfile);nextState.presentationOverrides=copy(overrides)
        local saved,problem=persist(nextState);studio.PresentationIssue=not saved and problem or nil
        if not saved then return end
        presentationBaseline=copy(nextProfile);assign(nextProfile)
    end,"studio:presentation")
    return true
end
function studio.AutoActivity()
    if studio.Pinned then return end
    local activity="exploration"
    local ok,raid=pcall(IsInRaid);if ok and raid then activity="raid"
    else local partyOK,party=pcall(IsInGroup);if partyOK and party then activity="party"
    else local restOK,rest=pcall(IsResting);if restOK and rest then activity="town" end end end
    return studio.Presentation(activity,studio.Device,false)
end
function studio.TryOn(scene)
    local ok,reason=safe();if not ok then return nil,reason end
    local resolved,problem=studio.Resolve();if not resolved then return nil,problem end
    if #resolved.conflicts>0 then return nil,"Resolve fitting conflicts first" end
    preview={profile=portable(),party=core.UnitFrames and core.UnitFrames.Party.Testing,raid=core.UnitFrames and core.UnitFrames.Raid.Testing,
        bags=core.Bags and core.Bags.Holder and core.Bags.Holder:IsShown()}
    -- Only layout is temporary: module/font changes remain explicitly marked for reload.
    if core.UnitFrames then
        if scene=="party" then core.UnitFrames.Party.SetTest(true)
        elseif scene=="raid" then core.UnitFrames.Raid.SetTest(true) end
    end
    if scene=="casting" and core.CastBars and core.CastBars.Preview then core.CastBars.Preview(true) end
    if scene=="inventory" and core.Bags and core.Bags.Holder then core.Bags.Holder:Show() end
    if core.Layout.Preview then core.Layout.Preview(resolved.profile,studio.Selected,studio.Draft.groups) end
    return true
end
function studio.ExitPreview()
    if not preview then return true end
    if InCombatLockdown() then core.Combat.Queue(studio.ExitPreview,"studio:exit");return nil,"Exit queued until combat ends" end
    if core.UnitFrames then core.UnitFrames.Party.SetTest(preview.party);core.UnitFrames.Raid.SetTest(preview.raid) end
    if core.CastBars and core.CastBars.Preview then core.CastBars.Preview(false) end
    if core.Bags and core.Bags.Holder and not preview.bags then core.Bags.Holder:Hide() end
    preview=nil;core.Layout.Apply();return true
end
function studio.Capture(enabled,attribution,privacy)
    if not enabled then
        if capture then for _,entry in ipairs(capture) do if entry.shown then entry.frame:Show() end end end
        capture=nil;if studio.Attribution then studio.Attribution:Hide() end;return true
    end
    if InCombatLockdown() then return nil,"Capture mode is unavailable in combat" end
    if capture then return true end
    capture={}
    privacy=privacy or {chat=true,planner=true,inventory=true,sharing=true}
    local areas={chat={"RikUIChatHolder","RikUIChatStrip","GeneralDockManager"},planner={"RikUIQuestPlannerWindow","RikUIQuestTransfer"},inventory={"RikUIBags"},sharing={"RikUISharing"}}
    for i=1,math.min(10,tonumber(NUM_CHAT_WINDOWS) or 10) do for _,suffix in ipairs({"","Tab","EditBox"}) do areas.chat[#areas.chat+1]="ChatFrame"..i..suffix end end
    for area,names in pairs(areas) do if privacy[area] then for _,name in ipairs(names) do
        local frame=_G[name];if frame and type(frame.IsShown)=="function" then capture[#capture+1]={frame=frame,shown=frame:IsShown()};frame:Hide() end
    end end end
    if attribution and studio.Draft then
        if not studio.Attribution then studio.Attribution=core.WizardControls.Text(UIParent,"small","");studio.Attribution:SetPoint("BOTTOMLEFT",16,16) end
        studio.Attribution:SetText(studio.Draft.title.." / "..studio.Draft.creator);studio.Attribution:Show()
    end
    return true,"Hides listed RikUI/chat windows only; names, world and other addons remain visible"
end
function studio.GamepadLegend()
    if type(C_GamePad)~="table" or type(C_GamePad.IsEnabled)~="function" then return "Gamepad API unavailable; bindings preserved" end
    local ok,enabled=pcall(C_GamePad.IsEnabled)
    if not ok or not enabled then return "Gamepad inactive; bindings preserved" end
    local labels={}
    if type(GetBindingKey)=="function" then
        for i=1,4 do local read,key=pcall(GetBindingKey,"ACTIONBUTTON"..i)
            if read and type(key)=="string" and not core.Secret.IsSecret(key) then labels[#labels+1]=i..": "..key end
        end
    end
    return #labels>0 and table.concat(labels,"  ") or "Use Blizzard gamepad input legend; no binding changes"
end

-- Reviewed QuestTogether recipe: QT owns stock nameplate augmentation; RikUI reserves bubble space.
function studio.IntegrationAvailable()
    local reader=C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(reader)~="function" then return false end
    local ok,present=pcall(reader,"QuestTogether")
    return ok and present==true
end
function studio.IntegrationRecipe()
    if not studio.Draft then return nil,"Choose a setup" end
    studio.Draft.integration="questtogether"
    if studio.IntegrationAvailable() then
        studio.Draft.ownership.nameplates="specialist"
        studio.Draft.profile.modules=studio.Draft.profile.modules or {};studio.Draft.profile.modules.nameplates=false
    end
    return true,studio.IntegrationAvailable() and "QT owns nameplates; reload RikUI. Set QT icons Left, health tint off, and place its personal bubble in the reserved upper-left area. QT comparison/chat/location settings stay under QT control."
        or "QuestTogether absent or unavailable; RikUI remains responsible. No foreign settings changed."
end
function studio.PrepareCharacter()
    if not studio.Draft or not studio.Draft.character or not studio.Draft.character.preset then return nil,"This pack has no compatible character preset" end
    local ok,reason=safe();if not ok then return nil,reason end
    local preset=studio.Draft.character.preset
    local _,class=UnitClass("player")
    if class~=preset.class then return nil,"Character preset is for "..preset.class end
    local name="Studio-"..studio.Draft.id
    if #name>64 then name=name:sub(1,64) end
    local existing=core.PresetLibrary.Get(class,name)
    if not existing then
        local added,failure=core.PresetLibrary.Add(name,preset);if not added then return nil,failure end
    elseif not pack.Equal(existing,preset) then return nil,"Stored character preset differs; choose a new pack identity or use the preset library" end
    -- Explicit wizard review owns protected action/macros writes and its established recovery journal.
    core:Print("Character preset saved as "..name..". Open /rik setup and choose it; review macros and bars before Apply. Bindings are a separate explicit Studio operation.")
    if core.Wizard and core.Wizard.Open then core.Wizard.Open() end
    return true
end
function studio.ApplyBindings()
    local ok,reason=safe();if not ok then return nil,reason end
    local selected=studio.Draft and studio.Draft.character and studio.Draft.character.bindings
    if not selected or not next(selected) then return nil,"This pack contains no explicitly selected bindings" end
    local snapshot,failure=core.Bindings.CaptureSelected(selected);if not snapshot then return nil,failure end
    local point,index=restorePoint();if not point then return nil,index end
    point.bindings=snapshot
    local saved,problem=core.Store.Save("studio_restore_"..index,point);if not saved then return nil,problem end
    local nextState=copy(studio.State());nextState.restoreIndex=index
    local retained,retentionFailure=persist(nextState);if not retained then return nil,retentionFailure end
    return core.Bindings.ApplySelected(selected,snapshot)
end

core:RegisterEvent("GROUP_ROSTER_UPDATE",studio.AutoActivity)
core:RegisterEvent("PLAYER_UPDATE_RESTING",studio.AutoActivity)
core:RegisterEvent("PLAYER_REGEN_DISABLED",function() studio.Capture(false);studio.ExitPreview() end)
core:RegisterEvent("PLAYER_LOGOUT",function() studio.Capture(false);studio.ExitPreview() end)
