-- Release ingestion is incremental and publishes only after every batch validates.
local planner = RikUI.QuestPlanner
local schema, corpus = planner.Schema, {}
planner.Corpus = corpus
local MAX_SOURCES, MAX_BATCH, MAX_ROWS, MAX_QUESTS = 64, 64, 32768, 8192
local MAX_NODES, MAX_BYTES = 262144, 4194304

local function token(value)
    return schema.Text(value) and #value > 0 and #value <= 128 and value:match("^[%w_.%-]+$") ~= nil
end

local function sameIdentity(a, b)
    return a.product == b.product and a.build == b.build and a.locale == b.locale
end

local function sourceCopy(raw, identity)
    local value = schema.Copy(raw)
    if not value or not schema.Identity(value) or not sameIdentity(value, identity) then return nil end
    if not token(value.id) or not token(value.dataset) or not token(value.revision) or not token(value.parser) then return nil end
    if value.authority ~= "verified" and value.authority ~= "reference" then return nil end
    if value.status ~= "active" and value.status ~= "superseded" and value.status ~= "retracted" then return nil end
    if not schema.Text(value.sha256) or #value.sha256 ~= 64 or value.sha256:find("[^a-f0-9]") then return nil end
    if not schema.Text(value.uri) or #value.uri == 0 or not schema.Text(value.terms) or #value.terms == 0 then return nil end
    if value.status == "retracted" and (not schema.Text(value.reason) or #value.reason == 0) then return nil end
    if value.supersedes ~= nil and not token(value.supersedes) then return nil end
    if value.mode ~= "snapshot" or not schema.Integer(value.assertions, 0, MAX_ROWS) then return nil end
    return value
end

local function manifests(identity, raw)
    if not schema.List(raw, MAX_SOURCES) then return nil, "invalid source manifest" end
    local sources, replaced = {}, {}
    for _, entry in ipairs(raw) do
        local value = sourceCopy(entry, identity)
        if not value or sources[value.id] then return nil, "invalid or duplicate source" end
        sources[value.id] = value
    end
    for id, value in pairs(sources) do
        local old = value.supersedes and sources[value.supersedes]
        if value.supersedes then
            if not old or old.dataset ~= value.dataset or old.status ~= "superseded" or replaced[old.id] then
                return nil, "invalid source supersession"
            end
            replaced[old.id] = id
        end
    end
    for id, value in pairs(sources) do
        if value.status == "superseded" and not replaced[id] then return nil, "orphan superseded source" end
        local seen, cursor = {}, id
        while cursor do
            if seen[cursor] then return nil, "cyclic source supersession" end
            seen[cursor], cursor = true, sources[cursor].supersedes
        end
    end
    return sources
end

local function measure(value, stats)
    stats.nodes = stats.nodes + 1
    if type(value) == "string" then stats.bytes = stats.bytes + #value end
    if type(value) ~= "table" then return end
    for key, child in pairs(value) do measure(key, stats); measure(child, stats) end
end

local function fail(state, reason)
    state.error, state.books, state.ids = reason, {}, {}
    return nil, reason
end

local function appendRow(state, raw)
    local row = schema.Copy(raw)
    if not row or not schema.ID(row.questID) or not token(row.source) then return nil, "invalid assertion" end
    local source = state.sources[row.source]
    if not source then return nil, "assertion source absent from manifest" end
    local value, reason = schema.Field(row.field, row.value)
    if value == nil then return nil, reason end
    state.rows = state.rows + 1
    state.sourceRows[row.source] = (state.sourceRows[row.source] or 0) + 1
    measure(row, state)
    measure({ id = source.id, product = source.product, build = source.build,
        locale = source.locale, authority = source.authority }, state)
    if state.rows > MAX_ROWS or state.nodes > MAX_NODES or state.bytes > MAX_BYTES then return nil, "corpus resource limit" end
    if source.status ~= "active" then return true end
    local book = state.books[row.questID]
    if not book then
        if #state.ids >= MAX_QUESTS then return nil, "corpus quest limit" end
        book = assert(planner.Evidence.New(state.identity))
        state.books[row.questID], state.ids[#state.ids + 1] = book, row.questID
    end
    return book:Add(row.questID, row.field, value, {
        id = source.id, product = source.product, build = source.build,
        locale = source.locale, authority = source.authority,
    })
end

local function resolve(state, id, field)
    if not schema.ID(id) then return { status = "unknown", reason = "invalid query", evidence = {} } end
    local book = state.books[id]
    if book then return book:Resolve(id, field) end
    return { status = "unknown", reason = "missing", evidence = {} }
end

local function ids(state, zone)
    local result = {}
    for _, id in ipairs(state.ids) do
        local found = zone and resolve(state, id, "zoneID")
        if not zone or (found.status == "known" and found.value == zone) then result[#result + 1] = id end
    end
    return result
end

local function coverage(state, zone)
    local selected = ids(state, zone)
    local report = { denominator = "unknown", catalogued = #selected, fields = {}, revision = state.revision }
    for _, field in ipairs(schema.Fields()) do
        local counts = { known = 0, conflict = 0, unknown = 0, referenceOnly = 0 }
        for _, id in ipairs(selected) do
            local result = resolve(state, id, field)
            counts[result.status] = counts[result.status] + 1
            if result.reason == "unverified" then counts.referenceOnly = counts.referenceOnly + 1 end
        end
        report.fields[field] = counts
    end
    report.unassignedZone = 0
    for _, id in ipairs(state.ids) do
        if resolve(state, id, "zoneID").status ~= "known" then report.unassignedZone = report.unassignedZone + 1 end
    end
    return report
end

local function publish(state)
    table.sort(state.ids)
    return {
        Resolve = function(_, id, field) return resolve(state, id, field) end,
        IDs = function(_, zone) return ids(state, zone) end,
        Identity = function() return schema.Clone(state.identity) end,
        Revision = function() return state.revision end,
        Sources = function()
            local values = {}
            for _, source in pairs(state.sources) do values[#values + 1] = schema.Clone(source) end
            table.sort(values, function(a, b) return a.id < b.id end)
            return values
        end,
        Coverage = function(_, zone) return coverage(state, zone) end,
        Metrics = function() return { assertions = state.rows, quests = #state.ids, nodes = state.nodes, bytes = state.bytes } end,
    }
end

function corpus.New(identity, rawSources, revision)
    local content = schema.Copy(identity)
    if not content or not schema.Identity(content) or not token(revision) then return nil, "invalid corpus identity/revision" end
    local sources, reason = manifests(content, rawSources)
    if not sources then return nil, reason end
    local state = { identity = content, revision = revision, sources = sources, books = {}, ids = {}, sourceRows = {}, rows = 0, nodes = 0, bytes = 0 }
    measure(content, state)
    measure(sources, state)
    return {
        Append = function(_, rows)
            if state.error or state.result then return nil, state.error or "corpus already published" end
            if not schema.List(rows, MAX_BATCH) then return fail(state, "append exceeds bounded batch") end
            for _, row in ipairs(rows) do
                local ok, problem = appendRow(state, row)
                if not ok then return fail(state, problem) end
            end
            return true
        end,
        Finish = function()
            if state.error then return nil, state.error end
            for id, source in pairs(state.sources) do
                if source.status == "active" and (state.sourceRows[id] or 0) ~= source.assertions then
                    return fail(state, "source snapshot assertion count mismatch")
                end
            end
            state.result = state.result or publish(state)
            return state.result
        end,
        Result = function() return state.result, state.error end,
    }
end
