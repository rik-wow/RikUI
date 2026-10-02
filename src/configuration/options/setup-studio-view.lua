-- The addon journey: choose, select parts, fit/review, try on, apply, personalize, share/update.
local core,studio,pack=RikUI,RikUI.Studio,RikUI.SetupPack
local controls=core.WizardControls
local window,accepts,history,redo=nil,{}, {},{}
local privacy={chat=true,planner=true,inventory=true,sharing=true}
local attribution=true
local function report(ok,reason)
    local detail=type(reason)=="table" and ((reason.status or "Result")..": "..tostring(reason.error or reason.reason or "settings written; review reload requirements")) or reason
    if window then window.status:SetText(ok and (type(detail)=="string" and detail or "Done. Review reload requirements below.") or tostring(detail)) end
    if window then studio.RefreshWindow() end
end
local function remember()
    if studio.Draft then history[#history+1]=pack.Copy(studio.Draft);if #history>20 then table.remove(history,1) end end
    redo={}
end
local function button(text,x,y,action,width)
    local b=controls.Button(window,text,function() action();studio.RefreshWindow() end)
    b:SetSize(width or 130,30);b:SetPoint("TOPLEFT",x,-y)
    return b
end
function studio.Select(name)
    studio.State()
    remember();local value,reason=pack.Bundled(name);if not value then return nil,reason end
    studio.Draft=value;studio.Selected=pack.Copy(value.components);studio.Selected.character=false;accepts={}
    return true
end
function studio.Recipe(name)
    studio.Selected={}
    if name=="everything" then for c in pairs(pack.Components) do studio.Selected[c]=c~="character" end
    elseif pack.Components[name] then studio.Selected[name]=true else return nil,"Unknown component recipe" end
    return true
end
function studio.Remix()
    if not studio.Draft then return end
    if studio.Draft.creator=="You" then
        local installed=studio.State().installed and pack.Decode(studio.State().installed)
        if installed and installed.id==studio.Draft.id then studio.Draft.revision=math.max(studio.Draft.revision,installed.revision+1) end
        return
    end
    local p=studio.Draft
    p.ancestry={id=p.id,revision=p.revision,creator=p.creator}
    p.id="remix-"..core.Codec.ChecksumHex(assert(pack.Encode(p)));p.revision=1;p.creator="You"
    p.title=(p.title:sub(1,72).." remix")
end
function studio.EditTheme(key,value)
    if not studio.Draft then return nil,"Choose a pack" end
    remember();studio.Remix();studio.Draft.profile.theme=studio.Draft.profile.theme or pack.Copy(pack.Themes.classic.theme)
    if key=="font" or key=="scale" or key=="textScale" then studio.Draft.adjustments=studio.Draft.adjustments or {};studio.Draft.adjustments[key]=value else studio.Draft.adjustments=studio.Draft.adjustments or {};studio.Draft.adjustments.theme=studio.Draft.adjustments.theme or pack.Copy(studio.Draft.profile.theme);studio.Draft.adjustments.theme[key]=value end
    return pack.Validate(studio.Draft)
end
function studio.ThemeExport()
    if not studio.Draft then return nil,"Choose a pack" end
    local resolved,reason=studio.Resolve();if not resolved then return nil,reason end
    local p=resolved.profile
    local value=pack.FromProfile({theme=pack.Copy(p.theme),font=p.font,borderColor=pack.Copy(p.borderColor),textScale=p.textScale},
        {id=studio.Draft.id:sub(1,58).."-theme",title=studio.Draft.title:sub(1,74).." theme",creator=studio.Draft.creator},{})
    if not value then return nil,"Theme exceeds metadata capacity" end
    value.components={appearance=true}
    return pack.Encode(value)
end
function studio.DraftUndo(forward)
    local from,to=forward and redo or history,forward and history or redo
    if #from==0 then return nil,"No edit to undo" end
    to[#to+1]=pack.Copy(studio.Draft);studio.Draft=table.remove(from);return true
end
local groupIndex,conflictIndex=1,1
local function groupKeys()
    local keys={};for key in pairs(studio.Draft and studio.Draft.groups or {}) do keys[#keys+1]=key end;table.sort(keys);return keys
end
function studio.MoveGroup(dx,dy)
    local keys=groupKeys();local key=keys[groupIndex];if not key then return nil,"No movable group in this pack" end
    local resolved,reason=studio.Resolve();if not resolved then return nil,reason end
    local position=resolved.profile.positions[key];if not position then return nil,"No resolved anchor for this group" end
    remember();studio.Remix();studio.Draft.adjustments=studio.Draft.adjustments or {};studio.Draft.adjustments.positions=studio.Draft.adjustments.positions or {}
    position=pack.Copy(position);position.x=math.floor((position.x+dx)/8+0.5)*8;position.y=math.floor((position.y+dy)/8+0.5)*8
    studio.Draft.adjustments.positions[key]=position
    return pack.Validate(studio.Draft)
end
function studio.RefreshWindow()
    if not window then return end
    local p=studio.Draft
    if not p then window.details:SetText("Choose a curated setup or import a code. No settings change until Apply.");return end
    local review,reason=studio.Review(accepts)
    local lines={p.title.."  ·  "..p.creator.."  ·  revision "..p.revision,
        "Device: "..studio.Device.."  Activity: "..studio.Activity.."  "..(studio.Pinned and "(pinned)" or "(automatic)")}
    for _,c in ipairs({"appearance","hud","nameplates","group","navigation","inventory","character"}) do
        if studio.Selected[c] then lines[#lines+1]=c..": "..tostring(p.ownership[c]) end
    end
    if review then
        lines[#lines+1]=review.reload and "Reload required for module/font/theme changes. Activity transitions do not reload." or "Geometry applies outside combat."
        for _,conflict in ipairs(review.fit.conflicts) do lines[#lines+1]="Fit: "..conflict.key.." — "..conflict.reason end
        for _,conflict in ipairs(review.conflicts) do lines[#lines+1]="Update: "..conflict.path.." — "..(accepts[conflict.path] and "take creator" or "keep personal edit") end
        lines[#lines+1]="Restore slots: 3. One installed source, bounded to codec capacity. Export a portable backup for client restart."
    else lines[#lines+1]=tostring(reason) end
    local keys=groupKeys();if groupIndex>#keys then groupIndex=1 end
    window.group:SetText("Adjust: "..(keys[groupIndex] or "no groups").." (8-unit snap)")
    window.details:SetText(table.concat(lines,"\n"))
    if window.checks then for _,check in ipairs(window.checks) do check:Refresh() end end
end
local function build()
    window=CreateFrame("Frame","RikUIStudio",UIParent);studio.Window=window
    window:SetSize(760,740);window:SetPoint("CENTER");window:SetFrameStrata("DIALOG");window:EnableMouse(true)
    core.Skin.Fill(window);core.Skin.Outline(window)
    local title=controls.Text(window,"heading","RikUI Setup Studio");title:SetPoint("TOPLEFT",20,-18)
    local note=controls.Text(window,"small","Choose > Select parts > Fit > Preview > Apply > Personalize > Share/update");note:SetPoint("TOPLEFT",20,-44)
    for i,name in ipairs({"centered","classic","hud","healer"}) do button(name,20+(i-1)*145,68,function() report(studio.Select(name)) end) end
    button("Import",600,68,function() core.Sharing.OpenDialog("Import Setup Pack",nil,function(_,code) local ok,why=studio.Import(code);studio.RefreshWindow();return ok,why end,"Paste !RIKS1!, or a legacy UI/preset code. This only stages a review.","Imported for review in /rik studio.") end)
    window.checks={}
    for i,c in ipairs({"appearance","hud","nameplates","group","navigation","inventory"}) do
        local check=controls.Check(window,118,c,function() return studio.Selected[c]==true end,function(on) studio.Selected[c]=on end)
        check:SetPoint("TOPLEFT",20+(i-1)*120,-112);window.checks[#window.checks+1]=check
    end
    for i,name in ipairs({"classic","ocean","ink"}) do button(name.." theme",20+(i-1)*145,148,function()
        remember();studio.Remix();studio.Draft.adjustments=pack.Merge(studio.Draft.adjustments or {},pack.Themes[name]);report(true,"Theme staged; reload after Apply")
    end) end
    button("Density +",455,148,function() report(studio.EditTheme("scale",math.min(1.3,((studio.Draft.adjustments or {}).scale or studio.Draft.profile.scale or 1)+0.05))) end)
    button("Density -",600,148,function() report(studio.EditTheme("scale",math.max(0.85,((studio.Draft.adjustments or {}).scale or studio.Draft.profile.scale or 1)-0.05))) end)
    for i,key in ipairs({"accent","border","texture","font","spacing"}) do button(key,20+(i-1)*145,188,function()
        local choices={accent={"gold","blue","white"},border={1,2,3},texture={"bundled","flat"},font={"bundled","game"},spacing={"standard","relaxed"}}
        local current=key=="font" and ((studio.Draft.adjustments or {}).font or studio.Draft.profile.font) or ((studio.Draft.adjustments or {}).theme or studio.Draft.profile.theme or {})[key]
        local list=choices[key];local index=1;for n,value in ipairs(list)do if value==current then index=n%#list+1 end end
        report(studio.EditTheme(key,list[index]))
    end) end
    for i,name in ipairs({"standard","readable","contrast","calm"}) do button(name,20+(i-1)*145,228,function() report(studio.Accessibility(name)) end) end
    button("QT recipe",600,228,function() report(studio.IntegrationRecipe()) end)
    for i,name in ipairs({"desktop","ultrawide","handheld"}) do button(name,20+(i-1)*145,268,function() studio.Device=name;report(true,studio.GamepadLegend()) end) end
    button("Activity",455,268,function()
        local order={"exploration","party","raid","town"};local nextIndex=1;for i,name in ipairs(order) do if name==studio.Activity then nextIndex=i%4+1 end end
        report(studio.Presentation(order[nextIndex],studio.Device,true))
    end)
    button("Auto / pin",600,268,function() studio.Pinned=not studio.Pinned;studio.AutoActivity() end)
    local recipes={"everything","appearance","hud","group","navigation"};local recipeIndex=1
    button("Adopt parts",600,300,function()local name=recipes[recipeIndex];recipeIndex=recipeIndex%#recipes+1;report(studio.Recipe(name),"Adoption recipe: "..name)end)
    window.group=controls.Text(window,"small","");window.group:SetPoint("TOPLEFT",20,-314)
    button("Next frame",20,340,function() groupIndex=groupIndex%math.max(1,#groupKeys())+1 end)
    button("Left",165,340,function() report(studio.MoveGroup(-8,0)) end,60)
    button("Right",230,340,function() report(studio.MoveGroup(8,0)) end,60)
    button("Up",295,340,function() report(studio.MoveGroup(0,8)) end,60)
    button("Down",360,340,function() report(studio.MoveGroup(0,-8)) end,60)
    button("Undo edit",455,340,function() report(studio.DraftUndo(false)) end)
    button("Redo edit",600,340,function() report(studio.DraftUndo(true)) end)
    window.scroll=CreateFrame("ScrollFrame",nil,window);window.scroll:SetPoint("TOPLEFT",20,-380);window.scroll:SetSize(720,145)
    local body=CreateFrame("Frame",nil,window.scroll);body:SetSize(710,540);window.scroll:SetScrollChild(body)
    window.details=controls.Text(body,"small","");window.details:SetPoint("TOPLEFT",0,0);window.details:SetWidth(700);window.details:SetJustifyH("LEFT")
    window.scroll:EnableMouseWheel(true);window.scroll:SetScript("OnMouseWheel",function(self,delta) self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*36))) end)
    button("Fit / review",20,540,function() studio.RefreshWindow() end)
    button("Try on",165,540,function() report(studio.TryOn(studio.Activity)) end)
    button("Cast sample",310,540,function() report(studio.TryOn("casting")) end)
    button("Inventory",455,540,function() report(studio.TryOn("inventory")) end)
    button("Exit try-on",600,540,function() report(studio.ExitPreview()) end)
    button("Apply setup",20,578,function() report(studio.Apply(accepts)) end)
    button("Update choice",165,578,function()
        local review=studio.Review(accepts);local conflict=review and review.conflicts[conflictIndex]
        conflictIndex=review and conflictIndex%math.max(1,#review.conflicts)+1 or 1
        if conflict then accepts[conflict.path]=not accepts[conflict.path];report(true,conflict.path..": "..(accepts[conflict.path] and "take creator" or "keep personal")) end
    end)
    button("Restore",310,578,function() report(studio.Restore()) end)
    button("Character",455,578,function() report(studio.PrepareCharacter()) end)
    button("Bindings",600,578,function() report(studio.ApplyBindings()) end)
    button("Export live",20,616,function() local code,why=studio.Export();if code then core.Sharing.OpenDialog("Export current setup",code,nil,"Shares supported settings and geometry; no private records or restoration history.") else report(nil,why) end end)
    button("Share draft",165,616,function() local value=pack.Copy(studio.Draft);value.components=pack.Copy(studio.Selected);if not value.components.character then value.character=nil end
        local code,why=pack.Encode(value);if code then core.Sharing.OpenDialog("Share Setup Pack",code,nil,"Open rikwow.com/studio to edit or create a shareable link.") else report(nil,why) end end)
    button("Theme export",310,616,function() local code,why=studio.ThemeExport();if code then core.Sharing.OpenDialog("Share theme",code,nil,"Appearance-only Setup Pack.") else report(nil,why) end end)
    button("Capture",455,616,function() report(studio.Capture(true,attribution,privacy)) end)
    button("Exit capture",600,616,function() report(studio.Capture(false)) end)
    button("Export bars",20,656,function() local code,why=studio.ExportCharacter();if code then core.Sharing.OpenDialog("Export live standard bars",code,nil,"Main and four standard pages, referenced macros only. Script macros and unknown catalogue spells are refused. Bindings excluded.") else report(nil,why) end end)
    button("Bars + keys",165,656,function() local code,why=studio.ExportCharacter(nil,true);if code then core.Sharing.OpenDialog("Export bars and main keys",code,nil,"Explicitly includes bindings for ACTIONBUTTON1..12 plus standard pages and referenced macros. Inspect character data before sharing.") else report(nil,why) end end)
    for i,area in ipairs({"chat","planner","inventory"}) do
        local check=controls.Check(window,110,"Hide "..area,function()return privacy[area]end,function(on)privacy[area]=on end)
        check:SetPoint("TOPLEFT",310+(i-1)*140,-656);window.checks[#window.checks+1]=check
    end
    local credit=controls.Check(window,160,"Pack attribution",function()return attribution end,function(on)attribution=on end)
    credit:SetPoint("TOPLEFT",575,-20);window.checks[#window.checks+1]=credit
    window.status=controls.Text(window,"small","");window.status:SetPoint("BOTTOMLEFT",20,20);window.status:SetWidth(560);window.status:SetJustifyH("LEFT")
    local close=controls.Button(window,"Close",function() window:Hide() end);close:SetPoint("BOTTOMRIGHT",-20,14)
    window:EnableKeyboard(true)
    window:SetPropagateKeyboardInput(true)
    window:SetScript("OnKeyDown",function(self,key)
        local delta={LEFT={-8,0},RIGHT={8,0},UP={0,8},DOWN={0,-8}}
        if delta[key] then self:SetPropagateKeyboardInput(false);report(studio.MoveGroup(unpack(delta[key])))
        elseif key=="TAB" then self:SetPropagateKeyboardInput(false);groupIndex=groupIndex%math.max(1,#groupKeys())+1;studio.RefreshWindow()
        else self:SetPropagateKeyboardInput(true) end
    end)
    window:SetScript("OnHide",function() studio.Capture(false);studio.ExitPreview() end)
    if type(UISpecialFrames)=="table" then UISpecialFrames[#UISpecialFrames+1]="RikUIStudio" end
end
function studio.Open()
    if InCombatLockdown() then return nil,"Open Setup Studio out of combat" end
    if not core.Profile then return nil,"Still loading" end
    if not studio.Draft then studio.Select("centered") end
    if not window then build() end
    local screen=core.Layout.Screen()
    window:SetScale(math.min(1,(screen.width-16)/760,(screen.height-16)/740))
    studio.RefreshWindow();window:Show();return true
end
core:RegisterCommand("studio",function(args)
    if args=="" then report(studio.Open())
    elseif args=="exit" then studio.ExitPreview();studio.Capture(false)
    elseif args:match("^accept ") then accepts[args:sub(8)]=true;studio.RefreshWindow()
    elseif args:match("^restore ") then report(studio.Restore(tonumber(args:sub(9))))
    else core:Print("Usage: /rik studio [exit|accept <conflict path>|restore <1..3>]") end
end,"Configure, fit, share and safely update Setup Packs",studio)
