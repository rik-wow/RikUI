-- Reads only this character's visible log. No world completeness or prerequisites inferred.
local planner, secret = RikUI.QuestPlanner, RikUI.Secret
local schema, reader = planner.Schema, {}
planner.Reader = reader
local MAX_ENTRIES, MAX_OBJECTIVES, MAX_COUNT = 256, 32, 2147483647

local function call(fn, ...)
    if secret.IsSecret(fn) or type(fn) ~= "function" then return false end
    return secret.Read(fn, ...)
end

local function identity()
    local ok, version, build, _, interface = call(GetBuildInfo)
    if not ok or not schema.Text(version) or not schema.Text(build)
        or not schema.Integer(interface, 1, MAX_COUNT) then return nil, "build information unavailable" end
    if interface ~= 16001 or not version:match("^1%.60%.%d+$") or not build:match("^%d+$") then
        return nil, "unsupported client identity"
    end
    local localized, locale = call(GetLocale)
    if not localized or not schema.Text(locale) or not locale:match("^[a-z][a-z][A-Z][A-Z]$") then
        return nil, "client locale unavailable"
    end
    local full, builds = version .. "." .. build, planner.Builds
    if builds then builds.Observe(full); full = builds.DataBuild(full) end
    return { product = "forever", build = full, locale = locale }
end

local function counts(api)
    local ok, shown, total = call(api.GetNumQuestLogEntries)
    if not ok or not schema.Integer(shown, 0, MAX_ENTRIES) or not schema.Integer(total, 0, MAX_ENTRIES) then
        return nil, nil, "quest log counts unavailable or exceed limit"
    end
    return shown, total
end

local function boolean(value)
    return not secret.IsSecret(value) and type(value) == "boolean"
end

local function field(quest, name, value, valid)
    if valid(value) then quest[name] = value else quest.unknown[name] = true end
end

local function objectiveRow(value)
    if not schema.PlainTable(value) or not schema.Text(value.text) or not schema.Text(value.type)
        or not boolean(value.finished) or not schema.Integer(value.numFulfilled, 0, MAX_COUNT)
        or not schema.Integer(value.numRequired, 0, MAX_COUNT) then return nil end
    return {
        text = value.text, type = value.type, finished = value.finished,
        numFulfilled = value.numFulfilled, numRequired = value.numRequired,
    }
end

local function objectives(api, questID)
    local ok, values = call(api.GetQuestObjectives, questID)
    if not ok then return nil end
    local valid, count = schema.List(values, MAX_OBJECTIVES)
    if not valid then return nil end
    local result = {}
    for index = 1, count do
        local objective = objectiveRow(values[index])
        if not objective then return nil end
        result[index] = objective
    end
    return result
end

local function optionalFlag(api, name, quest)
    local ok, value = call(api[name], quest.id)
    if ok and boolean(value) then return value end
end

local function questRow(api, info)
    if not schema.ID(info.questID) then return nil, "quest ID unavailable" end
    local quest = { id = info.questID, unknown = {} }
    field(quest, "title", info.title, schema.Text)
    field(quest, "level", info.level, function(value) return schema.Integer(value, -1, 1000) end)
    field(quest, "objectivesComplete", optionalFlag(api, "IsComplete", quest), boolean)
    field(quest, "failed", optionalFlag(api, "IsFailed", quest), boolean)
    quest.objectives = objectives(api, quest.id)
    if not quest.objectives then quest.unknown.objectives = true end
    return quest
end

local function readEntries(api, shown, snapshot)
    for index = 1, shown do
        local ok, info = call(api.GetInfo, index)
        if not ok or not schema.PlainTable(info) or secret.IsSecret(info.isHeader) then
            return nil, "quest log entry unavailable"
        end
        if info.isHeader ~= nil and not boolean(info.isHeader) then return nil, "invalid header flag" end
        if not info.isHeader then
            local quest, reason = questRow(api, info)
            if not quest then return nil, reason end
            if snapshot.quests[quest.id] then return nil, "duplicate quest ID" end
            snapshot.quests[quest.id] = quest
            snapshot.order[#snapshot.order + 1] = quest.id
            if next(quest.unknown) then snapshot.hasUnknown = true end
        end
    end
    return true
end

local function readSnapshot()
    local content, reason = identity()
    if not content then return nil, reason end
    local api = C_QuestLog
    if not schema.PlainTable(api) then return nil, "quest log API unavailable" end
    local shown, total, errorMessage = counts(api)
    if shown == nil then return nil, errorMessage end
    local snapshot = { identity = content, quests = {}, order = {}, hasUnknown = false }
    local ok, readError = readEntries(api, shown, snapshot)
    if not ok then return nil, readError end
    local shownAfter, totalAfter = counts(api)
    if shownAfter ~= shown or totalAfter ~= total then return nil, "quest log changed during read" end
    snapshot.observedCount, snapshot.reportedCount = #snapshot.order, total
    snapshot.coverage = snapshot.observedCount == total and "log-complete" or "log-partial"
    local timed, now = call(GetTime)
    if timed and schema.Number(now, 0, MAX_COUNT) then snapshot.observedAt = now end
    return snapshot
end

function reader.Read()
    local ok, snapshot, reason = pcall(readSnapshot)
    if not ok then return nil, "quest observation failed" end
    return snapshot, reason
end
