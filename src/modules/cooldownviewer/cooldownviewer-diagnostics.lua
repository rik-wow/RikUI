-- Report configured entries without reading live auras or touching native pooled items.
local core, viewer = RikUI, RikUI.CooldownViewer
local function readable(value, kind) return not core.Secret.IsSecret(value) and type(value) == kind end
local function field(value)
    if readable(value, "number") or readable(value, "boolean") then return tostring(value) end
    return "unknown"
end

local function report()
    if not CooldownViewerSettings or type(CooldownViewerSettings.GetDataProvider) ~= "function" then
        core:Print("Cooldown entries: native settings unavailable."); return
    end
    local provider = CooldownViewerSettings:GetDataProvider()
    local categories = Enum and Enum.CooldownViewerCategory
    if not provider or not categories then core:Print("Cooldown entries: categories unavailable."); return end
    for _, name in ipairs({ "Essential", "Utility", "TrackedBuff", "TrackedBar" }) do
        if readable(categories[name], "number") then
            local ids = provider:GetOrderedCooldownIDsForCategory(categories[name])
            if not readable(ids, "table") then error("unreadable category") end
            core:Print("Cooldown " .. name .. ": " .. #ids .. " configured entries")
            for _, id in ipairs(ids) do
                if not readable(id, "number") then error("unreadable entry ID") end
                local info = provider:GetCooldownInfoForID(id)
                if not readable(info, "table") then error("unreadable entry metadata") end
                core:Print("  entry=" .. id .. " spell=" .. field(info.spellID)
                    .. " override=" .. field(info.overrideSpellID) .. " aura=" .. field(info.hasAura)
                    .. " self=" .. field(info.selfAura))
            end
        end
    end
end

function viewer.DebugEntries()
    local ok, reason = pcall(report)
    if not ok then core:Print("Cooldown entries unavailable: " .. tostring(reason)) end
end

local function configured(name)
    if not CooldownViewerSettings or type(CooldownViewerSettings.GetDataProvider) ~= "function" then return nil end
    local provider = CooldownViewerSettings:GetDataProvider()
    local categories = Enum and Enum.CooldownViewerCategory
    if not provider or not categories or not readable(categories[name], "number") then return nil end
    local ids = provider:GetOrderedCooldownIDsForCategory(categories[name])
    if not readable(ids, "table") then return nil end
    return #ids
end

-- Whether the client configures nothing for a category (Essential, Utility, TrackedBuff,
-- TrackedBar) on this character: true, false, or nil when it cannot be read. A manager
-- switched off shows nothing either. This reads the settings data provider's entry list,
-- never live cooldown or aura state; the class cooldown row stands in when the middle is empty.
function viewer.NativeEmpty(name)
    if type(viewer.ManagerEnabled) == "function" and viewer.ManagerEnabled() == false then return true end
    local ok, count = pcall(configured, name)
    if not ok or type(count) ~= "number" then return nil end
    return count == 0
end
