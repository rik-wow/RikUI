-- Lifecycle and optional character-window entry. Native equipment clicks remain untouched.
local core,g=RikUI,RikUI.GearGoals
local module={title="Gear goals"};g.Module=module
local slotGlobals={[1]="CharacterHeadSlot",[2]="CharacterNeckSlot",[3]="CharacterShoulderSlot",
    [15]="CharacterBackSlot",[5]="CharacterChestSlot",[9]="CharacterWristSlot",[10]="CharacterHandsSlot",
    [6]="CharacterWaistSlot",[7]="CharacterLegsSlot",[8]="CharacterFeetSlot",[11]="CharacterFinger0Slot",
    [12]="CharacterFinger1Slot",[13]="CharacterTrinket0Slot",[14]="CharacterTrinket1Slot",
    [16]="CharacterMainHandSlot",[17]="CharacterSecondaryHandSlot",[18]="CharacterRangedSlot"}
local pending=false
function g.AttachCharacter()
    local host=CharacterFrame
    if not host or not host.HookScript or InCombatLockdown() then return end
    local view=g.View
    if not view.CharacterEntry then
        local entry=core.Shell.Button(host,"Gear goals",function()view.Show()end)
        entry:SetSize(120,26);entry:SetPoint("BOTTOMLEFT",host,"TOPLEFT",20,4)
        entry.label:SetJustifyH("CENTER");core.Media.Font(entry.label,"small")
        view.CharacterEntry=entry
        core.Hooks.Script(host,"OnHide",function()
            if view.Badges then for _,b in pairs(view.Badges)do b:Hide()end end
        end)
    end
    view.Badges=view.Badges or {}
    for slot,name in pairs(slotGlobals)do
        local parent=_G[name]
        if parent and parent.HookScript and not view.Badges[slot] then
            local b=core.Shell.Button(parent,"",function()view.Show(slot)end)
            b:SetSize(18,18);b:SetPoint("BOTTOMRIGHT",2,-2)
            b:SetFrameLevel(parent:GetFrameLevel()+5)
            local icon=core.Media.Icon(b,"star",12,"OVERLAY");icon:SetPoint("CENTER");icon:SetVertexColor(unpack(core.Skin.GOLD))
            b:SetScript("OnEnter",function()
                if GameTooltip then GameTooltip:SetOwner(b,"ANCHOR_RIGHT");GameTooltip:AddLine("Gear goal: "..g.SlotNames[slot]);GameTooltip:AddLine("Compare sources for this slot",.7,.8,.9);GameTooltip:Show()end
            end)
            b:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
            b:Hide();view.Badges[slot]=b
        end
    end
end
function g.RefreshTracker()
    local focused=g.Focused()
    local show=g.Tracking() and focused and not focused.seen
    if not show then if g.Tracker then g.Tracker:Hide()end;return end
    if not g.Tracker then
        if InCombatLockdown() then return end
        local frame=core.Shell.Button(UIParent,"",nil);g.Tracker=frame
        frame:SetSize(270,74);frame:SetFrameStrata("MEDIUM")
        frame.label:Hide();core.Skin.WindowChrome(frame,0,0)
        frame.icon=frame:CreateTexture(nil,"ARTWORK");frame.icon:SetSize(34,34);frame.icon:SetPoint("TOPLEFT",10,-10);core.Skin.CropIcon(frame.icon,.06)
        frame.title=core.Shell.Text(frame,"","label");frame.title:SetSize(205,28);frame.title:SetPoint("TOPLEFT",54,-8);frame.title:SetWordWrap(true)
        frame.detail=core.Shell.Text(frame,"","small");frame.detail:SetSize(246,32);frame.detail:SetPoint("TOPLEFT",12,-38);frame.detail:SetWordWrap(true)
        frame.detail:SetTextColor(.7,.78,.86)
        frame:SetScript("OnClick",function()local row=g.Focused();if row then g.View.Show(row.slot);g.View.SelectItem(row.itemID,row.source)end end)
        core.Layout.Register(frame,"geargoals",{point="TOPLEFT",relativePoint="TOPLEFT",x=24,y=-140},{label="Gear goal",grow="DOWN"})
    end
    local frame=g.Tracker;local item=g.Item(focused.itemID);local src=item and focused.source and item.sources[focused.source]
    local meta=g.Meta(focused.itemID,true)
    frame.title:SetText(meta and meta.name or item and item.name or "Gear goal")
    frame.title:SetTextColor(unpack(core.Skin.GOLD));frame.icon:SetTexture(meta and meta.icon or item and item.icon)
    local detail=src and src.kind=="dungeon" and ((src.dungeon or "Dungeon").." · "..(src.name or "Encounter").." · reference")
        or src and src.name or "Source unknown"
    if src and src.kind=="quest" then
        local path=g.Path(src.id,focused.branch)
        if path.issue then detail=path.issue
        elseif #path.choices>0 then detail="Choose a prerequisite branch in Gear goals"
        else for _,q in ipairs(path.rows)do if q.state~="complete" then detail=q.name.." · "..q.state;break end end end
    end
    frame.detail:SetText(detail)
    local titleHeight=math.max(28,(frame.title:GetStringHeight() or 0)+4)
    frame.title:SetHeight(titleHeight)
    frame.detail:ClearAllPoints();frame.detail:SetPoint("TOPLEFT",12,-math.max(38,titleHeight+16))
    local detailHeight=math.max(32,(frame.detail:GetStringHeight() or 0)+4)
    frame.detail:SetHeight(detailHeight);frame:SetHeight(math.max(74,titleHeight+detailHeight+26));frame:Show()
end
local function refresh()
    pending=false
    if not module.enabled then return end
    g.Observe()
    if g.View.mode=="goals" then g.View.Query()end
    g.View.Refresh()
end
local function request(event,...)
    if event=="ADDON_LOADED" or event=="PLAYER_REGEN_ENABLED" then
        g.AttachCharacter();if g.Provider then g.Provider.RetryAfterLoad()end
    end
    if event=="GET_ITEM_INFO_RECEIVED" then
        local id=...
        if not core.Secret.IsSecret(id) and type(id)=="number" then g.InvalidateItem(id)end
    end
    if pending then return end
    pending=true
    if C_Timer and C_Timer.After then C_Timer.After(.15,refresh)else refresh()end
end
function module:OnEnable()
    local ok,reason=g.Restore();if not ok then core:Print(reason.."; gear goals reset for this session.")end
    core:RegisterCommand("gear",function()g.View.Show()end,"Compare equipment sources and track per-character gear goals")
    core.Shell.Register("geargoals",{group="Tools",label="Gear goals",order=25,action=function()g.View.Show()end})
    for _,event in ipairs({"ADDON_LOADED","PLAYER_REGEN_ENABLED","BAG_UPDATE_DELAYED","PLAYER_EQUIPMENT_CHANGED",
        "GET_ITEM_INFO_RECEIVED","QUEST_LOG_UPDATE","QUEST_TURNED_IN","PLAYER_LEVEL_UP","PLAYER_ENTERING_WORLD"})do core:RegisterEvent(event,request)end
    local worker=CreateFrame("Frame");local elapsed=0
    worker:SetScript("OnUpdate",function(_,delta)
        if g.Provider and g.Provider.Step() then g.View.Query();g.View.Refresh() end
        elapsed=elapsed+delta
        if elapsed<.1 then return end;elapsed=0
        if g.Provider and g.Provider.Progress() and g.View.Window and g.View.Window:IsShown() then
            g.View.Window.status:SetText("Preparing source references: "..math.floor(g.Provider.Progress()*100).."%")
        end
        g.LoadStep()
    end)
    g.AttachCharacter();request()
end
core:RegisterModule("geargoals",module)
