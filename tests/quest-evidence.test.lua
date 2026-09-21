-- Evidence must never turn an Era assumption into a Forever fact.
return function(check)
    local previous = RikUI
    RikUI = { Secret = { IsSecret = function(value) return value == "SECRET" end } }
    local ok, reason = pcall(function()
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-evidence.lua")
        local evidence = RikUI.QuestPlanner.Evidence
        local identity = { product = "forever", build = "1.60.1.69913", locale = "enUS" }
        local book = assert(evidence.New(identity))
        local function source(id, authority)
            return { id = id, product = identity.product, build = identity.build, locale = identity.locale, authority = authority or "verified" }
        end
        local function add(field, value, id, authority)
            return book:Add(900001, field, value, source(id, authority))
        end
        check("absent quest and prerequisites are unknown", book:Resolve(900001, "prerequisites").status == "unknown")
        local era = source("era")
        era.product = "classic-era"
        check("Era source cannot enter Forever catalogue", not book:Add(7, "title", "Old title", era))
        local oldBuild = source("old-build")
        oldBuild.build = "1.60.1.69893"
        check("different build never silently falls back", not book:Add(7, "title", "Old title", oldBuild))
        local otherLocale = source("locale")
        otherLocale.locale = "deDE"
        check("localized facts cannot contaminate another locale", not book:Add(7, "title", "Titel", otherLocale))
        check("catalogue must declare locale", not evidence.New({ product = "forever", build = "1.60.1.69913" }))
        check("reference can be retained", add("title", "Provisional title", "reference", "reference"))
        local provisional = book:Resolve(900001, "title")
        check("unverified reference stays unknown with evidence", provisional.status == "unknown"
            and provisional.reason == "unverified" and #provisional.evidence == 1 and provisional.value == nil)
        check("Forever-only quest needs no Era record", add("title", "New Forever quest", "forever"))
        local known = book:Resolve(900001, "title")
        check("verified fact wins while reference remains inspectable", known.status == "known"
            and known.value == "New Forever quest" and #known.evidence == 2)
        check("contradicting verified source retained", add("title", "Changed quest", "second"))
        local conflict = book:Resolve(900001, "title")
        check("equal authority contradiction is explicit", conflict.status == "conflict" and conflict.value == nil)
        check("duplicate source/value is idempotent", add("title", "Changed quest", "second")
            and #book:Resolve(900001, "title").evidence == 3)
        check("rewriting evidence source is rejected", not add("title", "Another change", "second"))
        check("authority cannot be silently upgraded for the same source",
            not add("title", "Provisional title", "reference", "verified"))
        check("equivalent NPC sets do not conflict", add("startNPCs", { 9, 2, 9 }, "npc1")
            and add("startNPCs", { 2, 9 }, "npc2") and book:Resolve(900001, "startNPCs").status == "known")
        check("false is a known fact", add("repeatable", false, "repeat")
            and book:Resolve(900001, "repeatable").value == false)
        local requirement = { op = "all", args = { { op = "completed", questID = 7 }, { op = "active", questID = 8 } } }
        check("requirements preserve active versus turned-in predicates", add("prerequisites", requirement, "chain"))
        requirement.args[1].questID = 99
        local resolved = book:Resolve(900001, "prerequisites")
        check("input mutation cannot rewrite evidence", resolved.value.args[2].questID == 7)
        resolved.value.args[2].questID = 88
        resolved.evidence[1].source.id = "changed"
        check("output mutation cannot rewrite evidence", book:Resolve(900001, "prerequisites").value.args[2].questID == 7
            and book:Resolve(900001, "prerequisites").evidence[1].source.id == "chain")
        check("unordered prerequisite operands do not conflict",
            add("prerequisites", { op = "all", args = { { op = "active", questID = 8 },
                { op = "completed", questID = 7 } } }, "equivalent")
            and book:Resolve(900001, "prerequisites").status == "known")
        check("empty conjunction is not silently no prerequisites",
            not book:Add(8, "prerequisites", { op = "all", args = {} }, source("empty")))
        check("no prerequisites requires explicit assertion",
            book:Add(8, "prerequisites", { op = "always" }, source("none")))
        check("unknown fields rejected", not add("complete", true, "player-state"))
        check("unknown authority rejected", not add("level", 12, "bad-authority", "guess"))
        check("invalid ids rejected", not book:Add(0 / 0, "level", 12, source("nan"))
            and not book:Add(1.5, "level", 12, source("fraction")))
        check("nonfinite fields rejected", not add("baseXP", math.huge, "infinite"))
        check("secret field rejected", not add("title", "SECRET", "secret"))
        local cycle = { op = "all", args = {} }
        cycle.args[1] = cycle
        check("cyclic input rejected without throwing", not add("prerequisites", cycle, "cycle"))
        check("oversized strings rejected", not add("title", string.rep("x", 2049), "long"))
        check("metatable input rejected", not add("prerequisites", setmetatable({ op = "always" }, {}), "meta"))
        check("location bounds enforced", not add("locations", { { mapID = 1, x = 1.2, y = 0.5 } }, "outside"))
        check("sparse lists rejected", not add("startNPCs", { [1] = 1, [3] = 3 }, "sparse"))
        for index = 1, 8 do assert(book:Add(42, "level", index, source("limit-" .. index))) end
        check("per-field evidence bound is explicit", not book:Add(42, "level", 9, source("limit-9")))
        check("duplicate at full capacity remains idempotent", book:Add(42, "level", 1, source("limit-1"))
            and #book:Resolve(42, "level").evidence == 8)
        check("rejected evidence leaves prior facts intact", book:Resolve(42, "level").status == "conflict"
            and #book:Resolve(42, "level").evidence == 8)
        local nested = { op = "always" }
        for _ = 1, 12 do nested = { op = "all", args = { nested } } end
        check("excessive depth rejected", not add("prerequisites", nested, "deep"))
        local another = assert(evidence.New({ product = "forever", build = "1.60.1.69914", locale = "enUS" }))
        check("catalogues do not share mutable state", another:Resolve(900001, "title").status == "unknown")
        identity.build = "mutated"
        check("identity is copied", book:Identity().build == "1.60.1.69913")
    end)
    RikUI = previous
    if not ok then error(reason) end
end
