-- Synthetic logic fixtures, not Forever quest rules.
return function(check)
    local previous = RikUI
    RikUI = { Secret = { IsSecret = function(v) return v == "SECRET" end } }
    local ok, reason = pcall(function()
        for _, name in ipairs({ "quest-schema", "quest-evidence", "quest-eligibility" }) do
            dofile("src/modules/questplanner/" .. name .. ".lua")
        end
        local p = RikUI.QuestPlanner
        local identity = { product = "forever", build = "1.60.1.69913", locale = "enUS" }
        local source = { id = "synthetic", product = identity.product, build = identity.build, locale = identity.locale, authority = "verified" }
        local book = assert(p.Evidence.New(identity))
        assert(book:Add(20, "prerequisites", { op = "completed", questID = 10 }, source))
        assert(book:Add(20, "requirements", { op = "all", args = {
            { op = "class", value = 1 }, { op = "race", value = 3 }, { op = "faction", value = "Alliance" },
            { op = "levelAtLeast", value = 7 }, { op = "not", arg = { op = "completed", questID = 30 } } } }, source))
        local state = { identity = identity, fresh = true, active = {}, objectivesComplete = {}, failed = {},
            turnedIn = { [10] = false, [20] = false, [30] = false }, logComplete = true,
            class = 1, race = 3, faction = "Alliance", level = 7, logCount = 9, logCapacity = 25 }
        local action = { questID = 20, kind = "pickup" }
        check("skipped prerequisite blocks pickup", p.Eligibility.Evaluate(action, state, book).status == "blocked")
        state.objectivesComplete[10] = true
        check("objectives complete cannot unlock successor", p.Eligibility.Evaluate(action, state, book).status == "blocked")
        state.turnedIn[10] = true
        check("turned-in predecessor unlocks class quest", p.Eligibility.Evaluate(action, state, book).status == "eligible")
        state.class = 2
        check("wrong class blocks pickup", p.Eligibility.Evaluate(action, state, book).status == "blocked")
        state.class = 1; state.level = 6
        check("dungeon leveling changes eligibility on new state", p.Eligibility.Evaluate(action, state, book).status == "blocked")
        state.level = 7; state.logCount = 25
        check("full log blocks pickup", p.Eligibility.Evaluate(action, state, book).status == "blocked")
        state.logCapacity = nil
        check("unknown capacity remains unknown", p.Eligibility.Evaluate(action, state, book).status == "unknown")
        state.logCapacity = 25; state.logCount = 9; state.turnedIn[30] = nil
        check("unknown exclusion stays unknown under NOT", p.Eligibility.Evaluate(action, state, book).status == "unknown")
        state.turnedIn[30] = false
        local values = { "true", "false", "unknown" }
        for _, left in ipairs(values) do for _, right in ipairs(values) do
            state.flags = { a = left == "true" and true or (left == "false" and false or nil),
                b = right == "true" and true or (right == "false" and false or nil) }
            if left == "false" then state.flags.a = false end
            if right == "false" then state.flags.b = false end
            local args = { { op = "flag", value = "a" }, { op = "flag", value = "b" } }
            local andExpected = (left == "false" or right == "false") and "false"
                or ((left == "true" and right == "true") and "true" or "unknown")
            local orExpected = (left == "true" or right == "true") and "true"
                or ((left == "false" and right == "false") and "false" or "unknown")
            check("AND truth table " .. left .. right, p.Eligibility.Condition({ op = "all", args = args }, state) == andExpected)
            check("OR truth table " .. left .. right, p.Eligibility.Condition({ op = "any", args = args }, state) == orExpected)
        end end
        state.active[20], state.failed[20], state.objectivesComplete[20] = true, false, false
        check("accepted quest can progress without known pickup requirements", p.Eligibility.Evaluate({ questID = 20, kind = "objective" }, state).status == "eligible")
        check("unfinished quest cannot turn in", p.Eligibility.Evaluate({ questID = 20, kind = "turnin" }, state).status == "blocked")
        state.objectivesComplete[20] = true
        check("ready quest can turn in", p.Eligibility.Evaluate({ questID = 20, kind = "turnin" }, state).status == "eligible")
        state.fresh = false
        check("stale state never actionable", p.Eligibility.Evaluate({ questID = 20, kind = "turnin" }, state).status == "unknown")
        state.fresh = true; state.origin = "imported-untrusted"
        check("import never masquerades as live", p.Eligibility.Evaluate({ questID = 20, kind = "turnin" }, state).status == "unknown")
        state.origin = nil; state.identity = { product = "forever", build = "other", locale = "enUS" }
        check("identity mismatch blocks world-rule use", p.Eligibility.Evaluate(action, state, book).status == "unknown")
        state.identity = identity; state.active[20] = nil; state.logComplete = false
        check("absence from partial log stays unknown", p.Eligibility.Evaluate(action, state, book).status == "unknown")
        local cycle = { op = "not" }; cycle.arg = cycle
        check("cyclic condition is unknown safely", p.Eligibility.Condition(cycle, state) == "unknown")
        check("invalid action kind is unknown", p.Eligibility.Evaluate({ questID = 20, kind = "abandon" }, state).status == "unknown")
        state.identity = identity; state.logComplete = true; state.turnedIn[20] = true
        assert(book:Add(20, "repeatable", false, source))
        check("nonrepeatable turn-in cannot be rewarded again", p.Eligibility.Evaluate(action, state, book).status == "blocked")
        local changed = assert(p.Evidence.New(identity))
        assert(changed:Add(20, "prerequisites", { op = "completed", questID = 99 }, source))
        assert(changed:Add(20, "requirements", { op = "always" }, source))
        state.turnedIn[20], state.turnedIn[99] = false, false
        check("changed chain re-evaluates the replacement rule", p.Eligibility.Evaluate(action, state, changed).status == "blocked")
        local conflicting = { id = "second", product = identity.product, build = identity.build, locale = identity.locale, authority = "verified" }
        assert(changed:Add(20, "prerequisites", { op = "always" }, conflicting))
        check("conflicting prerequisite never authorizes pickup", p.Eligibility.Evaluate(action, state, changed).status == "unknown")
        local snap = { identity = identity, generation = 1, order = {20}, reportedCount = 1, coverage = "log-partial",
            quests = { [20] = { id = 20, failed = false, objectivesComplete = true } } }
        local derived = assert(p.Eligibility.FromSnapshot(snap, {state = "partial"}, { level = 7, logCapacity = 25 }, { [10] = true }))
        check("snapshot adapter preserves partial absence and true turn-in history",
            derived.active[20] and not derived.logComplete and derived.turnedIn[10] == true and derived.turnedIn[20] == nil)
        derived.active[20] = false
        check("snapshot adapter detaches character state", snap.quests[20].objectivesComplete == true)
        local normalized = assert(p.Schema.Field("requirements", { op = "any", args = {
            { op = "class", value = 1 }, { op = "class", value = 2 } } }))
        check("normalization preserves distinct class predicates", #normalized.args == 2)
    end)
    RikUI = previous
    check("eligibility fixture completes", ok, reason)
end
