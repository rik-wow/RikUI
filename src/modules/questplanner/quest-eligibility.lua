-- Pure three-valued action eligibility. Observations never rewrite world rules.
local planner, guard = RikUI.QuestPlanner, RikUI.Secret
local schema, eligibility = planner.Schema, {}
planner.Eligibility = eligibility

local function boolean(value)
    if not guard.IsSecret(value) and type(value) == "boolean" then return value end
end

local function flag(state, name, id)
    local values = state[name]
    if not schema.PlainTable(values) then return nil end
    return boolean(values[id])
end

local function active(state, id)
    local value = flag(state, "active", id)
    if value ~= nil then return value end
    if boolean(state.logComplete) == true then return false end
end

local function atom(rule, state)
    if rule.op == "always" then return true end
    if rule.op == "never" then return false end
    if rule.op == "active" then return active(state, rule.questID) end
    if rule.op == "completed" then return flag(state, "turnedIn", rule.questID) end
    if rule.op == "flag" then return flag(state, "flags", rule.value) end
    local value = state[rule.op]
    if rule.op == "class" or rule.op == "race" then
        if schema.ID(value) then return value == rule.value end
    elseif rule.op == "faction" then
        if schema.Text(value) then return value == rule.value end
    elseif not state.levelProgressUnknown and schema.Integer(state.level, 0, 1000) then
        if rule.op == "levelAtLeast" then return state.level >= rule.value end
        if rule.op == "levelAtMost" then return state.level <= rule.value end
    end
end

local function evaluate(rule, state)
    if rule.op == "not" then
        local value = evaluate(rule.arg, state)
        if value ~= nil then return not value end
        return nil
    end
    if not rule.args then return atom(rule, state) end
    local unknown = false
    for _, child in ipairs(rule.args) do
        local value = evaluate(child, state)
        if rule.op == "all" and value == false then return false end
        if rule.op == "any" and value == true then return true end
        if value == nil then unknown = true end
    end
    if unknown then return nil end
    return rule.op == "all"
end

function eligibility.Condition(condition, state)
    local rule = schema.Condition(condition)
    if not rule or not schema.PlainTable(state) then return "unknown" end
    local value = evaluate(rule, state)
    if value == nil then return "unknown" end
    return value and "true" or "false"
end

local function requireValue(result, value, reason)
    if value == true then return end
    result.reasons[#result.reasons + 1] = reason
    if value == false then result.status = "blocked"
    elseif result.status ~= "blocked" then result.status = "unknown" end
end

local function fact(book, id, field)
    if not book then return nil, "missing " .. field end
    local result = book:Resolve(id, field)
    if result.status ~= "known" then return nil, result.status .. " " .. field end
    return result.value
end

local function rule(result, book, id, field, state)
    local value, reason = fact(book, id, field)
    if value == nil then requireValue(result, nil, reason); return end
    local condition = schema.Condition(value)
    requireValue(result, condition and evaluate(condition, state), field .. " not satisfied")
end

local function repeatable(result, book, id, state)
    local turnedIn = flag(state, "turnedIn", id)
    if turnedIn == false then return end
    if turnedIn == nil then requireValue(result, nil, "turn-in history unknown"); return end
    local repeats, reason = fact(book, id, "repeatable")
    requireValue(result, repeats, reason or "already turned in")
    if repeats then requireValue(result, flag(state, "repeatReady", id), "repeat availability unknown") end
end

local function capacity(state)
    if not schema.Integer(state.logCount, 0, 256) or not schema.Integer(state.logCapacity, 1, 256) then return nil end
    return state.logCount < state.logCapacity
end

local function pickup(result, action, state, book)
    local present = active(state, action.questID)
    local absent
    if present ~= nil then absent = not present end
    requireValue(result, absent, "quest already active or log coverage unknown")
    repeatable(result, book, action.questID, state)
    rule(result, book, action.questID, "prerequisites", state)
    rule(result, book, action.questID, "requirements", state)
    requireValue(result, capacity(state), "quest log full or capacity unknown")
end

local function currentAction(result, action, state)
    local id = action.questID
    requireValue(result, active(state, id), "quest not active or log coverage unknown")
    local failed = flag(state, "failed", id)
    local healthy
    if failed ~= nil then healthy = not failed end
    requireValue(result, healthy, "quest failed or failure state unknown")
    local complete = flag(state, "objectivesComplete", id)
    if action.kind == "objective" and complete ~= nil then complete = not complete end
    requireValue(result, complete, action.kind == "turnin" and "objectives not complete" or "no unfinished objectives")
end

local function validIdentity(state, book)
    if not schema.Identity(state.identity) then return false end
    if not book then return true end
    local identity = book:Identity()
    return identity.product == state.identity.product and identity.build == state.identity.build
        and identity.locale == state.identity.locale
end

local function actionResult(action, state, book)
    local result = { status = "unknown", reasons = { "invalid or stale state" } }
    if not schema.PlainTable(action) or not schema.ID(action.questID) or not schema.PlainTable(state) then return result end
    if boolean(state.fresh) ~= true or state.origin == "imported-untrusted" or not validIdentity(state, book) then return result end
    if action.kind ~= "pickup" and action.kind ~= "objective" and action.kind ~= "turnin" then return result end
    result = { status = "eligible", reasons = {}, questID = action.questID, kind = action.kind }
    if action.kind == "pickup" then pickup(result, action, state, book)
    else currentAction(result, action, state) end
    return result
end

function eligibility.Evaluate(action, state, book)
    local ok, result = pcall(actionResult, action, state, book)
    if ok then return result end
    return { status = "unknown", reasons = { "invalid eligibility input" } }
end

function eligibility.FromSnapshot(snapshot, status, attributes, history)
    if not schema.PlainTable(snapshot) or not schema.Identity(snapshot.identity)
        or not schema.List(snapshot.order, 256) or not schema.PlainTable(snapshot.quests) then return nil end
    local state = { identity = schema.Clone(snapshot.identity), generation = snapshot.generation,
        fresh = status and (status.state == "current" or status.state == "partial") or false,
        logComplete = snapshot.coverage == "log-complete", logCount = snapshot.reportedCount,
        active = {}, objectivesComplete = {}, failed = {}, turnedIn = {}, origin = snapshot.origin }
    for _, id in ipairs(snapshot.order) do
        if not schema.ID(id) or not schema.PlainTable(snapshot.quests[id]) then return nil end
        local quest = snapshot.quests[id]
        state.active[id], state.objectivesComplete[id], state.failed[id] = true, boolean(quest.objectivesComplete), boolean(quest.failed)
    end
    for _, key in ipairs({ "class", "race", "level", "logCapacity" }) do
        local value = attributes and attributes[key]
        if schema.Integer(value, 0, 1000) then state[key] = value end
    end
    if attributes and schema.Text(attributes.faction) then state.faction = attributes.faction end
    if schema.PlainTable(history) then
        local count = 0
        for id, value in pairs(history) do
            count = count + 1
            if count > 256 or not schema.ID(id) or boolean(value) == nil then return nil end
            state.turnedIn[id] = value
        end
    end
    return state
end
