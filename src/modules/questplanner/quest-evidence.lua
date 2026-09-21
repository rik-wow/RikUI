-- Each catalogue owns one exact content identity. No fallback across products/builds.
local planner = RikUI.QuestPlanner
local schema, evidence = planner.Schema, {}
planner.Evidence = evidence

local MAX_ASSERTIONS, MAX_SOURCES = 4096, 8

local function equal(first, second)
    if type(first) ~= type(second) then return false end
    if type(first) ~= "table" then return first == second end
    for key, value in pairs(first) do if not equal(value, second[key]) then return false end end
    for key in pairs(second) do if first[key] == nil then return false end end
    return true
end

local function add(state, questID, field, value, source)
    if not schema.ID(questID) then return nil, "invalid quest ID" end
    local provenance = schema.Copy(source)
    if not provenance or not schema.Source(provenance) then return nil, "invalid source" end
    if provenance.product ~= state.identity.product or provenance.build ~= state.identity.build
        or provenance.locale ~= state.identity.locale then
        return nil, "content identity mismatch"
    end
    local fact, reason = schema.Field(field, value)
    if fact == nil then return nil, reason end
    local quest = state.quests[questID]
    local entries = quest and quest[field] or {}
    for _, entry in ipairs(entries) do
        if entry.source.id == provenance.id then
            if equal(entry.value, fact) and equal(entry.source, provenance) then return true end
            return nil, "source already recorded; use a new revision ID"
        end
    end
    if #entries >= MAX_SOURCES or state.count >= MAX_ASSERTIONS then return nil, "evidence capacity reached" end
    state.quests[questID] = quest or {}
    entries[#entries + 1] = { value = fact, source = provenance }
    state.quests[questID][field], state.count = entries, state.count + 1
    return true
end

local function resolve(state, questID, field)
    if not schema.ID(questID) or not schema.Text(field) then return { status = "unknown", reason = "invalid query", evidence = {} } end
    local quest = state.quests[questID]
    local entries = schema.Clone(quest and quest[field] or {})
    table.sort(entries, function(a, b) return a.source.id < b.source.id end)
    local value, found, conflict = nil, false, false
    for _, entry in ipairs(entries) do
        if entry.source.authority == "verified" then
            if found and not equal(value, entry.value) then conflict = true end
            value, found = entry.value, true
        end
    end
    if conflict then return { status = "conflict", evidence = entries } end
    if found then return { status = "known", value = schema.Clone(value), evidence = entries } end
    return { status = "unknown", reason = #entries > 0 and "unverified" or "missing", evidence = entries }
end

function evidence.New(identity)
    local copy = schema.Copy(identity)
    if not copy or not schema.Identity(copy) then return nil, "invalid content identity" end
    local state = { identity = { product = copy.product, build = copy.build, locale = copy.locale }, quests = {}, count = 0 }
    return {
        Add = function(_, ...) return add(state, ...) end,
        Resolve = function(_, ...) return resolve(state, ...) end,
        Identity = function() return schema.Clone(state.identity) end,
    }
end
