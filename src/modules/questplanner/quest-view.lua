-- Compact guidance uses the existing tracker footprint; details open only on request.
local core,planner,media=RikUI,RikUI.QuestPlanner,RikUI.Media
local view={}
planner.View=view
local HEIGHT,WIDTH=110,240
local inline,window
local page=1
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
local function command(value) if planner.Command then planner.Command(value) end end
local function selectedID()
    local model=planner.Controller.Get()
    return model.selected and model.selected.questID
end
local function selectedCommand(name)
    local id=selectedID()
    if id then command(name.." "..id) end
end
local function details(frame,model)
    local title=model.selected and ((model.calculated and "Next: " or "Quest: ")..model.selected.title) or "Quest planner"
    frame.title:SetText(title)
    frame.detail:SetText(model.selected and model.selected.detail or model.detail)
    frame.status:SetText(planner.Guidance.RouteStatus(model,planner.Terrain and planner.Terrain.Status()))
    frame.pause.label:SetText(planner.Controller.Policy().paused and "Resume" or "Pause")
    frame.pin.label:SetText(model.selected and planner.Controller.Policy().pins[model.selected.questID] and "Unpin" or "Pin")
    frame.arrowToggle.label:SetText(planner.Controller.Policy().arrow and "Arrow: on" or "Arrow: off")
    frame.model=model
end
local function tooltip(frame)
    local model=frame.model or {}
    GameTooltip:SetOwner(frame,"ANCHOR_LEFT")
    GameTooltip:SetText(model.selected and model.selected.title or "Quest planner")
    GameTooltip:AddLine(model.detail or "",1,1,1,true)
    if planner.Terrain then
        local route,state=planner.Terrain.Guidance(),planner.Terrain.Status()
        if route then GameTooltip:AddLine(string.format("Terrain estimate: %.0f yd, %.0fs running; traversal unverified",route.meters,route.seconds),1,.7,.2,true)
        elseif state and state.detail then GameTooltip:AddLine(state.detail,1,.7,.2,true) end
        if route and route.approach then GameTooltip:AddLine(route.detail,1,.7,.2,true) end
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
    window:SetSize(450,422); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:EnableMouse(true)
    local fill=window:CreateTexture(nil,"BACKGROUND"); fill:SetAllPoints(); fill:SetColorTexture(.04,.05,.07,.98)
    window.heading=text(window,"heading"); window.heading:SetPoint("TOPLEFT",12,-10); window.heading:SetText("Quest planner")
    local exit=button(window,"Close",52,close); exit:SetPoint("TOPRIGHT",-8,-8)
    window.summary=create(window); window.summary:SetPoint("TOPLEFT",12,-38); window.summary:SetWidth(426)
    window.rows={}
    for index=1,8 do
        local row=button(window,"",370,function(self)
            if self.questID then planner.OpenQuest(self.questID) end
        end)
        row:SetPoint("TOPLEFT",12,-154-(index-1)*23)
        row.label:ClearAllPoints(); row.label:SetPoint("LEFT",3,0); row.label:SetPoint("RIGHT",-3,0)
        local pin=button(window,"Pin",52,function()
            if row.questID then command("pin "..row.questID) end
        end)
        pin:SetPoint("LEFT",row,"RIGHT",0,0); row.pin=pin; window.rows[index]=row
    end
    local previous=button(window,"Previous",80,function() page=math.max(1,page-1); view.Refresh() end)
    previous:SetPoint("BOTTOMLEFT",12,46)
    local following=button(window,"Next",64,function() page=page+1; view.Refresh() end)
    following:SetPoint("LEFT",previous,"RIGHT",6,0)
    local reset=button(window,"Reset constraints",130,function() command("reset") end)
    reset:SetPoint("BOTTOMRIGHT",-12,46)
    window.page=text(window); window.page:SetPoint("BOTTOM",0,52)
    window.arrow=button(window,"Arrow: off",92,function() command("arrow "..(planner.Controller.Policy().arrow and "off" or "on")) end)
    window.dungeons=button(window,"Dungeons: off",110,function() command("dungeons "..(planner.Controller.Policy().dungeons and "off" or "on")) end)
    local avoid=button(window,"Avoid area",92,function()
        local model=planner.Controller.Get(); local point=model.selected and model.selected.destination
        if point then command("avoid "..point.mapID) else core:Print("This quest has no observed map location.") end
    end)
    local export=button(window,"Copy data",92,function() command("export") end)
    for index,control in ipairs({window.arrow,window.dungeons,avoid,export}) do control:SetPoint("BOTTOMLEFT",12+(index-1)*106,12) end
    if type(UISpecialFrames)=="table" then table.insert(UISpecialFrames,"RikUIQuestPlannerWindow") end
    view.Window=window
end
function view.Refresh()
    local model=planner.Controller.Get()
    if inline then details(inline,model) end
    if not window or not window:IsShown() then return end
    details(window.summary,model)
    local policy=planner.Controller.Policy()
    window.arrow.label:SetText(policy.arrow and "Arrow: on" or "Arrow: off")
    window.dungeons.label:SetText(policy.dungeons and "Dungeons: on" or "Dungeons: off")
    local pages=math.max(1,math.ceil(#(model.quests or {})/8))
    page=math.min(page,pages); window.page:SetText(page.."/"..pages)
    for index,row in ipairs(window.rows) do
        local quest=model.quests and model.quests[(page-1)*8+index]
        row:SetShown(quest~=nil); row.pin:SetShown(quest~=nil)
        if quest then
            row.questID=quest.questID; row.label:SetText((quest.kind=="turnin" and "Turn in: " or "")..quest.title)
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
