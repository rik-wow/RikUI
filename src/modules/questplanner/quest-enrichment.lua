-- Bounded native metadata requests for quests already observed in the live log.
local RikUI = _G.RikUI
local planner = RikUI and RikUI.QuestPlanner
if not planner then return end

local enrichment = {}
planner.Enrichment = enrichment

local REQUESTS_PER_STEP, MAX_INFLIGHT, SESSION_LIMIT = 2, 2, 40
local MAX_ATTEMPTS, RETRY_SECONDS, TIMEOUT_SECONDS, LOG_LIMIT = 2, 30, 30, 80
local identityKey, identity, active, missing, order = nil, nil, {}, {}, {}
local records, pending, log = {}, {}, {}
local requests, accepted, failed, ignored = 0, 0, 0, 0
local trusted = false
local nextTick = 0

local function validId(value)
    return planner.Schema.ID(value)
end

local function call(fn, ...)
    if type(fn) ~= 'function' or not planner.Context or type(planner.Context.Call) ~= 'function' then
        return false
    end
    return planner.Context.Call(fn, ...)
end

local function now()
    local ok, value = call(_G.GetTime)
    if ok and planner.Schema.Number(value,0,2147483647) then return value end
    return 0
end

local function append(id, status, attempt, at)
    log[#log + 1] = {questID = id, status = status, attempt = attempt or 0, at = at or now(),
        source = 'native-quest-metadata', identityKey = identityKey}
    if #log > LOG_LIMIT then table.remove(log, 1) end
end

local function getIdentity(snapshot)
    local value = snapshot.identity
    if type(value) ~= 'table' then return nil end
    local parts = {}
    for _, name in ipairs({'product', 'build', 'locale'}) do
        local part = value[name]
        if (type(part) ~= 'string' and type(part) ~= 'number') or tostring(part) == '' then return nil end
        part = tostring(part)
        if #part > 128 then return nil end
        parts[#parts + 1] = #part .. ':' .. part
    end
    return table.concat(parts, '|'), {product = value.product, build = value.build, locale = value.locale}
end

local function missingFields(quest)
    local unknown = type(quest.unknown) == 'table' and quest.unknown or {}
    return unknown.title == true or type(quest.title) ~= 'string' or quest.title == '',
        unknown.objectives == true or quest.objectives == nil
end

function enrichment.Ensure(snapshot)
    nextTick = 0
    active, missing, order, trusted = {}, {}, {}, false
    if type(snapshot) ~= 'table' or snapshot.origin == 'imported-untrusted'
        or type(snapshot.quests) ~= 'table' or type(snapshot.order) ~= 'table' then return false end
    local key, snapshotIdentity = getIdentity(snapshot)
    if not key then return false end
    if key ~= identityKey then
        -- Keep old pending IDs as tombstones until their callback/timeout: events carry
        -- only a quest ID, so an old event must not be accepted for a new identity.
        identityKey, identity = key, snapshotIdentity
        records, log = {}, {}
        requests, accepted, failed, ignored = 0, 0, 0, 0
    end
    trusted = true
    for _, id in ipairs(snapshot.order) do
        local quest = validId(id) and snapshot.quests[id] or nil
        if type(quest) == 'table' and quest.origin ~= 'imported-untrusted' and not active[id] then
            active[id], order[#order + 1] = true, id
            local title, objectives = missingFields(quest)
            if title or objectives then
                missing[id] = {title = title, objectives = objectives}
                local record = records[id]
                if record and (record.status == 'loaded-awaiting-read' or record.status == 'resolved') then
                    record.status = 'loaded-missing'
                end
            elseif records[id] then
                records[id].status = 'resolved'
            end
        end
    end
    for id, record in pairs(pending) do
        if record.identityKey == identityKey and not active[id] and not record.dropped then
            -- Keep a tombstone to disambiguate a late callback from re-acceptance.
            record.dropped = true
            append(id, 'dropped', record.attempts)
        end
    end
    return true
end

local function failure(id, record, status, at)
    pending[id] = nil
    record.status, record.nextAt = status, at + RETRY_SECONDS
    failed = failed + 1
    append(id, status, record.attempts, at)
end

function enrichment.Step()
    if not trusted then return 0 end
    local at, inflight = now(), 0
    for id, record in pairs(pending) do
        if at >= record.deadline then
            if record.identityKey == identityKey and not record.dropped and active[id] then
                failure(id, record, 'timeout', at)
            else
                pending[id] = nil
            end
        elseif record.identityKey == identityKey and not record.dropped and active[id] then
            inflight = inflight + 1
        end
    end
    local api = _G.C_QuestLog
    if type(api) ~= 'table' or type(api.RequestLoadQuestByID) ~= 'function' then return 0 end
    local sent = 0
    for _, id in ipairs(order) do
        if sent >= REQUESTS_PER_STEP or inflight >= MAX_INFLIGHT or requests >= SESSION_LIMIT then break end
        if active[id] and missing[id] and not pending[id] then
            local record = records[id]
            if not record then
                record = {attempts = 0, nextAt = 0, identityKey = identityKey}
                records[id] = record
            end
            if record.attempts < MAX_ATTEMPTS and at >= record.nextAt
                and record.status ~= 'loaded-awaiting-read' and record.status ~= 'resolved' then
                record.attempts, record.status = record.attempts + 1, 'pending'
                record.requestedAt, record.deadline, record.dropped = at, at + TIMEOUT_SECONDS, nil
                pending[id] = record
                requests, sent, inflight = requests + 1, sent + 1, inflight + 1
                append(id, 'requested', record.attempts, at)
                -- A successful function call only means the request was submitted.
                -- Metadata is read exclusively by the next authoritative snapshot.
                local ok = call(api.RequestLoadQuestByID, id)
                if not ok then failure(id, record, 'request-failed', at); inflight = inflight - 1 end
            end
        end
    end
    return sent
end

function enrichment.OnResult(id, success)
    nextTick = 0
    if RikUI.Secret.IsSecret(success) then return false end
    if not validId(id) then return false end
    local record = pending[id]
    if not record then ignored = ignored + 1; return false end
    if not trusted or record.identityKey ~= identityKey or record.dropped or not active[id] then
        pending[id], ignored = nil, ignored + 1
        return false
    end
    local at = now()
    if at >= record.deadline then failure(id, record, 'timeout', at); return false end
    if success ~= true then failure(id, record, 'load-failed', at); return false end
    pending[id] = nil
    record.status, record.nextAt = 'loaded-awaiting-read', at + RETRY_SECONDS
    accepted = accepted + 1
    append(id, 'loaded-awaiting-read', record.attempts, at)
    if type(planner.Request) == 'function' then planner.Request() end
    return true
end

function enrichment.Status()
    local count, waiting, unresolved, entries = 0, 0, 0, {}
    local nextAt, at = nil, now()
    local function wake(value)
        if not nextAt or value < nextAt then nextAt = value end
    end
    for id, record in pairs(pending) do
        if trusted then wake(record.deadline) end
        if record.identityKey == identityKey and not record.dropped and active[id] then
            count = count + 1
        end
    end
    for id in pairs(missing) do
        unresolved = unresolved + 1
        local record = records[id]
        if not pending[id] and (not record or record.attempts < MAX_ATTEMPTS)
            and requests < SESSION_LIMIT and (not record or record.status ~= 'loaded-awaiting-read') then
            waiting = waiting + 1
            if count < MAX_INFLIGHT then wake(record and math.max(at, record.nextAt) or at) end
        end
    end
    for index, value in ipairs(log) do
        entries[index] = {questID = value.questID, status = value.status, attempt = value.attempt,
            at = value.at, source = value.source, identityKey = value.identityKey}
    end
    local api = _G.C_QuestLog
    return {trusted = trusted, available = type(api) == 'table' and type(api.RequestLoadQuestByID) == 'function',
        identity = identity and {product = identity.product, build = identity.build, locale = identity.locale} or nil,
        requests = requests, accepted = accepted, failed = failed, ignored = ignored, inflight = count,
        waiting = waiting, nextAt = nextAt, unresolved = unresolved, exhausted = requests >= SESSION_LIMIT,
        limit = SESSION_LIMIT, maxAttempts = MAX_ATTEMPTS, log = entries}
end

-- Called by the frame worker; detailed status/log copies occur only when work is due.
function enrichment.Tick()
    if not nextTick then return end
    if now()<nextTick then return end
    enrichment.Step()
    local status=enrichment.Status()
    nextTick=status.available and status.nextAt or nil
end

