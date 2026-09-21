-- Addon-owned destination markers; no synthetic straight-line walking route.
local core,planner,media=RikUI,RikUI.QuestPlanner,RikUI.Media
local navigation={}
planner.Navigation=navigation
local pins,frame,arrow,elapsed={},nil,nil,0
local bearingElapsed=0
local MAP_INTERVAL, BEARING_INTERVAL = .2, .05
local lines,lineHolder={},nil
local MAX_ROUTE_LINES,NEW_LINES_PER_REFRESH=2048,32
local antPools={world={dots={}},mini={dots={}}}
local antPhase=0
local function hideAnts(pool) for _,dot in ipairs(pool.dots) do dot:Hide() end end
local function antHolder(pool,parent)
    if not pool.holder then
        pool.holder=CreateFrame("Frame",nil,parent);pool.holder:SetAllPoints(parent)
        pool.holder:EnableMouse(false)
    elseif pool.holder:GetParent()~=parent then
        if InCombatLockdown() then return nil end
        pool.holder:SetParent(parent);pool.holder:SetAllPoints(parent)
    end
    return pool.holder
end
local function paintAnts(pool,parent,points,width,height,limit,round)
    local holder=antHolder(pool,parent)
    if not holder then return end
    local samples=planner.NavGeometry.ScreenAnts(points,width,height,antPhase,limit,round)
    for at=1,math.min(#samples,#pool.dots+16) do
        local dot=pool.dots[at]
        if not dot then
            dot=holder:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4)
            dot:SetColorTexture(1,.9,.35,1);pool.dots[at]=dot
        end
        dot:ClearAllPoints();dot:SetPoint("CENTER",holder,"TOPLEFT",samples[at][1],-samples[at][2]);dot:Show()
    end
end
local function routePoints(route,mapID,project)
    local points={}
    for at=1,math.min(#route.points,2049) do
        local point=route.points[at]
        if point.mapID~=mapID or not planner.Schema.Number(point.x,0,1)
            or not planner.Schema.Number(point.y,0,1) then return nil end
        points[#points+1]=project(point)
    end
    return points
end
local function minimapAnts(route)
    if not Minimap or not Minimap:IsShown() then return end
    local position=planner.Context.Position()
    local ok,radius=planner.Context.Call(C_Minimap and C_Minimap.GetViewRadius)
    if not ok or not planner.Schema.Number(radius,1,100000) or not position then return end
    local sized,mw,mh=planner.Context.Call(C_Map and C_Map.GetMapWorldSize,position.mapID)
    local readable,rotates=planner.Context.Call(GetCVarBool,"rotateMinimap")
    if not sized or not planner.Schema.Number(mw,1,100000) or not planner.Schema.Number(mh,1,100000)
        or not readable or type(rotates)~="boolean" then return end
    local ignored,ignore=planner.Context.Call(C_Minimap and C_Minimap.IsRotateMinimapIgnored)
    if ignored and ignore==true then rotates=false end
    local rotation=0
    if rotates then
        local faced,facing=planner.Context.Call(GetPlayerFacing)
        if not faced or not planner.Schema.Number(facing,0,math.pi*2) then return end
        rotation=facing
    end
    local w,h=Minimap:GetWidth(),Minimap:GetHeight()
    if not planner.Schema.Number(w,8,20000) or not planner.Schema.Number(h,8,20000) then return end
    local points=routePoints(route,position.mapID,function(point)
        return planner.NavGeometry.MinimapPoint(point,position,mw,mh,w,h,radius,rotation)
    end)
    local square=core.Minimap and core.Minimap.Holder and Minimap:GetParent()==core.Minimap.Holder
    if points then paintAnts(antPools.mini,Minimap,points,w,h,96,not square) end
end
local function drawAnts()
    hideAnts(antPools.world);hideAnts(antPools.mini)
    if not planner.enabled then return end
    local model=planner.Controller.Get()
    if model.status=="paused" or model.status=="updating" or not model.selected then return end
    local route=planner.Terrain and planner.Terrain.Guidance()
    if not route or not route.points or #route.points<2 then return end
    if frame and frame:IsShown() then
        local canvas,mapID=frame:GetCanvas(),frame:GetMapID()
        local w,h=canvas:GetWidth(),canvas:GetHeight()
        if planner.Schema.Number(w,8,20000) and planner.Schema.Number(h,8,20000) then
            local points=routePoints(route,mapID,function(point) return {point.x*w,point.y*h} end)
            if points then paintAnts(antPools.world,canvas,points,w,h,256,false) end
        end
    end
    minimapAnts(route)
end
function navigation.Instruction()
    if not planner.enabled then return nil end
    local model=planner.Controller.Get()
    if model.status=="paused" or model.status=="updating" or not model.selected then return nil end
    local route=planner.Terrain and planner.Terrain.Guidance()
    local position=planner.Context.Position()
    if not route or not position then return nil end
    local sized,w,h=planner.Context.Call(C_Map and C_Map.GetMapWorldSize,position.mapID)
    local _,facing=planner.Context.Call(GetPlayerFacing)
    if not sized then return nil end
    return planner.Guidance.Instruction(route,position,facing,w,h)
end
local function hideLines() for _,line in ipairs(lines) do line:Hide() end end
local function drawTerrain(canvas,width,height,mapID)
    if not planner.Terrain then return end
    local route=planner.Terrain.Guidance()
    if not route or not route.points or #route.points<2 or route.points[1].mapID~=mapID then return end
    if not lineHolder then
        lineHolder=CreateFrame("Frame",nil,canvas); lineHolder:SetAllPoints(canvas)
    elseif lineHolder:GetParent()~=canvas then
        if InCombatLockdown() then return end
        lineHolder:SetParent(canvas); lineHolder:SetAllPoints(canvas)
    end
    if type(lineHolder.CreateLine)~="function" then return end
    for index=1,math.min(#route.points-1,MAX_ROUTE_LINES,#lines+NEW_LINES_PER_REFRESH) do
        local a,b=route.points[index],route.points[index+1]
        local line=lines[index]
        if not line then
            line=lineHolder:CreateLine(nil,"OVERLAY")
            if not line then return end
            line:SetThickness(2); line:SetColorTexture(1,.7,.2,.8); lines[index]=line
        end
        line:SetStartPoint("TOPLEFT",canvas,a.x*width,-a.y*height)
        line:SetEndPoint("TOPLEFT",canvas,b.x*width,-b.y*height); line:Show()
    end
end
local function hidePins() hideLines(); for _,pin in ipairs(pins) do pin:Hide() end end
local function marker(canvas,index)
    local pin=CreateFrame("Button",nil,canvas)
    pin:SetSize(20,20)
    pin.icon=media.Icon(pin,"diamond",20); pin.icon:SetAllPoints(); pin.icon:SetVertexColor(.2,.8,1)
    pin.label=pin:CreateFontString(nil,"OVERLAY"); media.Font(pin.label,"small"); pin.label:SetPoint("CENTER")
    pin.label:SetText(tostring(index))
    pin:SetScript("OnEnter",function()
        GameTooltip:SetOwner(pin,"ANCHOR_RIGHT"); GameTooltip:SetText(pin.title or "Quest destination")
        GameTooltip:AddLine("Destination marker; follow verified paths. Click to open the quest.",1,1,1,true); GameTooltip:Show()
    end)
    pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    pin:SetScript("OnClick",function() if pin.questID then planner.OpenQuest(pin.questID) end end)
    return pin
end
local function draw()
    hidePins()
    if not frame or not frame:IsShown() or not planner.enabled then return end
    local model=planner.Controller.Get()
    if model.status=="paused" or not model.selected then return end
    local canvas=frame:GetCanvas()
    local mapID,width,height=frame:GetMapID(),canvas:GetWidth(),canvas:GetHeight()
    if not planner.Schema.ID(mapID) or not planner.Schema.Number(width,1,20000) or not planner.Schema.Number(height,1,20000) then return end
    drawTerrain(canvas,width,height,mapID)
    local count=0
    for _,row in ipairs(model.stops or {model.selected}) do
        local point=row.destination
        if point and point.mapID==mapID and planner.Schema.Number(point.x,0,1) and planner.Schema.Number(point.y,0,1) then
            count=count+1; if count>8 then break end
            local pin=pins[count] or marker(canvas,count); pins[count]=pin
            if pin:GetParent()~=canvas then pin:SetParent(canvas) end
            pin:ClearAllPoints(); pin:SetPoint("CENTER",canvas,"TOPLEFT",point.x*width,-point.y*height)
            pin.title,pin.questID=row.title,row.questID
            pin:Show()
        end
    end
end
local function arrowBuild()
    arrow=CreateFrame("Frame",nil,UIParent)
    arrow:SetSize(240,66); arrow:SetPoint("TOP",UIParent,"TOP",0,-110)
    arrow.icon=media.Icon(arrow,"chevron-up",26); arrow.icon:SetPoint("TOP",0,0)
    arrow.label=arrow:CreateFontString(nil,"OVERLAY"); media.Font(arrow.label,"small"); arrow.label:SetPoint("BOTTOM")
    arrow.label:SetWidth(240);arrow.label:SetHeight(32);arrow.label:SetWordWrap(true)
    arrow.label:SetText("Destination bearing")
    arrow:Hide()
end
local function bearing()
    if not arrow then return end
    arrow:Hide()
    if not planner.enabled or not planner.Controller.Policy().arrow then return end
    local model=planner.Controller.Get()
    if model.status=="paused" or not model.selected or not model.selected.destination then return end
    local terrain=planner.Terrain and planner.Terrain.Guidance()
    local point,position=terrain and terrain.next or model.selected.destination,planner.Context.Position()
    local hint=navigation.Instruction()
    arrow.label:SetText(hint and (hint.text.."\n"..hint.subtext) or "Destination bearing")
    if not position or position.mapID~=point.mapID then return end
    local ok,facing=planner.Context.Call(GetPlayerFacing)
    local sized,width,height=planner.Context.Call(C_Map and C_Map.GetMapWorldSize,point.mapID)
    if not ok or not sized or not planner.Schema.Number(facing,0,math.pi*2)
        or not planner.Schema.Number(width,1,100000) or not planner.Schema.Number(height,1,100000) or not math.atan2 then return end
    local dx,dy=(point.x-position.x)*width,(point.y-position.y)*height
    if hint and hint.ending then arrow.icon:Hide();arrow:Show();return end
    arrow.icon:Show()
    if math.abs(dx)+math.abs(dy)<1 then return end
    arrow.icon:SetRotation(math.atan2(-dx,-dy)-facing)
    arrow:Show()
end
local function refreshBearing()
    local readable,failure=pcall(bearing)
    if not readable then if arrow then arrow:Hide() end; navigation.lastError=tostring(failure) end
end
local function refreshRouteDisplay()
    local ok,reason=pcall(drawAnts)
    if not ok then hideAnts(antPools.world);hideAnts(antPools.mini);navigation.lastError=tostring(reason) end
    if planner.View and planner.View.RefreshInstruction then planner.View.RefreshInstruction(navigation.Instruction()) end
end
function navigation.Refresh()
    local ok,reason=pcall(draw)
    if not ok then hidePins(); navigation.lastError=tostring(reason) end
    refreshBearing();refreshRouteDisplay()
end
function navigation.Start()
    core.Combat.Queue(function()
        if not arrow then arrowBuild() end
        local driver=CreateFrame("Frame")
        driver:SetScript("OnUpdate",function(_,delta)
            antPhase=(antPhase+delta*20)%14
            elapsed=elapsed+delta; bearingElapsed=bearingElapsed+delta
            if elapsed>=MAP_INTERVAL then
                elapsed=elapsed%MAP_INTERVAL; bearingElapsed=0
                frame=WorldMapFrame
                navigation.Refresh()
            elseif bearingElapsed>=BEARING_INTERVAL then
                bearingElapsed=bearingElapsed%BEARING_INTERVAL
                refreshBearing();refreshRouteDisplay()
            end
        end)
    end,"questplanner:navigation")
end
function navigation.Open()
    local model=planner.Controller.Get()
    if model.selected then planner.OpenQuest(model.selected.questID) end
end
