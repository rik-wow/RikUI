-- Compact guidance uses the existing tracker footprint; details open only on request.
local core,planner,media=RikUI,RikUI.QuestPlanner,RikUI.Media
local view={}
planner.View=view
local HEIGHT,WIDTH=110,240
local inline,window
local page,filterIndex=1,1
local FILTERS={"All","Available","Excluded"}
local PAGE_SIZE=8
local function filteredQuests()
    local result={}
    for _,quest in ipairs(planner.Controller.Quests()) do
        local excluded=quest.skipped or quest.avoided or quest.failed
        if filterIndex==1 or (filterIndex==2 and not excluded) or (filterIndex==3 and excluded) then result[#result+1]=quest end
    end
    return result
end
local function text(parent,role)
    local label=parent:CreateFontString(nil,"OVERLAY")
    media.Font(label,role or "small")
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    return label
end
local function button(parent,label,width,action)
    local control=CreateFrame("Button",nil,parent)
    control:SetSize(width,20); control:SetHighlightTexture(media.highlight)
    control.label=text(control); control.label:SetPoint("CENTER"); control.label:SetText(label)
    control:SetScript("OnClick",action)
    return control
end
local function enabled(control,value)
    control:SetEnabled(value)
    control.label:SetAlpha(value and 1 or .4)
end
local function command(value) if planner.Command then planner.Command(value) end end
local function selectedID()
    local model=planner.Controller.Get()
    return model.selected and model.selected.questID
end
local function selectedCommand(name)
    local id=selectedID()
    if id then command(name.." "..id) end
end
local function instruction(frame,model,hint)
    if hint and model.selected and model.status~="paused" and model.status~="updating" then
        local value=hint.text.."\n"..hint.subtext
        if frame.status:GetText()~=value then frame.status:SetText(value) end
        frame.arrowHint:SetText("Estimated route")
    else
        frame.status:SetText(planner.Guidance.RouteStatus(model,planner.Terrain and planner.Terrain.Status()))
        frame.arrowHint:SetText("Direction guide")
    end
end
function view.RefreshInstruction(hint)
    local model=planner.Controller.Get()
    if inline and inline:IsShown() then instruction(inline,model,hint) end
    if window and window:IsShown() then instruction(window.summary,model,hint) end
end
local function destinationFloor(frame)
    local floors=planner.Terrain and planner.Terrain.Floors and planner.Terrain.Floors()
    local available=floors and #floors.choices>1
    frame.floor:SetShown(available==true)
    frame.arrowHint:SetShown(not available)
    if not available then return end
    frame.floor.selection=floors
    local choice=floors.choices[floors.selected]
    frame.floor.label:SetText(choice and choice.label or floors.automatic and ("Auto: "..floors.automatic.label) or "Floor: Auto")
end
local function chooseFloor(control)
    local floors=control.selection
    if not floors then return end
    local ok,reason=planner.Terrain.SelectFloor((floors.selected+1)%(#floors.choices+1),floors.key)
    if not ok then core:Print(reason) end
    view.Refresh()
end
local function details(frame,model)
    local title=model.selected and ((model.calculated and "Next: " or "Quest: ")..model.selected.title) or "Quest planner"
    frame.title:SetText(title)
    frame.detail:SetText(model.selected and model.selected.detail or model.detail)
    instruction(frame,model,planner.Navigation and planner.Navigation.Instruction and planner.Navigation.Instruction())
    frame.pause.label:SetText(planner.Controller.Policy().paused and "Resume" or "Pause")
    frame.pin.label:SetText(model.selected and planner.Controller.Policy().pins[model.selected.questID] and "Unpin" or "Pin")
    frame.arrowToggle.label:SetText(planner.Controller.Policy().arrow and "Arrow: on" or "Arrow: off")
    destinationFloor(frame)
    frame.model=model
end
local function tooltip(frame)
    local model=frame.model or {}
    GameTooltip:SetOwner(frame,"ANCHOR_LEFT")
    GameTooltip:SetText(model.selected and model.selected.title or "Quest planner")
    GameTooltip:AddLine(model.detail or "",1,1,1,true)
    local hint=model.selected and model.selected.targetHint
    if hint then GameTooltip:AddLine("Reported interaction: "..hint.instructions,1,1,1,true) end
    if planner.Terrain then
        local route,state=planner.Terrain.Guidance(),planner.Terrain.Status()
        if route then GameTooltip:AddLine(string.format("Terrain estimate: %.0f yd, %.0fs running; traversal unverified",route.meters,route.seconds),1,.7,.2,true)
        elseif state and state.detail then GameTooltip:AddLine(state.detail,1,.7,.2,true) end
        if route and route.approach then GameTooltip:AddLine(route.detail,1,.7,.2,true) end
        if route and route.destinationFloor then
            local floor=route.destinationFloor
            GameTooltip:AddLine(floor.basis or (floor.label.." selected by you; quest target floor remains unverified."),1,.7,.2,true)
        end
    end
    if model.reason then GameTooltip:AddLine(model.reason,.7,.8,.9,true) end
    if model.change then GameTooltip:AddLine(model.change,1,.8,.3,true) end
    if model.seconds then
        local rate=model.xp and model.xp/math.max(1,model.seconds)*60
        GameTooltip:AddLine(string.format("Modeled sequence: %.0fs; known XP %.0f (%.1f/min)",model.seconds,model.xp or 0,rate or 0),.7,.8,.9,true)
    end
    if model.deferredPins and #model.deferredPins>0 then GameTooltip:AddLine("Pinned quests awaiting a feasible plan: "..#model.deferredPins,1,.8,.3,true) end
    GameTooltip:Show()
end
local function floorControl(frame)
    frame.floor=button(frame,"Floor: Auto",124,chooseFloor)
    frame.floor:SetPoint("LEFT",frame.arrowToggle,"RIGHT",4,0);frame.floor:Hide()
    frame.floor:SetScript("OnEnter",function(control)
        GameTooltip:SetOwner(control,"ANCHOR_LEFT");GameTooltip:SetText("Destination floor")
        GameTooltip:AddLine("Click to cycle Auto, then modeled floors from lowest to highest.",1,1,1,true)
        local automatic=control.selection and control.selection.automatic
        if automatic then GameTooltip:AddLine(automatic.basis,1,.7,.2,true) end
        GameTooltip:AddLine("Chooses a walking destination; it does not confirm which floor contains the quest target.",1,.7,.2,true)
        GameTooltip:Show()
    end)
    frame.floor:SetScript("OnLeave",function() GameTooltip:Hide() end)
end
local function create(parent)
    local frame=CreateFrame("Frame",nil,parent)
    frame:SetSize(WIDTH,HEIGHT)
    local fill=frame:CreateTexture(nil,"BACKGROUND"); fill:SetAllPoints(); fill:SetColorTexture(.035,.07,.1,.94)
    frame.title=text(frame,"label"); frame.title:SetPoint("TOPLEFT",6,-3); frame.title:SetPoint("TOPRIGHT",-6,-3); frame.title:SetHeight(15)
    frame.detail=text(frame); frame.detail:SetPoint("TOPLEFT",6,-20); frame.detail:SetPoint("TOPRIGHT",-6,-20); frame.detail:SetHeight(13)
    frame.status=text(frame); frame.status:SetPoint("TOPLEFT",6,-34); frame.status:SetPoint("TOPRIGHT",-6,-34); frame.status:SetHeight(29); frame.status:SetWordWrap(true)
    frame.status:SetTextColor(.55,.75,.9)
    frame.arrowToggle=button(frame,"Arrow: off",92,function()
        command("arrow "..(planner.Controller.Policy().arrow and "off" or "on"))
    end)
    frame.arrowToggle:SetPoint("BOTTOMLEFT",4,22)
    frame.arrowHint=text(frame);frame.arrowHint:SetPoint("LEFT",frame.arrowToggle,"RIGHT",4,0)
    frame.arrowHint:SetText("Direction guide")
    floorControl(frame)
    frame.pause=button(frame,"Pause",48,function()
        command(planner.Controller.Policy().paused and "resume" or "pause")
    end)
    frame.pin=button(frame,"Pin",40,function() selectedCommand("pin") end)
    local controls={frame.pause,button(frame,"Map",40,function() command("map") end),frame.pin,
        button(frame,"Skip",40,function() selectedCommand("skip") end),button(frame,"More",44,view.Open)}
    local offset=4
    for _,control in ipairs(controls) do control:SetPoint("BOTTOMLEFT",offset,0); offset=offset+control:GetWidth() end
    frame:EnableMouse(true); frame:SetScript("OnEnter",tooltip); frame:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return frame
end
function view.RenderInline(holder,offset,limit,collapsed)
    if not planner.enabled then if inline then inline:Hide() end; return 0 end
    if not inline then inline=create(holder) end
    if collapsed or (limit and offset+HEIGHT>limit) then inline:Hide(); return 0 end
    if inline:GetParent()~=holder then inline:SetParent(holder) end
    inline:ClearAllPoints(); inline:SetPoint("TOPLEFT",holder,"TOPLEFT",0,-offset)
    details(inline,planner.Controller.Get()); inline:Show()
    return HEIGHT+6
end
local function close()
    if window then window:Hide() end
end
local function createWindow()
    window=CreateFrame("Frame","RikUIQuestPlannerWindow",UIParent)
    window:SetSize(700,422); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:EnableMouse(true)
    local fill=window:CreateTexture(nil,"BACKGROUND"); fill:SetAllPoints(); fill:SetColorTexture(.04,.05,.07,.98)
    window.heading=text(window,"heading"); window.heading:SetPoint("TOPLEFT",12,-10); window.heading:SetText("Quest planner")
    local exit=button(window,"Close",52,close); exit:SetPoint("TOPRIGHT",-8,-8)
    window.summary=create(window); window.summary:SetPoint("TOPLEFT",12,-38); window.summary:SetWidth(676)
    window.retry=button(window.summary,"Retry route",88,function() command("retry") end)
    window.retry:SetPoint("BOTTOMRIGHT",-4,0)
    window.automatic=button(window.summary,"Automatic choice",124,function() command("route auto") end)
    window.automatic:SetPoint("BOTTOMRIGHT",-96,0)
    window.rows={}
    for index=1,PAGE_SIZE do
        local row=button(window,"",416,function(self)
            if self.questID then planner.OpenQuest(self.questID) end
        end)
        row:SetPoint("TOPLEFT",12,-154-(index-1)*23)
        row.label:ClearAllPoints(); row.label:SetPoint("LEFT",3,0); row.label:SetPoint("RIGHT",-3,0)
        local pin=button(window,"Pin",52,function()
            if row.questID then command("pin "..row.questID) end
        end)
        pin:SetPoint("LEFT",row,"RIGHT",0,0); row.pin=pin
        row.skip=button(window,"Skip",60,function()
            if row.questID then command("skip "..row.questID) end
        end)
        row.skip:SetPoint("LEFT",pin,"RIGHT",0,0)
        row.area=button(window,"Avoid area",84,function()
            if row.mapID then command("avoid "..row.mapID) end
        end)
        row.area:SetPoint("LEFT",row.skip,"RIGHT",0,0)
        row.route=button(window,"Route",64,function()
            if row.questID then command("route "..row.questID) end
        end)
        row.route:SetPoint("LEFT",row.area,"RIGHT",0,0)
        window.rows[index]=row
    end
    local previous=button(window,"Previous",80,function() page=math.max(1,page-1); view.Refresh() end)
    previous:SetPoint("BOTTOMLEFT",12,46);window.previous=previous
    local following=button(window,"Next",64,function() page=page+1; view.Refresh() end)
    following:SetPoint("LEFT",previous,"RIGHT",6,0);window.following=following
    window.filter=button(window,"Show: All",152,function()
        filterIndex=filterIndex%#FILTERS+1;page=1;view.Refresh()
    end)
    window.filter:SetPoint("BOTTOMLEFT",174,46)
    window.empty=text(window);window.empty:SetPoint("TOPLEFT",12,-164)
    window.empty:SetSize(676,58);window.empty:SetWordWrap(true)
    local reset=button(window,"Reset constraints",130,function() command("reset") end)
    reset:SetPoint("BOTTOMRIGHT",-12,46)
    window.page=text(window); window.page:SetPoint("BOTTOM",60,52)
    window.arrow=button(window,"Arrow: off",92,function() command("arrow "..(planner.Controller.Policy().arrow and "off" or "on")) end)
    window.dungeons=button(window,"Dungeons: off",110,function() command("dungeons "..(planner.Controller.Policy().dungeons and "off" or "on")) end)
    local avoid=button(window,"Avoid area",92,function()
        local model=planner.Controller.Get(); local point=model.selected and model.selected.destination
        if point then command("avoid "..point.mapID) else core:Print("This quest has no observed map location.") end
    end)
    local export=button(window,"Copy data",92,function() command("export") end)
    for index,control in ipairs({window.arrow,window.dungeons,avoid,export}) do control:SetPoint("BOTTOMLEFT",12+(index-1)*106,12) end
    if type(UISpecialFrames)=="table" then table.insert(UISpecialFrames,"RikUIQuestPlannerWindow") end
    window.restoreArea=button(window,"",246,function(control)
        if control.mapID and planner.Controller.Policy().avoids[control.mapID] then command("avoid "..control.mapID) end
    end)
    window.restoreArea:SetPoint("BOTTOMRIGHT",-12,12)
    view.Window=window
end
local function avoidedArea(policy)
    local ids={}
    for id in pairs(policy.avoids) do ids[#ids+1]=id end
    table.sort(ids)
    local id=ids[1]
    window.restoreArea.mapID=id
    window.restoreArea:SetShown(id~=nil)
    if not id then return end
    local ok,info=planner.Context.Call(C_Map and C_Map.GetMapInfo,id)
    local name=ok and planner.Schema.PlainTable(info) and planner.Schema.Text(info.name) and planner.Guidance.Text(info.name)
    window.restoreArea.label:SetText("Allow "..(name or ("map "..id)))
end
function view.Refresh()
    local model=planner.Controller.Get()
    if inline then details(inline,model) end
    if not window or not window:IsShown() then return end
    details(window.summary,model)
    local policy=planner.Controller.Policy()
    window.arrow.label:SetText(policy.arrow and "Arrow: on" or "Arrow: off")
    window.dungeons.label:SetText(policy.dungeons and "Dungeons: on" or "Dungeons: off")
    window.automatic:SetShown(model.manual==true)
    avoidedArea(policy)
    local quests=filteredQuests()
    local pages=math.max(1,math.ceil(#quests/PAGE_SIZE))
    page=math.min(page,pages); window.page:SetText(page.."/"..pages)
    enabled(window.previous,page>1);enabled(window.following,page<pages)
    window.filter.label:SetText("Show: "..FILTERS[filterIndex])
    window.empty:SetShown(#quests==0)
    window.empty:SetText(filterIndex==2 and "No available quests. Show All to restore skipped quests or avoided areas."
        or filterIndex==3 and "No excluded quests." or "No current quest observations. Open your quest log or wait for it to update.")
    for index,row in ipairs(window.rows) do
        local quest=quests[(page-1)*PAGE_SIZE+index]
        row.questID=quest and quest.questID
        row:SetShown(quest~=nil); row.pin:SetShown(quest~=nil); row.skip:SetShown(quest~=nil)
        row.mapID=quest and quest.destination and quest.destination.mapID
        row.area:SetShown(row.mapID~=nil)
        row.route:SetShown(quest~=nil)
        enabled(row.route,quest~=nil and row.mapID~=nil and not quest.skipped and not quest.avoided and not quest.failed)
        if quest then
            row.area.label:SetText(quest.avoided and "Allow area" or "Avoid area")
            row.route.label:SetText(model.selected and model.selected.questID==quest.questID and "Selected" or "Route")
            row.questID=quest.questID; row.label:SetText((quest.skipped and "Skipped: " or quest.avoided and "Area avoided: " or quest.failed and "Failed: "
                or quest.kind=="turnin" and "Turn in: " or "")..quest.title)
            row.skip.label:SetText(quest.skipped and "Include" or "Skip")
            row.pin.label:SetText(policy.pins[quest.questID] and "Unpin" or "Pin")
        end
    end
end
function view.Open()
    if not planner.enabled then return end
    core.Combat.Queue(function()
        if not window then createWindow() end
        window:Show(); view.Refresh()
    end,"questplanner:window")
end
