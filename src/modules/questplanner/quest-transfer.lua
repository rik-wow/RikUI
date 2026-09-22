-- Manual, versioned observation transfer. Never writes profiles or promotes facts.
local planner, guard = RikUI.QuestPlanner, RikUI.Secret
local schema, transfer = planner.Schema, {}
planner.Transfer = transfer
local MAX_WIRE, MAX_NODES, MAX_DEPTH, MAX_TEXT = 131072, 16384, 16, 2048
local MODULUS = 65521
local MAX_PAYLOAD = 65528

local function scalar(text, state)
    state.bytes = state.bytes + #text
    if state.bytes > (state.maxBytes or MAX_PAYLOAD) then error("observation byte limit") end
    return text
end

local function checksum(text)
    local a, b = 1, 0
    for index = 1, #text do a = (a + text:byte(index)) % MODULUS; b = (b + a) % MODULUS end
    return string.format("%08x", b * 65536 + a)
end

local function visit(state, depth)
    state.nodes = state.nodes + 1
    if state.nodes > (state.maxNodes or MAX_NODES) or depth > (state.maxDepth or MAX_DEPTH) then error("observation limit") end
end

local function encode(value, state, depth)
    visit(state, depth)
    if guard.IsSecret(value) then error("secret observation") end
    local kind = type(value)
    if kind == "boolean" then return scalar(value and "b1" or "b0", state) end
    if kind == "string" then
        if #value > MAX_TEXT then error("observation text limit") end
        return scalar("s" .. #value .. ":" .. value, state)
    end
    if kind == "number" and schema.Number(value, -2147483647, 2147483647) then
        local text = string.format("%.17g", value)
        return scalar("n" .. #text .. ":" .. text, state)
    end
    if not schema.PlainTable(value) or state.seen[value] then error("invalid observation data") end
    state.seen[value] = true
    local keys, parts = {}, {}
    for key in pairs(value) do
        if guard.IsSecret(key) or (type(key) ~= "string" and not schema.ID(key)) then error("invalid observation key") end
        keys[#keys + 1] = key
        if #keys > (state.maxNodes or MAX_NODES) then error("observation key limit") end
    end
    table.sort(keys, function(a, b) if type(a) ~= type(b) then return type(a) < type(b) end; return a < b end)
    parts[1] = scalar("t" .. #keys .. ":", state)
    for _, key in ipairs(keys) do
        parts[#parts + 1], parts[#parts + 2] = encode(key, state, depth + 1), encode(value[key], state, depth + 1)
    end
    state.seen[value] = nil
    local result = table.concat(parts)
    if #result > (state.maxBytes or MAX_WIRE) then error("observation byte limit") end
    return result
end

local function length(state)
    local colon = state.text:find(":", state.at, true)
    if not colon or colon - state.at > 6 then error("invalid observation length") end
    local raw = state.text:sub(state.at, colon - 1)
    if not raw:match("^%d+$") or tostring(tonumber(raw)) ~= raw then error("invalid observation length") end
    state.at = colon + 1
    return tonumber(raw)
end

local function decode(state, depth)
    visit(state, depth)
    local tag = state.text:sub(state.at, state.at)
    state.at = state.at + 1
    if tag == "b" then
        local flag = state.text:sub(state.at, state.at); state.at = state.at + 1
        if flag ~= "0" and flag ~= "1" then error("invalid observation boolean") end
        return flag == "1"
    end
    if tag ~= "s" and tag ~= "n" and tag ~= "t" then error("invalid observation tag") end
    local size = length(state)
    if tag ~= "t" then
        if size > MAX_TEXT or state.at + size - 1 > #state.text then error("truncated observation") end
        local raw = state.text:sub(state.at, state.at + size - 1); state.at = state.at + size
        if tag == "s" then return raw end
        local number = tonumber(raw)
        if not schema.Number(number, -2147483647, 2147483647) or string.format("%.17g", number) ~= raw then error("invalid observation number") end
        return number
    end
    if size > (state.maxNodes or MAX_NODES) then error("observation table limit") end
    local result = {}
    for _ = 1, size do
        local key, value = decode(state, depth + 1), decode(state, depth + 1)
        if (type(key) ~= "string" and not schema.ID(key)) or result[key] ~= nil then error("invalid/duplicate observation key") end
        result[key] = value
    end
    return result
end

local function validate(value)
    if not schema.PlainTable(value) or not schema.Identity(value.identity) or not schema.List(value.order, 256)
        or not schema.PlainTable(value.quests) or not schema.Integer(value.observedCount, 0, 256)
        or not schema.Integer(value.reportedCount, 0, 256) or value.observedCount ~= #value.order
        or (value.coverage ~= "log-complete" and value.coverage ~= "log-partial") then error("invalid observation snapshot") end
    local seen, count = {}, 0
    for _, id in ipairs(value.order) do
        if not schema.ID(id) then error("invalid observation ID") end
        local quest = value.quests[id]
        if seen[id] or not schema.PlainTable(quest) or quest.id ~= id then error("invalid observation quest") end
        seen[id] = true
    end
    for id in pairs(value.quests) do if not seen[id] then error("unordered observation quest") end; count = count + 1 end
    if count ~= #value.order then error("invalid observation count") end
    return value
end

function transfer.Encode(snapshot)
    local ok, wire = pcall(function()
        validate(snapshot)
        local payload = encode(snapshot, { nodes = 0, bytes = 0, seen = {} }, 0)
        local hex = payload:gsub(".", function(byte) return string.format("%02x", byte:byte()) end)
        local text = "RIKQ1:" .. checksum(payload) .. ":" .. hex
        if #text > MAX_WIRE then error("observation byte limit") end
        return text
    end)
    if ok then return wire end
    return nil, "invalid or oversized observation export"
end

local function exportSelection(journal,entries,count)
    local total=#entries
    journal.entries={}
    for index=total-count+1,total do journal.entries[#journal.entries+1]=entries[index] end
    journal.export={selection="newest-contiguous",availableEntries=total,
        exportedEntries=count,omittedEntries=total-count}
end

-- Preserve the current log/context and fit the newest contiguous journal suffix.
-- At most seven bounded encoding attempts are needed for the 48-entry journal.
function transfer.EncodeSession(snapshot,journal)
    local value=schema.CopyLimited(snapshot,MAX_NODES,MAX_PAYLOAD,MAX_DEPTH)
    local history=schema.CopyLimited(journal,32768,1048576,MAX_DEPTH)
    if not value or value.journal~=nil or not history or not schema.List(history.entries,48)
        or not schema.Integer(history.dropped,0,2147483647) or history.scope~="session-only" then
        return nil,"invalid session observation export"
    end
    local entries=history.entries
    value.journal=history
    exportSelection(history,entries,0)
    local best,reason=transfer.Encode(value)
    if not best then return nil,reason end
    local low,high,count=1,#entries,0
    while low<=high do
        local middle=math.floor((low+high)/2)
        exportSelection(history,entries,middle)
        local wire=transfer.Encode(value)
        if wire then best,count,low=wire,middle,middle+1 else high=middle-1 end
    end
    exportSelection(history,entries,count)
    return best,nil,schema.Clone(history.export)
end

function transfer.Decode(wire)
    if guard.IsSecret(wire) or type(wire) ~= "string" or #wire > MAX_WIRE then return nil, "invalid observation packet" end
    local hash, hex = wire:match("^RIKQ1:([a-f0-9]+):([a-f0-9]+)$")
    if not hash or #hash ~= 8 or #hex % 2 ~= 0 then return nil, "invalid observation packet" end
    local payload = hex:gsub("..", function(byte) return string.char(tonumber(byte, 16)) end)
    if checksum(payload) ~= hash then return nil, "observation checksum mismatch" end
    local ok, result = pcall(function()
        local state = { text = payload, at = 1, nodes = 0 }
        local value = decode(state, 0)
        if state.at ~= #payload + 1 then error("trailing observation bytes") end
        validate(value)
        value.origin = "imported-untrusted"
        return value
    end)
    if ok then return result end
    return nil, "invalid observation payload"
end

-- Diagnostic packets never promote an imported rollout to live state.
local PLAN_BYTES,PLAN_NODES=4194296,250000
local function validatePlan(value)
    if not schema.PlainTable(value) or (value.version~=1 and value.version~=2 and value.version~=3) or not schema.PlainTable(value.state)
        or not schema.Identity(value.state.identity) or not schema.Text(value.stateKey)
        or not schema.List(value.candidateIDs,768) or not schema.List(value.actions,128)
        or not schema.PlainTable(value.constraints) then error("invalid plan trace") end
    for _,ids in ipairs({value.candidateIDs,value.actions}) do
        for _,id in ipairs(ids) do if not schema.Text(id) or #id>160 then error("invalid action identity") end end
    end
end
function transfer.EncodePlan(trace)
    local ok,wire=pcall(function()
        validatePlan(trace)
        local payload=encode(trace,{nodes=0,bytes=0,seen={},maxBytes=PLAN_BYTES,maxNodes=PLAN_NODES,maxDepth=24},0)
        return "RIKP1:"..checksum(payload)..":"..payload:gsub(".",function(byte) return string.format("%02x",byte:byte()) end)
    end)
    if ok then return wire end
    return nil,"Plan trace is unavailable or exceeds the bounded export size"
end
function transfer.DecodePlan(wire)
    if guard.IsSecret(wire) or type(wire)~="string" or #wire>8388608 then return nil,"invalid plan packet" end
    local hash,hex=wire:match("^RIKP1:([a-f0-9]+):([a-f0-9]+)$")
    if not hash or #hash~=8 or #hex%2~=0 then return nil,"invalid plan packet" end
    local payload=hex:gsub("..",function(byte) return string.char(tonumber(byte,16)) end)
    if checksum(payload)~=hash then return nil,"plan checksum mismatch" end
    local ok,result=pcall(function()
        local state={text=payload,at=1,nodes=0,maxNodes=PLAN_NODES,maxDepth=24}
        local value=decode(state,0)
        if state.at~=#payload+1 then error("trailing plan bytes") end
        validatePlan(value);value.origin="imported-untrusted";value.state.origin="imported-untrusted";value.state.fresh=false
        return value
    end)
    if ok then return result end
    return nil,"invalid plan payload"
end
