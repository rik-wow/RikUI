-- Explicit clipboard transfer window. Pasted observations stay quarantined.
local core,planner,media=RikUI,RikUI.QuestPlanner,RikUI.Media
local transferView={}
planner.TransferView=transferView
local window
local function close()
    if window then window.edit:ClearFocus(); window:Hide() end
end
local function build()
    window=CreateFrame("Frame","RikUIQuestTransfer",UIParent)
    window:SetSize(560,320); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:EnableMouse(true)
    local fill=window:CreateTexture(nil,"BACKGROUND"); fill:SetAllPoints(); fill:SetColorTexture(.04,.05,.07,.98)
    window.title=window:CreateFontString(nil,"OVERLAY"); media.Font(window.title,"label"); window.title:SetPoint("TOPLEFT",12,-12)
    local scroll=CreateFrame("ScrollFrame",nil,window)
    scroll:SetPoint("TOPLEFT",12,-44); scroll:SetPoint("BOTTOMRIGHT",-12,38); scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*30)))
    end)
    window.edit=CreateFrame("EditBox",nil,scroll)
    window.edit:SetMultiLine(true); window.edit:SetAutoFocus(false); window.edit:SetWidth(520)
    window.edit:SetFont(media.font,media.sizes.small,""); window.edit:SetMaxLetters(131072)
    window.edit:SetScript("OnEscapePressed",close); scroll:SetScrollChild(window.edit)
    window.edit:SetScript("OnTextChanged",function(self)
        if not window.inspect then return end
        local raw=self:GetText() or ""
        if raw:sub(1,6)=="RIKP1:" then
            local trace,reason=planner.Transfer.DecodePlan(raw)
            window.title:SetText(trace and ("Imported "..trace.flavor.." plan; inspection only") or reason)
            return
        end
        local value,reason=planner.Transfer.Decode(raw)
        window.title:SetText(value and ("Imported "..value.identity.build..": "..value.observedCount.." log quests; inspection only")
            or reason or "Paste observations to inspect")
    end)
    local exit=CreateFrame("Button",nil,window); exit:SetSize(72,24); exit:SetPoint("BOTTOMRIGHT",-12,8)
    exit:SetHighlightTexture(media.highlight)
    local label=exit:CreateFontString(nil,"OVERLAY"); media.Font(label,"small"); label:SetPoint("CENTER"); label:SetText("Close")
    exit:SetScript("OnClick",close)
    window.hint=window:CreateFontString(nil,"OVERLAY"); media.Font(window.hint,"small"); window.hint:SetPoint("BOTTOMLEFT",12,12)
    window.hint:SetText("Ctrl+A, Ctrl+C to copy. No automatic disk or settings storage.")
    if type(UISpecialFrames)=="table" then table.insert(UISpecialFrames,"RikUIQuestTransfer") end
    transferView.Window=window
end
function transferView.OpenPlan()
    local trace=planner.PlanRuntime and planner.PlanRuntime.Replay()
    local wire,reason=planner.Transfer.EncodePlan(trace)
    if not wire then return core:Print(reason) end
    core.Combat.Queue(function()
        if not window then build() end
        window.inspect=false;window.edit:SetMaxLetters(1048576)
        window.title:SetText("Copy plan evidence for replay")
        window.hint:SetText("State, source revision, candidates, costs and exclusions; inspection only.")
        window.edit:SetText(wire);window:Show();window.edit:SetFocus();window.edit:HighlightText()
    end,"questplanner:transfer")
end
function transferView.Open(inspect)
    local wire,exported
    if not inspect then
        local snapshot,status=planner.GetSnapshot()
        if not snapshot then core:Print("No quest observations are available."); return end
        snapshot.context=planner.Controller.Context()
        snapshot.observationStatus=status
        local reason
        wire,reason,exported=planner.Transfer.EncodeSession(snapshot,planner.Journal.Export())
        if not wire then core:Print(reason); return end
    end
    core.Combat.Queue(function()
        if not window then build() end
        window.inspect=inspect==true;window.edit:SetMaxLetters(inspect and 1048576 or 131072)
        window.title:SetText(inspect and "Paste observations to inspect (never used as live state)" or "Copy quest observations from this session")
        window.hint:SetText(exported and exported.omittedEntries>0
            and ("Newest "..exported.exportedEntries.." of "..exported.availableEntries.." journal entries; current log included.")
            or "Ctrl+A, Ctrl+C to copy. No automatic disk or settings storage.")
        window.edit:SetText(wire or ""); window:Show(); window.edit:SetFocus(); window.edit:HighlightText()
    end,"questplanner:transfer")
end
