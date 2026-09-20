-- Flat skin over Blizzard's windows. This file finds the windows and hooks their OnShow;
-- src/modules/panels/panels-skin.lua does the work on first show. A window is never reparented, moved, shown, hidden
-- or given a new script: only region alpha, fonts and new child regions are written, none of which
-- is protected, so a first open in combat is safe. Disable the module and reload for the stock look.
local core = RikUI
local panels = { Hooked = {}, Skinned = {}, Skin = {} }
core.Panels = panels

-- On 69913 the spellbook and talents share PlayerSpellsFrame (load on demand) and the quest log is
-- QuestMapFrame inside WorldMapFrame, whose chrome sits on BorderFrame. A fill on that higher
-- frame level would cover the map, so the map gets no fill.
local TARGETS = {
    { name = "CharacterFrame" }, { name = "PlayerSpellsFrame" },
    { name = "WorldMapFrame", chrome = "BorderFrame", fill = false },
    { name = "MerchantFrame" }, { name = "BankFrame" }, { name = "MailFrame" }, { name = "OpenMailFrame" },
    { name = "TradeFrame" }, { name = "QuestFrame" }, { name = "GossipFrame" },
    -- The rest of Blizzard's windows. Most load on demand; one the client lacks is skipped.
    { name = "ClassTrainerFrame" }, { name = "AuctionHouseFrame" }, { name = "FriendsFrame" },
    { name = "CommunitiesFrame" }, { name = "MacroFrame" }, { name = "ProfessionsFrame" },
    { name = "ProfessionsBookFrame" }, { name = "InspectFrame" }, { name = "DressUpFrame" },
    { name = "ItemTextFrame" }, { name = "StableFrame" }, { name = "TabardFrame" }, { name = "PetitionFrame" },
    { name = "GuildRegistrarFrame" }, { name = "GuildBankFrame" }, { name = "HelpFrame" }, { name = "AddonList" },
    { name = "TimeManagerFrame" }, { name = "GroupLootHistoryFrame" }, { name = "SettingsPanel" },
    -- Found in the 69913 source after the first two lists. regions marks hand-drawn windows whose
    -- unnamed textures sit on the frame itself.
    { name = "PVEFrame" }, { name = "LFGParentFrame", regions = true }, { name = "ChannelFrame" },
    { name = "ItemSocketingFrame" }, { name = "ChatConfigFrame" }, { name = "RaidInfoFrame", regions = true },
    { name = "TaxiFrame" }, { name = "CollectionsJournal" }, { name = "GuildControlUI" }, { name = "DeathRecapFrame" },
    { name = "PVPMatchScoreboard" }, { name = "PVPMatchResults" }, { name = "CooldownViewerSettings" },
    -- The last audit. The Camelot stable is PetStableFrame. The zone map is a canvas like the world
    -- map: its border pieces are unnamed textures on BorderFrame and it gets no fill.
    { name = "AchievementFrame", regions = true }, { name = "CalendarFrame", regions = true },
    { name = "StopwatchFrame", regions = true }, { name = "SideDressUpFrame", regions = true },
    { name = "BattlefieldMapFrame", chrome = "BorderFrame", regions = true, fill = false },
    { name = "TransmogFrame" }, { name = "PetStableFrame" }, { name = "QuestLogPopupDetailFrame" },
    { name = "InspectRecipeFrame" }, { name = "ItemUpgradeFrame" }, { name = "ClickBindingFrame" },
    { name = "ArchaeologyFrame" },
}
local failed, warnings = {}, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Panels " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.HookScript) == "function"
end

-- A failed window is not retried: half a skin applied twice is worse than half a skin.
local function show(frame, target)
    local name = target.name
    if not panels.Skinned[name] and not failed[name] then
        local ok, reason = pcall(panels.Skin.Apply, frame, target)
        if ok then panels.Skinned[name] = true else failed[name] = true; warn("skin " .. name, reason) end
    end
    if not panels.Skinned[name] then return end
    -- Every show, not only the first: windows build controls as their tabs and lists fill.
    if core.Controls then core.Controls.Walk(frame) end
    panels.Skin.FadeIn(frame)
end

local function hook(target)
    local frame = _G[target.name]
    if panels.Hooked[target.name] or not isFrame(frame) then return end
    panels.Hooked[target.name] = true
    frame:HookScript("OnShow", function(self) show(self, target) end)
    if frame:IsShown() then show(frame, target) end
end

-- Runs at login and again for every addon that loads, which is how load-on-demand windows arrive.
function panels.Discover()
    for _, target in ipairs(TARGETS) do hook(target) end
end

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

function panels:OnEnable()
    panels.Skin.HookTabs()
    panels.Discover()
    core:RegisterEvent("ADDON_LOADED", panels.Discover)
end

function panels:Debug()
    core:Print("Panels hooked=" .. count(panels.Hooked) .. " skinned=" .. count(panels.Skinned)
        .. " failed=" .. count(failed))
end

core:RegisterModule("panels", panels)
