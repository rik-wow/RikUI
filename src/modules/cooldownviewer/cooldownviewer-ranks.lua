-- The native manager can track several ranks of one spell as separate entries, and marks them
-- all known, so a level 3 Warlock sees Immolate rank 1 beside rank 7. RikUI shows the entry for
-- the highest rank the spellbook holds and hides the rest. Detection only reads the manager's
-- built display data; changes run Blizzard's own settings calls from a click and reload at once,
-- so no RikUI-written layout state outlives the click.
local core, viewer = RikUI, RikUI.CooldownViewer
local POPUP, DELAY = "RIKUI_COOLDOWN_RANKS", 1
local HIDDEN, KEPT = "hidden", "kept"
local GROUPS = {
    { "Essential", "Utility", hidden = "HiddenActive" },
    { "TrackedBuff", "TrackedBar", hidden = "HiddenPassive" },
}
local pending, shown, queued = nil, nil, false

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

-- Per character: HIDDEN for entries RikUI hid, KEPT for entries the player chose to keep.
local function marks()
    local db = core.CharDB
    if db and type(db.cooldownRankMarks) ~= "table" then db.cooldownRankMarks = {} end
    return db and db.cooldownRankMarks or {}
end

local function categoriesOf(group)
    local categories, enum = {}, Enum.CooldownViewerCategory
    for _, name in ipairs(group) do
        if readable(enum[name], "number") then categories[enum[name]] = true end
    end
    return categories
end

-- Visible entries of one row group plus the ones RikUI hid, keyed by catalogue spell name.
local function collect(data, group, index, marked)
    local byName, categories = {}, categoriesOf(group)
    for _, id in ipairs(data.orderedCooldownIDs) do
        local info = data.cooldownInfoByID[id]
        local category = readable(info, "table") and info.category
        local visible = readable(category, "number") and categories[category] == true
        local rank = (visible or (category == group.hiddenID and marked[id] == HIDDEN)) and rankOf(info, index)
        if rank then
            byName[rank.name] = byName[rank.name] or {}
            table.insert(byName[rank.name], { id = id, rank = rank.rank, category = category, visible = visible })
        end
    end
    return byName
end

local function keeperOf(name, entries)
    local _, _, learned = core.Spells.HighestKnownRank(name)
    if type(learned) ~= "number" then return nil end
    table.sort(entries, function(a, b) return a.rank > b.rank end)
    for _, entry in ipairs(entries) do
        if entry.rank <= learned then return entry end
    end
end

local function firstVisible(entries)
    for _, entry in ipairs(entries) do if entry.visible then return entry end end
end

-- Moves that leave only the highest learned rank showing; nothing when the spellbook is unreadable.
local function movesFor(name, entries, hiddenID, marked)
    local shownEntry, keeper = firstVisible(entries), keeperOf(name, entries)
    if not shownEntry or not keeper then return {} end
    local moves = {}
    for _, entry in ipairs(entries) do
        if entry.visible and entry ~= keeper and marked[entry.id] ~= KEPT then
            moves[#moves + 1] = { id = entry.id, name = name, category = hiddenID, hide = true }
        end
    end
    if keeper.visible or (#moves == 0 and marked[shownEntry.id] == KEPT) then return moves end
    table.insert(moves, 1, { id = keeper.id, name = name, category = shownEntry.category })
    return moves
end

function viewer.FindRankChanges(data)
    local index, marked, found = rankIndex(), marks(), {}
    for _, group in ipairs(GROUPS) do
        group.hiddenID = Enum.CooldownViewerCategory[group.hidden]
        if readable(group.hiddenID, "number") then
            for name, entries in pairs(collect(data, group, index, marked)) do
                for _, move in ipairs(movesFor(name, entries, group.hiddenID, marked)) do found[#found + 1] = move end
            end
        end
    end
    return found
end

local function remember(found, kept)
    local marked = marks()
    for _, move in ipairs(found) do
        if kept then marked[move.id] = move.hide and KEPT or marked[move.id]
        else marked[move.id] = move.hide and HIDDEN or nil end
    end
    core:Changed()
end

-- Rebuild first so the writes use current data, then save through the native layout manager.
local function apply(source)
    source:GetOrderedCooldownIDs()
    local found = viewer.FindRankChanges(displayData(source))
    for _, move in ipairs(found) do
        local status = source:SetCooldownToCategory(move.id, move.category)
        if status ~= Enum.CooldownLayoutStatus.Success then error("layout status " .. tostring(status)) end
    end
    source:GetLayoutManager():SaveLayouts()
    return found
end

local function accept(_, context)
    if not context or pending ~= context then return end
    pending = nil
    if InCombatLockdown() then core:Print("Cooldown ranks unchanged in combat; /rik cooldownranks asks again."); return end
    local ok, result = pcall(apply, provider())
    if not ok then
        core:Print("Cooldown ranks unchanged: " .. tostring(result) .. ". /reload discards any partial change.")
        return
    end
    if #result == 0 then core:Print("Cooldown ranks: nothing left to change."); return end
    remember(result)
    ReloadUI()
end

local function keep(_, context)
    if not context or pending ~= context then return end
    pending = nil
    remember(context.found, true)
end

local function dismiss(_, context) if pending == context then pending = nil end end

local function installPopup()
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
    StaticPopupDialogs[POPUP] = {
        text = "Your cooldowns show ranks of %s you have not learned, or hide one you have. "
            .. "Show only your highest learned rank? This reloads the interface.",
        button1 = "Update and reload", button2 = "Not now", button3 = "Keep as is",
        OnAccept = accept, OnCancel = dismiss, OnAlt = keep,
        OnHide = function(_, context) dismiss(nil, context) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    return true
end

local function names(found)
    local seen, list = {}, {}
    for _, move in ipairs(found) do
        if not seen[move.name] then seen[move.name], list[#list + 1] = true, move.name end
    end
    table.sort(list)
    return table.concat(list, ", ")
end

-- The same set of changes is offered once per session; a newly learned rank makes a new set.
local function signature(found)
    local parts = {}
    for _, move in ipairs(found) do parts[#parts + 1] = move.id .. ":" .. move.category end
    return table.concat(parts, ",")
end

local function suggest()
    queued = false
    if pending or not core.CharDB or not Enum.CooldownViewerCategory or not Enum.CooldownLayoutStatus then return end
    local data = displayData(provider())
    local found = data and viewer.FindRankChanges(data) or {}
    if #found == 0 or signature(found) == shown or not installPopup() then return end
    local context = { found = found }
    pending = context
    if StaticPopup_Show(POPUP, names(found), nil, context) then shown = signature(found) else pending = nil end
end

local function request()
    if queued then return end
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
    local marked = marks()
    for id, mark in pairs(marked) do if mark == KEPT then marked[id] = nil end end
    core:Changed()
    shown = nil
    request()
end, "Ask again about cooldown entries for spell ranks: /rik cooldownranks")
