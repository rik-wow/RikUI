-- Compact guidance uses the existing tracker footprint; details open only on request.
local core,planner,media=RikUI,RikUI.QuestPlanner,RikUI.Media
local view={}
planner.View=view
local HEIGHT,WIDTH=110,240
local inline
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
    control.label:SetSize(width-8,18)
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
local function instruction(frame,model,hint)
    if hint and model.selected and model.status~="paused" and model.status~="updating" then
        local value=hint.text.."\n"..hint.subtext
        if frame.status:GetText()~=value then frame.status:SetText(value) end
        frame.arrowHint:SetText(model.localGuidance and "Partial quest data" or "Estimated route")
    else
        frame.status:SetText(planner.Guidance.RouteStatus(model,planner.Terrain and planner.Terrain.Status()))
        frame.arrowHint:SetText(model.localGuidance and "Partial quest data" or "Direction guide")
    end
end
function view.RefreshInstruction(hint)
    local model=planner.Controller.Get()
    if inline and inline:IsShown() then instruction(inline,model,hint) end
    local window=view.Window
    if window and window:IsShown() then instruction(window.summary,model,hint) end
end
local function destinationFloor(frame)
    local floors=planner.Terrain and planner.Terrain.Floors and planner.Terrain.Floors()
    local available=floors and #floors.choices>1
    frame.floor:SetShown(available==true)
    frame.arrowHint:SetShown(frame.expanded or not available)
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
    frame.title:SetText(frame.expanded and model.selected and model.selected.title or title)
    frame.detail:SetText(model.selected and model.selected.detail or model.detail)
    instruction(frame,model,planner.Navigation and planner.Navigation.Instruction and planner.Navigation.Instruction())
    frame.pause.label:SetText(planner.Controller.Policy().paused and "Resume" or "Pause")
    if frame.pin then frame.pin.label:SetText(model.selected and planner.Controller.Policy().pins[model.selected.questID] and "Unpin" or "Pin") end
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
    local make=frame.expanded and view.WindowUI.Button or button
    frame.floor=make(frame,"Floor: Auto",124,chooseFloor)
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
        button(frame,"Skip",40,function() selectedCommand("skip") end),button(frame,"More",44,function() if view.Open then view.Open() end end)}
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

view.Command,view.RefreshSummary,view.SummaryTooltip,view.AddFloorControl=command,details,tooltip,floorControl
function view.Refresh()
    if planner.PlanControls then planner.PlanControls.Refresh() end
    if inline then details(inline,planner.Controller.Get()) end
    if view.RefreshWindow then view.RefreshWindow() end
end
