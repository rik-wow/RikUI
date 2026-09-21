-- Addon-owned destination markers; no synthetic straight-line walking route.
local core,planner,media=RikUI,RikUI.QuestPlanner,RikUI.Media
local navigation={}
planner.Navigation=navigation
local pins,frame,arrow,elapsed={},nil,nil,0
local function hidePins() for _,pin in ipairs(pins) do pin:Hide() end end
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
    arrow:SetSize(170,48); arrow:SetPoint("TOP",UIParent,"TOP",0,-110)
    arrow.icon=media.Icon(arrow,"chevron-up",26); arrow.icon:SetPoint("TOP",0,0)
    arrow.label=arrow:CreateFontString(nil,"OVERLAY"); media.Font(arrow.label,"small"); arrow.label:SetPoint("BOTTOM")
    arrow.label:SetText("Destination bearing")
    arrow:Hide()
end
local function bearing()
    if not arrow then return end
    arrow:Hide()
    if not planner.enabled or not planner.Controller.Policy().arrow then return end
    local model=planner.Controller.Get()
    if model.status=="paused" or not model.selected or not model.selected.destination then return end
    local point,position=model.selected.destination,planner.Context.Position()
    if not position or position.mapID~=point.mapID then return end
    local ok,facing=planner.Context.Call(GetPlayerFacing)
    local sized,width,height=planner.Context.Call(C_Map and C_Map.GetMapWorldSize,point.mapID)
    if not ok or not sized or not planner.Schema.Number(facing,0,math.pi*2)
        or not planner.Schema.Number(width,1,100000) or not planner.Schema.Number(height,1,100000) or not math.atan2 then return end
    local dx,dy=(point.x-position.x)*width,(point.y-position.y)*height
    if math.abs(dx)+math.abs(dy)<1 then return end
    arrow.icon:SetRotation(math.atan2(-dx,-dy)-facing)
    arrow:Show()
end
function navigation.Refresh()
    local ok,reason=pcall(draw)
    if not ok then hidePins(); navigation.lastError=tostring(reason) end
    local readable,failure=pcall(bearing)
    if not readable then if arrow then arrow:Hide() end; navigation.lastError=tostring(failure) end
end
function navigation.Start()
    core.Combat.Queue(function()
        if not arrow then arrowBuild() end
        local driver=CreateFrame("Frame")
        driver:SetScript("OnUpdate",function(_,delta)
            elapsed=elapsed+delta
            if elapsed<.2 then return end; elapsed=0
            frame=WorldMapFrame
            if planner.Controller.Policy().arrow or (frame and frame:IsShown()) then navigation.Refresh()
            else hidePins(); arrow:Hide() end
        end)
    end,"questplanner:navigation")
end
function navigation.Open()
    local model=planner.Controller.Get()
    if model.selected then planner.OpenQuest(model.selected.questID) end
end
