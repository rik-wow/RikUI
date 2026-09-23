-- Addon-owned destination markers; no synthetic straight-line walking route.
local core,planner,media=RikUI,RikUI.QuestPlanner,RikUI.Media
local navigation={}
planner.Navigation=navigation
local pins,frame,arrow,elapsed={},nil,nil,0
local bearingElapsed=0
local lastText,textAge,rotation,rotationTime=nil,0,nil,nil
local function playerFrame()
    if planner.Context.Frame then return planner.Context.Frame() end
    local position=planner.Context.Position()
    local _,facing=planner.Context.Call(GetPlayerFacing)
    local _,width,height=planner.Context.Call(C_Map and C_Map.GetMapWorldSize,position and position.mapID)
    return {position=position,facing=facing,width=width,height=height}
end
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
local function routeCount(route)
    local path=route and route.path
    return path and #path.prefix+#path.tail-path.first+1 or route and route.points and #route.points or 0
end
local function routePoint(route,at)
    local path=route.path
    if not path then return route.points[at] end
    return at<=#path.prefix and path.prefix[at] or path.tail[at-#path.prefix+path.first-1]
end
local function routeView(route,mapID)
    local source=route.mapView
    if not source then return end
    if source.uiMapID==mapID then return source end
    return planner.Roads and planner.Roads.View(route.worldMapID,mapID)
end
local function mapPoint(route,point,mapID,target)
    local source=route.mapView
    local low,high=source and -100000 or 0,source and 100000 or 1
    if not point or not planner.Schema.Number(point.x,low,high)
        or not planner.Schema.Number(point.y,low,high) then return end
    if not source then if point.mapID==mapID then return point end;return end
    if point.mapID~=source.uiMapID or not target then return end
    if target==source then return point end
    local p=source.projection
    local x,z=p.originY-point.x*p.width,p.originX-point.y*p.height
    if not planner.Schema.Number(x,-100000,100000) or not planner.Schema.Number(z,-100000,100000) then return end
    return planner.Roads.Unproject(target,{x=x,z=z})
end
local function routePoints(route,mapID,project)
    local points,target={},routeView(route,mapID)
    local count=routeCount(route)
    if count>MAX_ROUTE_LINES+1 then return nil end
    for at=1,count do
        local point=mapPoint(route,routePoint(route,at),mapID,target)
        if not point then return nil end
        points[#points+1]=project(point)
    end
    return points
end
local worldCaches={}
-- Immutable route tails are projected only when their geometry or map viewport changes.
local function worldPoints(route,mapID,width,height,inverted)
    local target=routeView(route,mapID)
    local function project(point)
        local p=mapPoint(route,point,mapID,target)
        if p then return {p.x*width,p.y*height*(inverted and -1 or 1)} end
    end
    local path=route.path
    if not path then return routePoints(route,mapID,function(p)return {p.x*width,p.y*height*(inverted and -1 or 1)}end) end
    if routeCount(route)>MAX_ROUTE_LINES+1 then return nil end
    local key=inverted and "lines" or "ants"
    local cache=worldCaches[key]
    if not cache or cache.tail~=path.tail or cache.mapID~=mapID or cache.width~=width or cache.height~=height
        or cache.source~=route.mapView or cache.target~=target then
        cache={tail=path.tail,mapID=mapID,width=width,height=height,source=route.mapView,target=target,points={},projected={}}
        for at,point in ipairs(path.tail) do
            cache.projected[at]=project(point)
            if not cache.projected[at] then return nil end
        end
        worldCaches[key]=cache
    end
    if cache.prefix==path.prefix and cache.first==path.first then return cache.points end
    local at=0
    for _,point in ipairs(path.prefix) do
        at=at+1
        cache.points[at]=project(point)
        if not cache.points[at] then return nil end
    end
    for index=path.first,#path.tail do at=at+1;cache.points[at]=cache.projected[index] end
    for index=#cache.points,at+1,-1 do cache.points[index]=nil end
    cache.prefix,cache.first=path.prefix,path.first
    return cache.points
end
local function minimapAnts(route)
    if not Minimap or not Minimap:IsShown() then return end
    local live=playerFrame()
    local position=live.position
    local ok,radius=planner.Context.Call(C_Minimap and C_Minimap.GetViewRadius)
    if not ok or not planner.Schema.Number(radius,1,100000) or not position then return end
    local mw,mh=live.width,live.height
    local sized=mw and mh
    local readable,rotates=planner.Context.Call(GetCVarBool,"rotateMinimap")
    if not sized or not planner.Schema.Number(mw,1,100000) or not planner.Schema.Number(mh,1,100000)
        or not readable or type(rotates)~="boolean" then return end
    local ignored,ignore=planner.Context.Call(C_Minimap and C_Minimap.IsRotateMinimapIgnored)
    if ignored and ignore==true then rotates=false end
    local rotation=0
    if rotates then
        local facing=live.facing
        local faced=facing~=nil
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
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    if model.status=="paused" or model.status=="updating" or not model.selected then return end
    local route=planner.Terrain and (planner.Terrain.PeekGuidance or planner.Terrain.Guidance)()
    if routeCount(route)<2 then return end
    if frame and frame:IsShown() then
        local canvas,mapID=frame:GetCanvas(),frame:GetMapID()
        local w,h=canvas:GetWidth(),canvas:GetHeight()
        if planner.Schema.Number(w,8,20000) and planner.Schema.Number(h,8,20000) then
            local points=worldPoints(route,mapID,w,h,false)
            if points then paintAnts(antPools.world,canvas,points,w,h,256,false) end
        end
    end
    minimapAnts(route)
end
function navigation.Instruction(live)
    if not planner.enabled then return nil end
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    if model.status=="paused" or model.status=="updating" or not model.selected then return nil end
    if model.selected.journey and planner.JourneyLive and model.selected.journey.mode~="walk" then
        return planner.JourneyLive.Instruction(model.selected.journey)
    end
    local route=planner.Terrain and (planner.Terrain.PeekGuidance or planner.Terrain.Guidance)()
    live=live or playerFrame()
    if not route or not live.position or not live.width then return nil end
    local mapID=live.position.mapID
    local point=mapPoint(route,route.next,mapID,routeView(route,mapID))
    if not point and not route.searching then return nil end
    return planner.Guidance.Instruction(route,live.position,live.facing,live.width,live.height,point)
end
local function hideLines() for _,line in ipairs(lines) do line:Hide() end end
local function drawTerrain(canvas,width,height,mapID)
    if not planner.Terrain then return end
    local route=(planner.Terrain.PeekGuidance or planner.Terrain.Guidance)()
    if routeCount(route)<2 then return end
    local points=worldPoints(route,mapID,width,height,true)
    if not points then return end
    if not lineHolder then
        lineHolder=CreateFrame("Frame",nil,canvas); lineHolder:SetAllPoints(canvas)
    elseif lineHolder:GetParent()~=canvas then
        if InCombatLockdown() then return end
        lineHolder:SetParent(canvas); lineHolder:SetAllPoints(canvas)
    end
    if type(lineHolder.CreateLine)~="function" then return end
    for index=1,math.min(routeCount(route)-1,MAX_ROUTE_LINES,#lines+NEW_LINES_PER_REFRESH) do
        local a,b=points[index],points[index+1]
        local line=lines[index]
        if not line then
            line=lineHolder:CreateLine(nil,"OVERLAY")
            if not line then return end
            line:SetThickness(2); line:SetColorTexture(1,.7,.2,.8); lines[index]=line
        end
        local key=string.format("%.3f:%.3f:%.3f:%.3f",a[1],a[2],b[1],b[2])
        if line.routeKey~=key then
            line:SetStartPoint("TOPLEFT",canvas,a[1],a[2])
            line:SetEndPoint("TOPLEFT",canvas,b[1],b[2]);line.routeKey=key
        end
        line:Show()
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
        GameTooltip:AddLine(pin.hunt and "Search approach; look for targets nearby. Click to open the quest."
            or "Destination marker; follow verified paths. Click to open the quest.",1,1,1,true); GameTooltip:Show()
    end)
    pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    pin:SetScript("OnClick",function() if pin.questID then planner.OpenQuest(pin.questID) end end)
    return pin
end
local function draw()
    hidePins()
    if not frame or not frame:IsShown() or not planner.enabled then return end
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    if model.status=="paused" or not model.selected then return end
    local canvas=frame:GetCanvas()
    local mapID,width,height=frame:GetMapID(),canvas:GetWidth(),canvas:GetHeight()
    if not planner.Schema.ID(mapID) or not planner.Schema.Number(width,1,20000) or not planner.Schema.Number(height,1,20000) then return end
    drawTerrain(canvas,width,height,mapID)
    local terrain=planner.Terrain and (planner.Terrain.PeekGuidance or planner.Terrain.Guidance)()
    local count=0
    for _,row in ipairs(model.stops or {model.selected}) do
        local point=row.destination
        if row.questID==model.selected.questID and terrain and terrain.huntEndpoint then point=terrain.huntEndpoint end
        if point and point.mapID==mapID and planner.Schema.Number(point.x,0,1) and planner.Schema.Number(point.y,0,1) then
            count=count+1; if count>8 then break end
            local pin=pins[count] or marker(canvas,count); pins[count]=pin
            if pin:GetParent()~=canvas then pin:SetParent(canvas) end
            pin:ClearAllPoints(); pin:SetPoint("CENTER",canvas,"TOPLEFT",point.x*width,-point.y*height)
            pin.title,pin.questID,pin.hunt=row.title,row.questID,row.hunt~=nil
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
    arrow.label:SetText("")
    arrow:Hide()
end
local function bearing()
    if not arrow then return end
    arrow:Hide()
    if not planner.enabled or not (planner.Controller.ArrowEnabled and planner.Controller.ArrowEnabled()
        or not planner.Controller.ArrowEnabled and planner.Controller.Policy().arrow) then return end
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    if model.status=="paused" or not model.selected then return end
    if model.selected.suppressSteering then
        local instruction=navigation.Instruction()
        if instruction then arrow.label:SetText(instruction.text.."\n"..instruction.subtext);arrow.icon:Hide();arrow:Show() end
        return
    end
    if not model.selected.destination then return end
    local terrain=planner.Terrain and (planner.Terrain.PeekGuidance or planner.Terrain.Guidance)()
    local live=playerFrame()
    local point,position=terrain and terrain.next or model.selected.destination,live.position
    if terrain and position then point=mapPoint(terrain,point,position.mapID,routeView(terrain,position.mapID)) end
    local hint=navigation.Instruction(live)
    if not point or not position or position.mapID~=point.mapID then return end
    local facing,width,height=live.facing,live.width,live.height
    local ok,sized=facing~=nil,width and height
    if not ok or not sized or not planner.Schema.Number(facing,0,math.pi*2)
        or not planner.Schema.Number(width,1,100000) or not planner.Schema.Number(height,1,100000) or not math.atan2 then return end
    hint=hint or planner.Guidance.MarkerInstruction(point,position,width,height,
        planner.Terrain and planner.Terrain.Status())
    if not hint then return end
    local label=hint.text.."\n"..hint.subtext
    if label~=lastText and (textAge>=BEARING_INTERVAL or not lastText or hint.ending) then
        arrow.label:SetText(label);lastText=label;textAge=0
    end
    local dx,dy=(point.x-position.x)*width,(point.y-position.y)*height
    if hint and hint.ending then arrow.icon:Hide();arrow:Show();return end
    arrow.icon:Show()
    if math.abs(dx)+math.abs(dy)<1 then return end
    local desired=math.atan2(-dx,-dy)
    local delta=live.time and rotationTime and math.max(0,live.time-rotationTime) or .05
    if rotation then
        local difference=(desired-rotation+math.pi)%(math.pi*2)-math.pi
        rotation=rotation+difference*(1-math.exp(-delta/.08))
    else rotation=desired end
    rotationTime=live.time
    -- Smooth the world bearing; camera rotation remains immediate.
    arrow.icon:SetRotation(rotation-facing)
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
    textAge=BEARING_INTERVAL
    if planner.Context.Frame then planner.Context.Frame(true) end
    local ok,reason=pcall(draw)
    if not ok then hidePins(); navigation.lastError=tostring(reason) end
    refreshBearing();refreshRouteDisplay()
end
function navigation.Start()
    core.Combat.Queue(function()
        if not arrow then arrowBuild() end
        local driver=CreateFrame("Frame")
        driver:SetScript("OnUpdate",function(_,delta)
            textAge=textAge+delta
            antPhase=(antPhase+delta*20)%14
            elapsed=elapsed+delta; bearingElapsed=bearingElapsed+delta
            if elapsed>=MAP_INTERVAL then
                elapsed=elapsed%MAP_INTERVAL; bearingElapsed=0
                frame=WorldMapFrame
                navigation.Refresh()
            else
                refreshBearing()
                if bearingElapsed>=BEARING_INTERVAL then
                    bearingElapsed=bearingElapsed%BEARING_INTERVAL
                    refreshRouteDisplay()
                end
            end
        end)
    end,"questplanner:navigation")
end
function navigation.Open()
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    if model.selected then planner.OpenQuest(model.selected.questID) end
end
