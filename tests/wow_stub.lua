-- Minimal fake of the WoW Forever client globals, enough to load RikProbe.lua
-- under luajit. It mimics the beta's known sharp edges: loadstring_untainted
-- is nil, RegisterEvent throws on unknown events, the player's own health is
-- a secret value. Everything else is a plain no-op with a sensible return.

local env = {
    printed = {},
    frames = {},
    stateDrivers = {},
    timers = {},
    hooks = {},
}

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
env.SECRET = SECRET

local KNOWN_EVENTS = {
    ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true,
    CURSOR_CHANGED = true, -- Forever 69913 CursorDocumentation.lua
    PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true, MODIFIER_STATE_CHANGED = true,
    UPDATE_BONUS_ACTIONBAR = true, UPDATE_SHAPESHIFT_FORM = true,
    UPDATE_SHAPESHIFT_FORMS = true, ACTIONBAR_PAGE_CHANGED = true,
    ACTIONBAR_SLOT_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true,
    SPELLS_CHANGED = true, CHARACTER_POINTS_CHANGED = true,
    PLAYER_TALENT_UPDATE = true, TRAIT_CONFIG_UPDATED = true, ACTIVE_COMBAT_CONFIG_CHANGED = true,
    UNIT_COMBAT = true, UNIT_HEALTH = true, PLAYER_LOGOUT = true, UI_SCALE_CHANGED = true, DISPLAY_SIZE_CHANGED = true,
    UNIT_MAXHEALTH = true, UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true,
    UNIT_NAME_UPDATE = true, UNIT_LEVEL = true, UNIT_FACTION = true, UNIT_CONNECTION = true,
    UNIT_CLASSIFICATION_CHANGED = true, UNIT_THREAT_SITUATION_UPDATE = true, UNIT_THREAT_LIST_UPDATE = true, UNIT_PET = true,
    UNIT_TARGET = true, PLAYER_TARGET_CHANGED = true, PLAYER_FOCUS_CHANGED = true,
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_INTERRUPTIBLE = true, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
    UNIT_AURA = true, WEAPON_ENCHANT_CHANGED = true, WEAPON_SLOT_CHANGED = true,
    ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true, ZONE_CHANGED_NEW_AREA = true, DIEL_CYCLE_CHANGED = true,
    BAG_UPDATE_DELAYED = true, GET_ITEM_INFO_RECEIVED = true, ITEM_DATA_LOAD_RESULT = true, BAG_UPDATE_COOLDOWN = true, ITEM_LOCK_CHANGED = true, PLAYER_MONEY = true,
    MERCHANT_SHOW = true, MERCHANT_CLOSED = true, MERCHANT_UPDATE = true,
    INVENTORY_SEARCH_UPDATE = true, GROUP_ROSTER_UPDATE = true, PARTY_LEADER_CHANGED = true,
    NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true,
    LOOT_OPENED = true, LOOT_CLOSED = true, LOOT_SLOT_CLEARED = true, LOOT_SLOT_CHANGED = true,
    PLAYER_XP_UPDATE = true, UPDATE_EXHAUSTION = true, PLAYER_LEVEL_UP = true, PLAYER_UPDATE_RESTING = true,
    UPDATE_FACTION = true, QUEST_LOG_UPDATE = true, QUEST_WATCH_LIST_CHANGED = true,
    QUEST_POI_UPDATE = true, CVAR_UPDATE = true, MAP_EXPLORATION_UPDATED = true,
    PLAYER_GUILD_UPDATE = true, CHAT_MSG_CHANNEL_NOTICE = true,
    MIRROR_TIMER_START = true, MIRROR_TIMER_STOP = true, MIRROR_TIMER_PAUSE = true,
    PLAYER_SWING = true, PLAYER_SWING_RANGE_UPDATE = true, UNIT_ATTACK_SPEED = true,
    START_AUTOREPEAT_SPELL = true, STOP_AUTOREPEAT_SPELL = true, PLAYER_DEAD = true,
    PLAYER_STARTED_MOVING = true, PLAYER_STOPPED_MOVING = true,
    UNIT_POWER_FREQUENT = true, UPDATE_INVENTORY_ALERTS = true, UPDATE_INVENTORY_DURABILITY = true,
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_MONSTER_SAY = true, CHAT_MSG_MONSTER_YELL = true, CHAT_MSG_MONSTER_PARTY = true,
    PLAYER_TOTEM_UPDATE = true, ADDON_ACTION_BLOCKED = true, ADDON_ACTION_FORBIDDEN = true,
    EDIT_MODE_LAYOUTS_UPDATED = true, PLAYER_SPECIALIZATION_CHANGED = true,
    SPELL_UPDATE_COOLDOWN = true, SPELL_UPDATE_CHARGES = true, SPELL_UPDATE_USES = true, SPELL_UPDATE_ICON = true,
    COOLDOWN_VIEWER_DATA_LOADED = true, COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED = true, -- 69977 CooldownViewerDocumentation.lua
}
env.KNOWN_EVENTS = KNOWN_EVENTS

local KNOWN_TEMPLATES = { SecureActionButtonTemplate = true, SecureHandlerStateTemplate = true,
    SecureUnitButtonTemplate = true, CustomAuraContainerTemplate = true, CustomAuraButtonTemplate = true,
    ContainerFrameItemButtonTemplate = true, BagSearchBoxTemplate = true }
local auraStub = require("aura_stub")

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local Frame = {}
Frame.__index = function(t, k)
    local v = rawget(Frame, k)
    if v ~= nil then return v end
    return function() end -- any unknown widget method is a no-op
end

function Frame:RegisterEvent(event)
    if not KNOWN_EVENTS[event] then
        error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
    end
    self.events[event] = true
end
Frame.RegisterUnitEvent = Frame.RegisterEvent
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:IsEventRegistered(event) return self.events[event] == true end
function Frame:SetScript(handler, fn) self.scripts[handler] = fn end
function Frame:GetScript(handler) return self.scripts[handler] end
function Frame:HookScript(handler, fn)
    self.hooks[handler] = self.hooks[handler] or {}
    table.insert(self.hooks[handler], fn)
end
function Frame:SetAttribute(name, value) self.attributes[name] = value end
function Frame:GetAttribute(name) return self.attributes[name] end
function Frame:GetName() return self.name end
function Frame:GetObjectType() return self.kind end
function Frame:IsShown() return self.shown end
function Frame:Show()
    if self.shown then return end
    self.shown = true
    env.runScript(self, "OnShow")
end
function Frame:Hide()
    if not self.shown then return end
    self.shown = false
    env.runScript(self, "OnHide")
end
function Frame:CreateTexture() return setmetatable({ kind = "Texture", parent = self, scripts = {}, hooks = {}, events = {}, attributes = {} }, Frame) end
function Frame:CreateFontString() return setmetatable({ kind = "FontString", parent = self, scripts = {}, hooks = {}, events = {}, attributes = {}, text = "" }, Frame) end
function Frame:SetText(text) self.text = text end
function Frame:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function Frame:GetText() return self.text end

function env.runScript(frame, handler, ...)
    local fn = frame.scripts[handler]
    if fn then fn(frame, ...) end
    for _, hook in ipairs(frame.hooks[handler] or {}) do hook(frame, ...) end
end

function CreateFrame(kind, name, parent, template)
    if template and not KNOWN_TEMPLATES[template] then
        error("CreateFrame: Unknown frame template: " .. tostring(template), 2)
    end
    if kind == "AuraContainer" and env.auraContainerMissing then
        error("CreateFrame: Unknown frame type: " .. kind, 2)
    end
    local f = setmetatable({
        kind = kind, name = name, parent = parent, template = template,
        scripts = {}, hooks = {}, events = {}, attributes = {}, shown = true,
    }, Frame)
    if kind == "AuraContainer" then auraStub.installContainer(f) end
    if kind == "AuraButton" then auraStub.installButton(f) end
    table.insert(env.frames, f)
    if name then _G[name] = f end
    return f
end

function env.fire(event, ...)
    for _, f in ipairs(env.frames) do
        if f.events[event] then env.runScript(f, "OnEvent", event, ...) end
    end
end

function env.click(frame, button)
    env.runScript(frame, "PreClick", button or "LeftButton")
    env.runScript(frame, "OnClick", button or "LeftButton")
    env.runScript(frame, "PostClick", button or "LeftButton")
end

------------------------------------------------------------------------
-- Globals the probe touches
------------------------------------------------------------------------
UIParent = CreateFrame("Frame", "UIParent")
ActionButton1 = CreateFrame("Button", "ActionButton1", UIParent)
ActionButton1.action = 1
EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
MainMenuBar = CreateFrame("Frame", "MainMenuBar", UIParent)

loadstring_untainted = nil
date = os.date
time = os.time
SlashCmdList = {}
AnchorUtil = {
    FlowLayoutAxis = { Horizontal = 0, Vertical = 1 },
    FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 },
}
AuraContainerItemEnchantmentSlot = { MainHand = 0, OffHand = 1, Ranged = 2 }
Enum = {
    PowerType = { Rage = 1, Mana = 0 },
    CustomAuraButtonDispelTypeTextureStyle = { Border = 0, BorderWithIcon = 1, Icon = 2, PreserveAsset = 3, CustomAsset = 4 },
    StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    SecondsFormatterInterval = { Seconds = 0, Minutes = 1, Hours = 2, Days = 3 },
}
GameFontNormal = "GameFontNormal"
GameFontNormalSmall = "GameFontNormalSmall"

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(env.printed, table.concat(parts, " "))
end

function issecretvalue(v) return v == SECRET end
function InCombatLockdown() return env.inCombat == true end
function GetTime() return os.clock() end
function UnitName() return "Probey" end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitLevel() return 12 end
function UnitExists(unit) return unit == "player" or unit == "target" end
function UnitHealth(unit) if unit == "player" then return SECRET end return 42 end
function UnitHealthMax() return 100 end
function UnitPower() return SECRET end
function UnitPowerMax() return 100 end
function UnitPowerType() return 1, "RAGE", 1, 0, 0 end
function UnitReaction() return 5 end
function UnitIsPlayer(unit) return unit == "player" end
function UnitThreatSituation() return nil end
function GetThreatStatusColor() return 1, 0, 0 end
function UnitCastingInfo() end
function UnitChannelInfo() end
function UnitCastingDuration() end
function UnitChannelDuration() end
function UnitIsConnected() return true end
function UnitIsTapDenied() return false end
function GetRealmName() return "Probe Realm" end
function GetBuildInfo() return "1.60.1", "69913", "Sep 17 2026", 16001 end

function GetActionCooldown() return 0, 0, 1, 1 end
function IsUsableAction() return true, false end
function IsActionInRange() return nil end
function GetActionCount() return 0 end
function HasAction(slot) return slot == 1 or slot == 73 end
function GetActionInfo(slot) if HasAction(slot) then return "spell", 78, "spell" end end
function GetActionTexture() return 132355 end
function GetActionText() return nil end
function GetBonusBarOffset() return env.bonusBarOffset or 1 end
function GetShapeshiftForm() return env.shapeshiftForm or 1 end
function GetActionBarPage() return 1 end
function GetNumShapeshiftForms() return 3 end
function GetShapeshiftFormInfo(i) return 132349, true, true, 2457 + i end
function GetBindingKey() return "1" end
function ActionButtonDown() end
function ActionButtonUp() end

function RegisterStateDriver(frame, state, condition)
    table.insert(env.stateDrivers, { frame = frame, state = state, condition = condition })
end
function UnregisterStateDriver() end
function SecureHandlerWrapScript() error("attempt to call a nil value") end
function SecureHandlerExecute() error("attempt to call a nil value") end
function hooksecurefunc(a, b, c)
    -- On 1.60.1.69977 a hook on an object's method leaves the method nil for Blizzard's callers.
    -- RikUI hooks global functions by name, and functions of plain C_ namespace tables
    -- (src/platform/hooks.lua). A widget has a metatable; a namespace table has none.
    local tbl, name, fn = _G, a, b
    if type(a) ~= "string" then
        if type(a) ~= "table" or getmetatable(a) ~= nil then
            error("hooksecurefunc(): object-method hooks break Blizzard callers on 69977", 2)
        end
        tbl, name, fn = a, b, c
    end
    local orig = tbl[name]
    if type(orig) ~= "function" then error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 2) end
    -- Like the client, the hook runs after the original and the original's returns are kept.
    tbl[name] = function(...)
        local results = { orig(...) }
        fn(...)
        return unpack(results, 1, table.maxn(results))
    end
    table.insert(env.hooks, name)
end

function IsShiftKeyDown() return env.shiftDown == true end
function HideUIPanel(frame) frame:Hide() end
env.settings = { registered = {}, opened = {} }
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local category = { frame = frame, name = name, id = "RikUI-" .. tostring(name) }
        function category:GetID() return self.id end
        table.insert(env.settings.registered, category)
        return category, {}
    end,
    RegisterAddOnCategory = function(category) category.addon = true end,
    OpenToCategory = function(id) table.insert(env.settings.opened, id) end,
}
ColorPickerFrame = {
    rgb = { 1, 1, 1 },
    SetupColorPickerAndShow = function(self, info) self.info = info end,
    GetColorRGB = function(self) return self.rgb[1], self.rgb[2], self.rgb[3] end,
}

function PickupSpell() end
function PlaceAction() end
function ClearCursor() end
function SetBinding() return true end
function SaveBindings() end
function CreateMacro() return 1 end
function EditMacro() return 1 end
function ReloadUI() end

C_Timer = {
    After = function(seconds, fn) table.insert(env.timers, { seconds = seconds, fn = fn }) end,
}
function env.flushTimers()
    local pending = env.timers
    env.timers = {}
    for _, t in ipairs(pending) do t.fn() end
end

C_Spell = { GetSpellCooldownDuration = function() end, GetSpellTexture = function() return 132355 end, GetSpellName = function() return "Heroic Strike" end, GetSpellInfo = function() end, PickupSpell = function() end }
function PickupAction() end
C_UnitAuras = { GetAuraDataByIndex = function() end, GetAuraDuration = function() end,
    GetAuraApplicationDisplayCount = function() return "" end }
C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function() end }
function GetInventoryItemTexture() return 135274 end
C_Macro = { GetNumMacros = function() return 0, 0 end }
C_CVar = { GetCVar = function() return "1" end, SetCVar = function() end, GetCVarInfo = function() end }
C_Secrets = { ShouldAurasBeSecret = function() return true end }
C_ActionBar = { GetActionCooldownDuration = function() end }
C_Item = { GetItemInfo = function() end }
C_AddOns = { GetAddOnMetadata = function() return "dev" end }
local function noopObject() return setmetatable({}, { __index = function() return function() end end }) end
C_DurationUtil = { CreateDuration = noopObject, CreateDurationTextBinding = noopObject }
C_StringUtil = { CreateSecondsFormatter = noopObject }
require("tooltip_stub").install(env) -- GameTooltip, its health bar, anchor/backdrop functions, TooltipDataProcessor

return env
