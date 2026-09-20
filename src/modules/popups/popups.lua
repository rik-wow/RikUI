-- Flat skin over the static popups, the game menu and the release-spirit button. This file finds
-- the frames and hooks their OnShow; src/modules/popups/popups-skin.lua does the work on first show. Popups gate
-- protected actions such as deleting an item, so nothing is moved, resized, reparented, shown,
-- hidden or given a new script: only region alpha, fonts, font objects and new child regions are
-- written. Disable the module and reload for the stock look.
local core = RikUI
local popups = { Hooked = {}, Skinned = {}, Skin = {} }
core.Popups = popups

local TARGETS = {
    { name = "StaticPopup1", kind = "popup" }, { name = "StaticPopup2", kind = "popup" },
    { name = "StaticPopup3", kind = "popup" }, { name = "StaticPopup4", kind = "popup" },
    { name = "GameMenuFrame", kind = "menu" }, { name = "GhostFrame", kind = "ghost" },
}
local failed, warnings = {}, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Popups " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.HookScript) == "function"
end

-- A failed frame is not retried: half a skin applied twice is worse than half a skin. Refresh runs
-- on every show because the game menu rebuilds its buttons from a pool.
local function show(frame, target)
    local name = target.name
    if not popups.Skinned[name] and not failed[name] then
        local ok, reason = pcall(popups.Skin.Apply, frame, target)
        if ok then popups.Skinned[name] = true else failed[name] = true; warn("skin " .. name, reason) end
    end
    if not popups.Skinned[name] then return end
    local ok, reason = pcall(popups.Skin.Refresh, frame, target)
    if not ok then warn("refresh " .. name, reason) end
    popups.Skin.FadeIn(frame)
end

local function hook(target)
    local frame = _G[target.name]
    if popups.Hooked[target.name] or not isFrame(frame) then return end
    popups.Hooked[target.name] = true
    frame:HookScript("OnShow", function(self) show(self, target) end)
    if frame:IsShown() then show(frame, target) end
end

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

function popups:OnEnable()
    for _, target in ipairs(TARGETS) do hook(target) end
end

function popups:Debug()
    core:Print("Popups hooked=" .. count(popups.Hooked) .. " skinned=" .. count(popups.Skinned)
        .. " failed=" .. count(failed))
end

core:RegisterModule("popups", popups)
