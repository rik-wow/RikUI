-- The native manager tracks each learned rank as its own entry, so Immolate can show twice.
-- Detection only reads the manager's built display data. Hiding runs Blizzard's own settings
-- calls from a click and reloads at once, so no RikUI-written layout state outlives the click.
local core, viewer = RikUI, RikUI.CooldownViewer
local POPUP, DELAY = "RIKUI_COOLDOWN_RANKS", 1
local GROUPS = {
    { "Essential", "Utility", hidden = "HiddenActive" },
    { "TrackedBuff", "TrackedBar", hidden = "HiddenPassive" },
}
local pending, shown, queued = nil, false, false

local function readable(value, kind) return not core.Secret.IsSecret(value) and type(value) == kind end

local function provider()
    local settings = CooldownViewerSettings
    if not settings or type(settings.GetDataProvider) ~= "function" then return nil end
    return settings:GetDataProvider()
end

local function displayData(source)
    if not source or type(source.GetDisplayData) ~= "function" then return nil end
    local data = source:GetDisplayData()
    if readable(data, "table") and readable(data.orderedCooldownIDs, "table")
        and readable(data.cooldownInfoByID, "table") then return data end
end

local function rankIndex()
    local index = {}
    for name, entry in pairs(core.Spells.Catalog()) do
        for rank, id in ipairs(entry.ranks or {}) do index[id] = { name = name, rank = rank } end
    end
    return index
end

local function rankOf(info, index)
    for _, key in ipairs({ "spellID", "overrideSpellID" }) do
        local id = info[key]
        if readable(id, "number") and index[id] then return index[id] end
    end
end

local function categoriesOf(group)
    local categories, enum = {}, Enum.CooldownViewerCategory
    for _, name in ipairs(group) do
        if readable(enum[name], "number") then categories[enum[name]] = true end
    end
    return categories
end

-- Known entries in one group of rows, keyed by catalogue spell name.
local function collect(data, categories, index)
    local byName = {}
    for _, id in ipairs(data.orderedCooldownIDs) do
        local info = data.cooldownInfoByID[id]
        local visible = readable(info, "table") and readable(info.category, "number")
            and categories[info.category] and info.isKnown == true
        local rank = visible and rankOf(info, index)
        if rank then
            byName[rank.name] = byName[rank.name] or {}
            table.insert(byName[rank.name], { id = id, rank = rank.rank })
        end
    end
    return byName
end

local function lowerRanks(entries, handled)
    table.sort(entries, function(a, b) return a.rank > b.rank end)
    local extra = {}
    for index = 2, #entries do
        if not handled[entries[index].id] then extra[#extra + 1] = entries[index].id end
    end
    return extra
end

local function handledIDs()
    local db = core.CharDB
    if db and type(db.cooldownRanksHandled) ~= "table" then db.cooldownRanksHandled = {} end
    return db and db.cooldownRanksHandled or {}
end

function viewer.FindDuplicateRanks(data)
    local index, handled, found = rankIndex(), handledIDs(), {}
    for _, group in ipairs(GROUPS) do
        local hidden = Enum.CooldownViewerCategory[group.hidden]
        if readable(hidden, "number") then
            for name, entries in pairs(collect(data, categoriesOf(group), index)) do
                for _, id in ipairs(lowerRanks(entries, handled)) do
                    found[#found + 1] = { id = id, name = name, hidden = hidden }
                end
            end
        end
    end
    return found
end

local function remember(found)
    local handled = handledIDs()
    for _, entry in ipairs(found) do handled[entry.id] = true end
    core:Changed()
end

-- Rebuild first so the write uses current data, then save through the native layout manager.
local function hide(source)
    source:GetOrderedCooldownIDs()
    local found = viewer.FindDuplicateRanks(displayData(source))
    for _, entry in ipairs(found) do
        local status = source:SetCooldownToCategory(entry.id, entry.hidden)
        if status ~= Enum.CooldownLayoutStatus.Success then error("layout status " .. tostring(status)) end
    end
    source:GetLayoutManager():SaveLayouts()
    return found
end

local function accept(_, context)
    if not context or pending ~= context then return end
    pending = nil
    if InCombatLockdown() then core:Print("Cooldown ranks unchanged in combat; /rik cooldownranks asks again."); return end
    local ok, result = pcall(hide, provider())
    if not ok then
        core:Print("Cooldown ranks unchanged: " .. tostring(result) .. ". /reload discards any partial change.")
        return
    end
    if #result == 0 then core:Print("Cooldown ranks: nothing left to hide."); return end
    remember(result)
    ReloadUI()
end

local function keep(_, context)
    if not context or pending ~= context then return end
    pending = nil
    remember(context.found)
end

local function dismiss(_, context) if pending == context then pending = nil end end

local function installPopup()
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
    StaticPopupDialogs[POPUP] = {
        text = "Your cooldowns track more than one rank of: %s. Hide the lower ranks? This reloads the interface.",
        button1 = "Hide and reload", button2 = "Not now", button3 = "Keep both",
        OnAccept = accept, OnCancel = dismiss, OnAlt = keep,
        OnHide = function(_, context) dismiss(nil, context) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    return true
end

local function names(found)
    local seen, list = {}, {}
    for _, entry in ipairs(found) do
        if not seen[entry.name] then seen[entry.name], list[#list + 1] = true, entry.name end
    end
    table.sort(list)
    return table.concat(list, ", ")
end

local function suggest()
    queued = false
    if shown or not core.CharDB or not Enum.CooldownViewerCategory or not Enum.CooldownLayoutStatus then return end
    local data = displayData(provider())
    local found = data and viewer.FindDuplicateRanks(data) or {}
    if #found == 0 or not installPopup() then return end
    local context = { found = found }
    pending = context
    if StaticPopup_Show(POPUP, names(found), nil, context) then shown = true else pending = nil end
end

local function request()
    if shown or queued then return end
    queued = true
    C_Timer.After(DELAY, function() core.Combat.Queue(suggest) end)
end

function viewer.EnableRanks()
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
        core:RegisterEvent(event, request, viewer)
    end
    request()
end

core:RegisterCommand("cooldownranks", function()
    if core.CharDB then core.CharDB.cooldownRanksHandled = {}; core:Changed() end
    shown = false
    request()
end, "Ask again about cooldown entries tracked at several ranks: /rik cooldownranks")
