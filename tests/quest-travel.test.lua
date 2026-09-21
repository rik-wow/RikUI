-- Original directed graph fixtures; coordinates do not assert walkability.
return function(check)
    local previous = RikUI
    RikUI = { Secret = { IsSecret = function(v) return v == "SECRET" end } }
    local ok, reason = pcall(function()
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-travel.lua")
        local p = RikUI.QuestPlanner
        local identity = { product = "forever", build = "1.60.1.69913", locale = "enUS" }
        local provenance = { id = "synthetic", product = identity.product, build = identity.build, locale = identity.locale, authority = "verified" }
        local nodes = { {id = "a", zoneID = 1}, {id = "b", zoneID = 1}, {id = "c", zoneID = 2}, {id = "d", zoneID = 3} }
        local function edge(id, from, to, seconds, mode)
            return { id = id, from = from, to = to, seconds = seconds, mode = mode or "walk", risk = 0, uncertainty = 0, zones = {1,2}, source = provenance }
        end
        local ab, bc, ac = edge("ab", "a", "b", 10), edge("bc", "b", "c", 10), edge("ac", "a", "c", 50)
        local graph = assert(p.Travel.New(identity, "fixture-1", nodes, {ab,bc,ac}))
        local state = { identity = identity, departure = 0, flights = {}, transport = {} }
        local result = graph:Estimate("a", "c", state)
        check("directed cost chooses traversable path", result.status == "known" and result.seconds == 20 and #result.path == 2)
        check("reverse is not inferred", graph:Estimate("c", "a", state).status == "no-known-route")
        check("proximity never creates a connection", graph:Estimate("a", "d", state).status == "no-known-route")
        check("avoid regions filter intermediate traversal", graph:Estimate("a", "c", state, {avoids = {[2]=true}}).status == "no-known-route")
        ab.seconds = 1000; nodes[2].zoneID = 99
        check("graph detaches input", graph:Estimate("a", "c", state).seconds == 20)
        result.path[1].seconds = 999
        check("result cannot mutate graph", graph:Estimate("a", "c", state).seconds == 20)
        local flight = edge("flight", "a", "c", 5, "flight")
        flight.flightFrom, flight.flightTo = "a", "c"
        graph = assert(p.Travel.New(identity, "fixture-2", nodes, {flight,ac}))
        check("locked flight omitted", graph:Estimate("a", "c", state).seconds == 50)
        state.flights.a, state.flights.c = true, true
        check("unlock invalidates costs without stale cache", graph:Estimate("a", "c", state).seconds == 5)
        state.flights.c = false
        check("unavailable flight never reused from cache", graph:Estimate("a", "c", state).seconds == 50)
        local boat = edge("boat", "a", "c", 10, "transport")
        boat.period, boat.offset, boat.transport = 60, 0, "boat"
        graph = assert(p.Travel.New(identity, "fixture-3", nodes, {boat}))
        state.transport.boat, state.departure = true, 1
        check("periodic transport waits until departure", graph:Estimate("a", "c", state).seconds == 69)
        state.departure = 0
        check("departure time changes cost", graph:Estimate("a", "c", state).seconds == 10)
        state.transport.boat = nil
        check("unknown transport availability remains no known route", graph:Estimate("a", "c", state).status == "no-known-route")
        local hearth = edge("hearth", "*", "c", 10, "hearth")
        graph = assert(p.Travel.New(identity, "fixture-4", nodes, {hearth}))
        state.hearthBind, state.hearthReadyAt, state.departure = "c", 100, 0
        check("hearth waits for known cooldown", graph:Estimate("a", "c", state).seconds == 110)
        state.hearthBind = "b"
        check("hearth bind mismatch rejected", graph:Estimate("a", "c", state).status == "no-known-route")
        local fast, slow, last = edge("fast", "a", "b", 1), edge("slow", "a", "b", 3), edge("last", "b", "c", 1)
        fast.risk, slow.risk, last.risk = .8, .1, .3
        graph = assert(p.Travel.New(identity, "risk", nodes, {fast,slow,last}))
        check("slower safe label survives earliest unsafe route", graph:Estimate("a", "c", state, {maxRisk = 1}).seconds == 4)
        check("total time cap includes waiting and movement", graph:Estimate("a", "c", state, {maxSeconds = 2}).status == "no-known-route")
        local job = assert(graph:Begin("a", "c", state, {maxWork = 1}))
        local limited = job:Step(1)
        check("search budget exhaustion is explicit", limited and limited.status == "budget-exhausted")
        local ref = edge("ref", "a", "d", 1); ref.source = p.Schema.Clone(provenance); ref.source.authority = "reference"
        graph = assert(p.Travel.New(identity, "reference", nodes, {ref}))
        check("reference edge cannot establish traversal", graph:Estimate("a", "d", state).status == "no-known-route")
        state.identity = {product = "forever", build = "different", locale = "enUS"}
        check("graph identity isolates builds", graph:Estimate("a", "d", state).status == "unknown")
        state.identity = identity; state.hearthBind = "c"
        graph = assert(p.Travel.New(identity, "hearth-effect", nodes, {hearth}))
        local consumed = graph:Estimate("a", "c", state)
        check("hearth effect records consumption time", consumed.hearthUsed and consumed.hearthAt == 100)
        state.hearthDisabled = true
        check("simulated subsequent leg cannot reset hearth", graph:Estimate("a", "c", state).status == "no-known-route")
        state.hearthDisabled = nil
        local zero, back = edge("zero", "a", "b", 0), edge("back", "b", "a", 0)
        local endEdge = edge("end", "b", "c", 2)
        graph = assert(p.Travel.New(identity, "zero-cycle", nodes, {zero,back,endEdge}))
        check("zero cycles deduplicate equal labels", graph:Estimate("a", "c", state).seconds == 2)
        local sliced = assert(graph:Begin("a", "c", state)); local slicedResult
        repeat slicedResult = sliced:Step(1) until slicedResult
        check("slice size does not change deterministic answer", slicedResult.seconds == 2 and #slicedResult.path == 2)
        local risky = edge("corridor", "a", "c", 1); risky.zones = {1,3,2}
        graph = assert(p.Travel.New(identity, "corridor", nodes, {risky}))
        check("avoids include intermediate traversed zones", graph:Estimate("a", "c", state, {avoids={[3]=true}}).status == "no-known-route")
        graph = assert(p.Travel.New(identity, "incumbent", nodes, {edge("1", "a", "c", 50), edge("2", "a", "b", 1), endEdge}))
        local incumbent = graph:Estimate("a", "c", state, {maxWork = 2})
        check("discovered terminal stays limited without popped proof", incumbent.status == "budget-exhausted"
            and incumbent.seconds == 50 and not incumbent.optimalInGraph)
        local bad = edge("bad", "a", "b", -1)
        check("negative travel costs rejected", not p.Travel.New(identity, "bad", nodes, {bad}))
    end)
    RikUI = previous
    check("travel fixture completes", ok, reason)
end
