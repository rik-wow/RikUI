-- Bounded plain-data contracts; character observations never enter world facts.
local planner = {}
RikUI.QuestPlanner = planner
local schema = {}
planner.Schema = schema

local secret = RikUI.Secret
local MAX_ID, MAX_NODES, MAX_DEPTH, MAX_BYTES = 2147483647, 256, 10, 8192
local MAX_TEXT, MAX_LIST = 2048, 64

function schema.Number(value, minimum, maximum)
    return not secret.IsSecret(value) and type(value) == "number" and value == value
        and value >= minimum and value <= maximum
end

function schema.Integer(value, minimum, maximum)
    return schema.Number(value, minimum, maximum) and value % 1 == 0
end

function schema.ID(value) return schema.Integer(value, 1, MAX_ID) end

function schema.Text(value)
    return not secret.IsSecret(value) and type(value) == "string" and #value <= MAX_TEXT
end

function schema.PlainTable(value)
    return not secret.IsSecret(value) and type(value) == "table" and getmetatable(value) == nil
end

function schema.List(value, maximum)
    if not schema.PlainTable(value) then return false end
    local count = 0
    for key in pairs(value) do
        if not schema.Integer(key, 1, maximum) then return false end
        count = count + 1
        if count > maximum then return false end
    end
    for index = 1, count do
        if secret.IsSecret(value[index]) or value[index] == nil then return false end
    end
    return true, count
end

local function copyValue(value, state, depth)
    state.nodes = state.nodes + 1
    if state.nodes > MAX_NODES or depth > MAX_DEPTH or secret.IsSecret(value) then error("data limit or secret value") end
    local kind = type(value)
    if kind == "string" then
        state.bytes = state.bytes + #value
        if #value > MAX_TEXT or state.bytes > MAX_BYTES then error("text limit") end
        return value
    end
    if kind == "boolean" or (kind == "number" and schema.Number(value, -MAX_ID, MAX_ID)) then return value end
    if not schema.PlainTable(value) or state.seen[value] then error("unsupported or cyclic data") end
    state.seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if secret.IsSecret(key) or (type(key) ~= "string" and not schema.ID(key)) then error("invalid key") end
        result[copyValue(key, state, depth + 1)] = copyValue(child, state, depth + 1)
    end
    state.seen[value] = nil
    return result
end

function schema.Copy(value)
    local ok, result = pcall(copyValue, value, { nodes = 0, bytes = 0, seen = {} }, 0)
    if ok then return result end
    return nil, "invalid or oversized plain data"
end

-- Only for already validated, privately owned data.
function schema.Clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = schema.Clone(child) end
    return result
end

local function token(value)
    return schema.Text(value) and #value > 0 and #value <= 128 and value:match("^[%w_.%-]+$") ~= nil
end

function schema.Identity(value)
    return schema.PlainTable(value) and token(value.product) and token(value.build) and token(value.locale)
end

local function only(value, allowed)
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end

function schema.Source(value)
    return schema.Identity(value) and token(value.id)
        and (value.authority == "verified" or value.authority == "reference")
        and only(value, { product = true, build = true, locale = true, id = true, authority = true })
end

local function idList(value)
    if not schema.List(value, MAX_LIST) then return false end
    for _, id in ipairs(value) do if not schema.ID(id) then return false end end
    return true
end

local function condition(value)
    if not schema.PlainTable(value) then return false end
    if value.op == "always" or value.op == "never" then return only(value, { op = true }) end
    if value.op == "not" then return only(value, { op = true, arg = true }) and condition(value.arg) end
    if value.op == "class" or value.op == "race" then
        return only(value, { op = true, value = true }) and schema.ID(value.value)
    end
    if value.op == "levelAtLeast" or value.op == "levelAtMost" then
        return only(value, { op = true, value = true }) and schema.Integer(value.value, 0, 1000)
    end
    if value.op == "flag" or value.op == "faction" then
        return only(value, { op = true, value = true }) and token(value.value)
    end
    if value.op == "completed" or value.op == "active" then
        return schema.ID(value.questID) and only(value, { op = true, questID = true })
    end
    if value.op ~= "all" and value.op ~= "any" then return false end
    if not only(value, { op = true, args = true }) or not schema.List(value.args, MAX_LIST) or #value.args == 0 then return false end
    for _, child in ipairs(value.args) do if not condition(child) then return false end end
    return true
end

function schema.Condition(value)
    local copy, reason = schema.Copy(value)
    if not copy or not condition(copy) then return nil, reason or "invalid condition" end
    return copy
end

local function locations(value)
    if not schema.List(value, MAX_LIST) then return false end
    for _, point in ipairs(value) do
        if not schema.PlainTable(point) or not schema.ID(point.mapID)
            or not schema.Number(point.x, 0, 1) or not schema.Number(point.y, 0, 1)
            or not only(point, { mapID = true, x = true, y = true }) then return false end
    end
    return true
end

local fields = {
    zoneID = schema.ID,
    clientRecord = function(value) return type(value) == "boolean" end,
    title = function(value) return schema.Text(value) and #value > 0 end,
    level = function(value) return schema.Integer(value, -1, 1000) end,
    minLevel = function(value) return schema.Integer(value, 0, 1000) end,
    baseXP = function(value) return schema.Integer(value, 0, MAX_ID) end,
    repeatable = function(value) return type(value) == "boolean" end,
    startNPCs = idList, endNPCs = idList, prerequisites = condition, requirements = condition, locations = locations,
}

function schema.Fields()
    local names = {}
    for name in pairs(fields) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function uniqueSorted(values)
    table.sort(values)
    local result, previous = {}, nil
    for _, value in ipairs(values) do
        if value ~= previous then result[#result + 1] = value end
        previous = value
    end
    return result
end

local function normalizeCondition(value)
    if value.arg then return value.op .. "(" .. normalizeCondition(value.arg) .. ")" end
    if not value.args then return value.op .. ":" .. tostring(value.questID or value.value or "") end
    local keyed, keys = {}, {}
    for _, child in ipairs(value.args) do
        local key = normalizeCondition(child)
        keyed[key], keys[#keys + 1] = child, key
    end
    keys = uniqueSorted(keys)
    value.args = {}
    for _, key in ipairs(keys) do value.args[#value.args + 1] = keyed[key] end
    return value.op .. "(" .. table.concat(keys, ",") .. ")"
end

function schema.Field(name, value)
    local validate = type(name) == "string" and not secret.IsSecret(name) and fields[name]
    if not validate then return nil, "unsupported world field" end
    local copy, reason = schema.Copy(value)
    if copy == nil then return nil, reason end
    if not validate(copy) then return nil, "invalid " .. name end
    if name == "startNPCs" or name == "endNPCs" then copy = uniqueSorted(copy) end
    if name == "prerequisites" or name == "requirements" then normalizeCondition(copy) end
    return copy
end
