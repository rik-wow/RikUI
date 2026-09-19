-- Four fixed party1-4 buttons from the shared unit frame factory. SecureGroupHeaderTemplate
-- needs initialConfigFunction snippets, which cannot run on 69913, so there is no header.
local core, layout, unitframes = RikUI, RikUI.Layout, RikUI.UnitFrames
local party = { Frames = {}, FadeAlpha = 0.45 }
unitframes.Party = party

local MEMBERS, SPACING, POLL_SECONDS = 4, 14, 0.5
local SIZE = { width = 150, height = 36, health = 22, power = 11, font = "small", powerText = false }
local DEFAULT = { point = "LEFT", relativePoint = "LEFT", x = 20, y = 0 }
local LAYOUT_KEY, HOLDER_NAME = "party", "RikUIParty"
local VISIBILITY = "[group:raid] hide; [@%s,exists] show; hide"
local STOCK_FRAMES = { "PartyFrame", "CompactPartyFrame" }
local LEADER_TEXTURE, LEADER_SIZE, ICON_INSET = "Interface\\GroupFrame\\UI-Group-LeaderIcon", 12, 4
local ROLE_LETTERS = { TANK = "T", HEALER = "H", DAMAGER = "D" }
local warnings = {}

local function warnOnce(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Unit frames " .. operation .. ": " .. tostring(reason))
end

-- A secret boolean is never compared: SetAlphaFromBoolean takes it as it is.
local function alphaFromBoolean(region, value, yes, no)
    if not core.Secret.IsSecret(value) then region:SetAlpha(value == true and yes or no); return end
    if type(region.SetAlphaFromBoolean) == "function" then
        region:SetAlphaFromBoolean(value, yes, no)
    else
        region:SetAlpha(yes)
    end
end

local function applyRange(frame, inRange, checked)
    if core.Secret.IsSecret(inRange) or core.Secret.IsSecret(checked) then
        alphaFromBoolean(frame, inRange, 1, party.FadeAlpha)
    else
        -- An unchecked range says nothing about distance, so the member stays opaque.
        frame:SetAlpha((checked ~= true or inRange == true) and 1 or party.FadeAlpha)
    end
end

function party.UpdateRange(frame)
    local ok, reason = core.Secret.Apply(function(inRange, checked) applyRange(frame, inRange, checked) end,
        UnitInRange, frame.unit)
    if ok then return end
    frame:SetAlpha(1)
    warnOnce("range", reason)
end

local function updateLeader(frame)
    local ok, isLeader = core.Secret.Read(UnitIsGroupLeader, frame.unit)
    if not ok then warnOnce("leader", isLeader); frame.leader:Hide(); return end
    if core.Secret.IsSecret(isLeader) then
        frame.leader:Show()
        alphaFromBoolean(frame.leader, isLeader, 1, 0)
        return
    end
    frame.leader:SetAlpha(1)
    frame.leader:SetShown(isLeader == true)
end

local function updateRole(frame)
    local ok, role = core.Secret.Read(UnitGroupRolesAssigned, frame.unit)
    if not ok then warnOnce("role", role); role = nil end
    local readable = not core.Secret.IsSecret(role) and type(role) == "string"
    frame.role:SetText(readable and ROLE_LETTERS[role] or "")
end

function party.UpdateStatus(frame)
    updateLeader(frame)
    updateRole(frame)
    party.UpdateRange(frame)
end

local function eachMember(callback)
    for _, frame in ipairs(party.Frames) do callback(frame) end
end

local function refresh()
    eachMember(unitframes.Update)
    eachMember(party.UpdateStatus)
end

local function decorate(frame)
    frame.leader = frame.health:CreateTexture(nil, "OVERLAY")
    frame.leader:SetTexture(LEADER_TEXTURE)
    frame.leader:SetSize(LEADER_SIZE, LEADER_SIZE)
    frame.leader:SetPoint("RIGHT", frame.health, "RIGHT", -ICON_INSET, 0)
    frame.leader:Hide()
    frame.role = frame.power:CreateFontString(nil, "OVERLAY")
    core.Media.Font(frame.role, "small")
    frame.role:SetPoint("RIGHT", frame.power, "RIGHT", -ICON_INSET, 0)
end

local function createHolder()
    local holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(SIZE.width, MEMBERS * SIZE.height + (MEMBERS - 1) * SPACING)
    holder.elapsed = 0
    holder:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < POLL_SECONDS then return end
        self.elapsed = 0
        eachMember(party.UpdateRange)
    end)
    layout.Register(holder, LAYOUT_KEY, DEFAULT)
    return holder
end

local function createMember(index)
    local unit = "party" .. index
    local frame = unitframes.Build({ key = unit, unit = unit, size = SIZE, threat = { unit },
        visibility = VISIBILITY:format(unit) }, party.Holder)
    frame:SetPoint("TOPLEFT", party.Holder, "TOPLEFT", 0, -(index - 1) * (SIZE.height + SPACING))
    -- The health text would crowd a small frame; the bar alone carries health.
    frame.health.text:Hide()
    decorate(frame)
    party.Frames[index] = frame
end

local function hideStock()
    if not party.Holder then return end
    for _, name in ipairs(STOCK_FRAMES) do
        -- RikUI frames own party1-4 now, so no native handler needs to keep running.
        if _G[name] then core.Hide.Frame(_G[name], false) end
    end
end

local function create()
    if party.Holder then return end
    party.Holder = createHolder()
    for index = 1, MEMBERS do createMember(index) end
    refresh()
    hideStock()
end

-- Called from the unitframes module's OnEnable; that module routes the unit events.
function party.Enable()
    core.Combat.Queue(create)
    core:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        refresh()
        hideStock()
    end)
    core:RegisterEvent("PARTY_LEADER_CHANGED", function() eachMember(party.UpdateStatus) end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        eachMember(party.UpdateStatus)
        hideStock()
    end)
end
