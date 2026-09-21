-- Directed, time-dependent paths over explicitly sourced traversable connections.
local planner = RikUI.QuestPlanner
local schema, travel = planner.Schema, {}
planner.Travel = travel
local MAX_NODES, MAX_EDGES, MAX_LABELS, MAX_WORK = 512, 2048, 2048, 8192
local MAX_SECONDS, MAX_CLOCK = 86400, 2147483647

local function token(value)
    return schema.Text(value) and #value > 0 and #value <= 128 and value:match("^[%w_.:%-]+$") ~= nil
end

local function same(a, b)
    return schema.Identity(a) and schema.Identity(b) and a.product == b.product and a.build == b.build and a.locale == b.locale
end

local function source(value, identity)
    return schema.Source(value) and same(value, identity)
end

local EDGE_FIELDS = { id=true, from=true, to=true, seconds=true, mode=true, risk=true, uncertainty=true,
    zones=true, source=true, flightFrom=true, flightTo=true, transport=true, period=true, offset=true }

local function edgeValid(edge, graph)
    for key in pairs(edge) do if not EDGE_FIELDS[key] then return false end end
    if not token(edge.id) or not graph.nodes[edge.to] or not source(edge.source, graph.identity)
        or not schema.Number(edge.seconds, 0, MAX_SECONDS) or not schema.Number(edge.risk, 0, 1)
        or not schema.Number(edge.uncertainty, 0, 1) or not schema.List(edge.zones, 16) then return false end
    if #edge.zones == 0 then return false end
    for _, zone in ipairs(edge.zones) do if not schema.ID(zone) then return false end end
    if edge.mode == "hearth" then return edge.from == "*" end
    if not graph.nodes[edge.from] then return false end
    if edge.mode == "walk" then return true end
    if edge.mode == "flight" then return token(edge.flightFrom) and token(edge.flightTo) end
    return edge.mode == "transport" and token(edge.transport) and schema.Number(edge.period, 1, MAX_SECONDS)
        and schema.Number(edge.offset, 0, edge.period)
end

local function readNodes(graph, rows)
    if not schema.List(rows, MAX_NODES) then return nil, "graph node limit" end
    for _, row in ipairs(rows) do
        local node = schema.Copy(row)
        if not node or not token(node.id) or not schema.ID(node.zoneID) or graph.nodes[node.id] then return nil, "invalid graph node" end
        if node.mapID ~= nil and (not schema.ID(node.mapID) or not schema.Number(node.x, 0, 1)
            or not schema.Number(node.y, 0, 1)) then return nil, "invalid graph location" end
        graph.nodes[node.id], graph.adj[node.id] = node, {}
    end
    return true
end

local function readEdges(graph, rows)
    if not schema.List(rows, MAX_EDGES) then return nil, "graph edge limit" end
    local ids = {}
    for _, row in ipairs(rows) do
        local edge = schema.Copy(row)
        if not edge or not edgeValid(edge, graph) or ids[edge.id] then return nil, "invalid graph edge" end
        ids[edge.id] = true
        local list = edge.mode == "hearth" and graph.hearth or graph.adj[edge.from]
        list[#list + 1] = edge
    end
    for _, list in pairs(graph.adj) do table.sort(list, function(a, b) return a.id < b.id end) end
    table.sort(graph.hearth, function(a, b) return a.id < b.id end)
    return true
end

local function flags(values, max, numeric)
    if values == nil then return {} end
    if not schema.PlainTable(values) then return nil end
    local result, count = {}, 0
    for key, value in pairs(values) do
        count = count + 1
        if RikUI.Secret.IsSecret(value) or count > max or (numeric and not schema.ID(key)) or (not numeric and not token(key))
            or (value ~= true and value ~= false) then return nil end
        result[key] = value
    end
    return result
end

local function context(graph, raw, input)
    if not schema.PlainTable(raw) or not same(raw.identity, graph.identity)
        or not schema.Number(raw.departure, 0, MAX_CLOCK) then return nil end
    local policy = schema.Copy(input or {})
    if not policy then return nil end
    local state = { departure = raw.departure, flights = flags(raw.flights, MAX_NODES),
        transport = flags(raw.transport, MAX_NODES), hearthBind = raw.hearthBind,
        hearthReadyAt = raw.hearthReadyAt, hearthDisabled = raw.hearthDisabled }
    if not state.flights or not state.transport then return nil end
    policy.maxSeconds, policy.maxRisk, policy.maxUncertainty = policy.maxSeconds or 1800, policy.maxRisk or .5, policy.maxUncertainty or .5
    policy.maxLabels, policy.maxWork = policy.maxLabels or MAX_LABELS, policy.maxWork or MAX_WORK
    if not schema.Number(policy.maxSeconds, 0, MAX_SECONDS) or not schema.Number(policy.maxRisk, 0, 100)
        or not schema.Number(policy.maxUncertainty, 0, 100) or not schema.Integer(policy.maxLabels, 1, MAX_LABELS)
        or not schema.Integer(policy.maxWork, 1, MAX_WORK) then return nil end
    policy.avoids = flags(policy.avoids, 64, true)
    if not policy.avoids then return nil end
    return state, policy
end

local function less(a, b)
    if a.time ~= b.time then return a.time < b.time end
    return a.serial < b.serial
end

local function push(heap, label)
    local index = #heap + 1
    while index > 1 do
        local parent = math.floor(index / 2)
        if not less(label, heap[parent]) then break end
        heap[index], index = heap[parent], parent
    end
    heap[index] = label
end

local function pop(heap)
    local first, last = heap[1], table.remove(heap)
    if #heap == 0 then return first end
    local index = 1
    while index * 2 <= #heap do
        local child = index * 2
        if child < #heap and less(heap[child + 1], heap[child]) then child = child + 1 end
        if not less(heap[child], last) then break end
        heap[index], index = heap[child], child
    end
    heap[index] = last
    return first
end

local function omission(job, reason)
    job.omitted[reason] = (job.omitted[reason] or 0) + 1
    return nil
end

local function edgeCost(job, label, edge)
    if edge.source.authority ~= "verified" then return omission(job, "reference-connection") end
    for _, zone in ipairs(edge.zones) do if job.policy.avoids[zone] then return omission(job, "avoided-area") end end
    if job.policy.avoids[job.graph.nodes[edge.to].zoneID] then return omission(job, "avoided-area") end
    local state, wait = job.state, 0
    local now = state.departure + label.time
    if edge.mode == "flight" then
        if state.flights[edge.flightFrom] ~= true or state.flights[edge.flightTo] ~= true then return omission(job, "flight-locked-or-unknown") end
    elseif edge.mode == "transport" then
        if state.transport[edge.transport] ~= true then return omission(job, "transport-unavailable-or-unknown") end
        wait = (edge.offset - now) % edge.period
    elseif edge.mode == "hearth" then
        if label.hearth or state.hearthDisabled or state.hearthBind ~= edge.to
            or not schema.Number(state.hearthReadyAt, 0, MAX_CLOCK) then return omission(job, "hearth-unavailable-or-unknown") end
        wait = math.max(0, state.hearthReadyAt - now)
    end
    return edge.seconds + wait, wait
end

local function dominates(a, b)
    return a.alive and a.hearth == b.hearth and a.time <= b.time and a.risk <= b.risk and a.uncertainty <= b.uncertainty
end

local function admit(job, label)
    local labels = job.labels[label.node] or {}
    for _, old in ipairs(labels) do if dominates(old, label) then return true end end
    if job.allocated >= job.policy.maxLabels then job.exhausted = true; return nil end
    for _, old in ipairs(labels) do if dominates(label, old) then old.alive = false end end
    job.allocated = job.allocated + 1
    label.serial = job.allocated
    labels[#labels + 1], job.labels[label.node] = label, labels
    push(job.heap, label)
    if label.node == job.to and (not job.best or less(label, job.best)) then job.best = label end
    return true
end

local function relax(job, label, edge)
    local cost, wait = edgeCost(job, label, edge)
    if not cost then return end
    local nextLabel = { node = edge.to, time = label.time + cost, risk = label.risk + edge.risk,
        uncertainty = label.uncertainty + edge.uncertainty, hearth = label.hearth or edge.mode == "hearth",
        hearthAt = label.hearthAt, previous = label, edge = edge, wait = wait, alive = true }
    if edge.mode == "hearth" then nextLabel.hearthAt = job.state.departure + label.time + wait end
    if nextLabel.time > job.policy.maxSeconds or nextLabel.risk > job.policy.maxRisk
        or nextLabel.uncertainty > job.policy.maxUncertainty then omission(job, "cost-or-risk-limit"); return end
    admit(job, nextLabel)
end

local function finish(job, status, label)
    local result = { status = status, graphRevision = job.graph.revision, path = {}, omitted = schema.Clone(job.omitted),
        metrics = { work = job.work, labels = job.allocated }, optimalInGraph = status == "known" }
    if label then
        result.seconds, result.risk, result.uncertainty = label.time, label.risk, label.uncertainty
        result.hearthUsed, result.hearthAt = label.hearth, label.hearthAt
        while label.edge do
            local edge = label.edge
            result.path[#result.path + 1] = { id = edge.id, from = label.previous.node, to = label.node,
                mode = edge.mode, seconds = label.time - label.previous.time, wait = label.wait, source = schema.Clone(edge.source) }
            label = label.previous
        end
    end
    for index = 1, math.floor(#result.path / 2) do
        local other = #result.path - index + 1
        result.path[index], result.path[other] = result.path[other], result.path[index]
    end
    job.result = result
    return schema.Clone(result)
end

local function step(job, budget)
    if job.result then return schema.Clone(job.result) end
    if not schema.Integer(budget, 1, 128) then return nil, "invalid travel slice budget" end
    for _ = 1, budget do
        if job.work >= job.policy.maxWork or job.exhausted then return finish(job, "budget-exhausted", job.best) end
        job.work = job.work + 1
        if not job.current then
            if #job.heap == 0 then return finish(job, "no-known-route") end
            local label = pop(job.heap)
            if label.alive then
                if label.node == job.to then return finish(job, "known", label) end
                job.current, job.edgeIndex = label, 1
            end
        else
            local edges = job.graph.adj[job.current.node]
            local edge = edges[job.edgeIndex] or job.graph.hearth[job.edgeIndex - #edges]
            if edge then relax(job, job.current, edge); job.edgeIndex = job.edgeIndex + 1
            else job.current = nil end
        end
    end
    if job.work >= job.policy.maxWork or job.exhausted then return finish(job, "budget-exhausted", job.best) end
end

local function begin(graph, from, to, raw, policy)
    if not token(from) or not token(to) or not graph.nodes[from] or not graph.nodes[to] then return nil, "unknown graph endpoint" end
    local state, limits = context(graph, raw, policy)
    if not state then return nil, "unknown travel context" end
    local job = { graph = graph, state = state, policy = limits, from = from, to = to,
        heap = {}, labels = {}, work = 0, allocated = 0, omitted = {} }
    admit(job, { node = from, time = 0, risk = 0, uncertainty = 0, hearth = false, alive = true })
    return { Step = function(_, budget) return step(job, budget or 64) end }
end

function travel.New(identity, revision, nodes, edges)
    local content = schema.Copy(identity)
    if not content or not schema.Identity(content) or not token(revision) then return nil, "invalid travel identity" end
    local graph = { identity = content, revision = revision, nodes = {}, adj = {}, hearth = {} }
    local ok, reason = readNodes(graph, nodes)
    if not ok then return nil, reason end
    ok, reason = readEdges(graph, edges)
    if not ok then return nil, reason end
    return {
        Identity = function() return schema.Clone(content) end,
        Revision = function() return revision end,
        Begin = function(_, ...) return begin(graph, ...) end,
        Estimate = function(_, ...)
            local job, problem = begin(graph, ...)
            if not job then return { status = "unknown", reason = problem, path = {} } end
            while true do local result = job:Step(128); if result then return result end end
        end,
    }
end
