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
