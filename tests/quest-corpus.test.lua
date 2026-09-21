-- Corpus releases and observation exports have their own bounds and provenance.
return function(check)
    local previous = RikUI
    RikUI = { Secret = { IsSecret = function(v) return v == "SECRET" end } }
    local ok, reason = pcall(function()
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-evidence.lua")
        dofile("src/modules/questplanner/quest-corpus.lua")
        local p = RikUI.QuestPlanner
        local identity = { product = "forever", build = "1.60.1.69913", locale = "enUS" }
        local function source(id, status, assertions)
            return { id = id, product = identity.product, build = identity.build, locale = identity.locale,
                authority = "verified", dataset = "fixture", status = status or "active",
                mode = "snapshot", assertions = assertions or 1,
                revision = "fixture-v1", sha256 = string.rep("a", 64), parser = "fixture-v1",
                uri = "fixture://synthetic", terms = "Original test fixture" }
        end
        local function row(id, field, value, sourceID)
            return { questID = id, field = field, value = value, source = sourceID or "one" }
        end
        local a, b = source("one", "superseded"), source("two")
        b.supersedes = "one"
        local build = assert(p.Corpus.New(identity, { a, b }, "release-1"))
        check("unpublished corpus unavailable", build:Result() == nil)
        assert(build:Append({ row(1, "title", "Old"), row(1, "title", "Corrected", "two") }))
        local corpus = assert(build:Finish())
        check("explicit source supersession corrects field", corpus:Resolve(1, "title").value == "Corrected")
        check("retired source remains auditable", #corpus:Sources() == 2)
        b.status = "retracted"
        check("source manifests are detached", corpus:Sources()[2].status == "active")
        local missing = source("bad"); missing.sha256 = nil
        check("unpinned sources rejected", not p.Corpus.New(identity, { missing }, "bad"))
        local dangling = source("dangling"); dangling.supersedes = "absent"
        check("dangling supersession rejected", not p.Corpus.New(identity, { dangling }, "bad"))
        local other = source("other"); other.build = "old"
        check("cross-build manifest rejected", not p.Corpus.New(identity, { other }, "bad"))
        local ref = source("reference"); ref.authority = "reference"
        local second = assert(p.Corpus.New(identity, { source("one", nil, 3), source("two"), ref }, "release-2"))
        assert(second:Append({ row(2, "title", "A"), row(2, "title", "B", "two"),
            row(3, "title", "Reference", "reference"), row(2, "zoneID", 27), row(3, "zoneID", 27) }))
        local book = assert(second:Finish())
        check("active verified disagreements survive", book:Resolve(2, "title").status == "conflict")
        check("reference never gains authority", book:Resolve(3, "title").status == "unknown")
        local report = book:Coverage(27)
        check("coverage discloses unknown world denominator", report.denominator == "unknown" and report.catalogued == 2)
        check("coverage reports conflicts and references", report.fields.title.conflict == 1 and report.fields.title.unknown == 1)
        local bad = assert(p.Corpus.New(identity, { source("one") }, "bad"))
        check("bad append fails candidate", not bad:Append({ row(9, "baseXP", -1) }))
        check("failed candidate never publishes", not bad:Finish())
        local wide = assert(p.Corpus.New(identity, { source("one", nil, 5000) }, "wide"))
        for first = 1, 5000, 64 do
            local rows = {}
            for id = first, math.min(first + 63, 5000) do rows[#rows + 1] = row(id, "level", 7) end
            assert(wide:Append(rows))
        end
        local large = assert(wide:Finish())
        check("corpus exceeds prototype catalogue assertion cap safely", large:Resolve(5000, "level").value == 7)
        check("bounded append batch enforced", not wide:Append({}))
        check("unknown quests remain unknown", large:Resolve(99999, "title").status == "unknown")
        local incomplete = assert(p.Corpus.New(identity, { source("one", nil, 2) }, "incomplete"))
        assert(incomplete:Append({ row(1, "title", "Only one") }))
        check("partial replacement snapshot cannot publish", not incomplete:Finish())
        local retired = source("retired", "retracted"); retired.reason = "invalid extraction"
        local retract = assert(p.Corpus.New(identity, { retired }, "retracted"))
        local retracted = assert(retract:Finish())
        check("retraction leaves unknown facts and retains reason", retracted:Resolve(1, "title").status == "unknown"
            and retracted:Sources()[1].reason == "invalid extraction")
        local cross = source("next"); cross.dataset = "other"; cross.supersedes = "one"
        check("cross-dataset retirement forbidden", not p.Corpus.New(identity, { a, cross }, "cross"))
        local tooMany = {}; for n = 1, 65 do tooMany[n] = row(n, "level", 1) end
        local limited = assert(p.Corpus.New(identity, { source("one", nil, 65) }, "limited"))
        check("append work bounded before ingestion", not limited:Append(tooMany))
        check("reference-only subset visible", report.fields.title.referenceOnly == 1)
        check("unknown zone records not assigned by title", large:Coverage(27).catalogued == 0
            and large:Coverage(27).unassignedZone == 5000)
        dofile("src/modules/questplanner/quest-transfer.lua")
        local observation = { identity = identity, generation = 1, coverage = "log-complete",
            observedCount = 1, reportedCount = 1, order = { 98319 },
            quests = { [98319] = { id = 98319, title = "A\tB\nC", level = 7, unknown = {},
                objectivesComplete = false, objectives = {} } } }
        local wire = assert(p.Transfer.Encode(observation))
        local restored = assert(p.Transfer.Decode(wire))
        check("observation transport roundtrips control characters and false", restored.quests[98319].title == "A\tB\nC"
            and restored.quests[98319].objectivesComplete == false)
        check("wire is separate versioned observation format", wire:match("^RIKQ1:") ~= nil)
        check("transfer is printable and imported observations are untrusted", not wire:find("[^%w:]")
            and restored.origin == "imported-untrusted")
        observation.quests[98319].title = "é |Hlink|h : " .. string.char(0)
        local special = assert(p.Transfer.Decode(assert(p.Transfer.Encode(observation))))
        check("unicode markup and NUL survive printable transport", special.quests[98319].title == observation.quests[98319].title)
        check("corruption rejected", not p.Transfer.Decode(wire .. "x"))
        check("oversized wire rejected", not p.Transfer.Decode(string.rep("x", 131073)))
        observation.quests[98319].title = string.rep("x", 2049)
        check("oversized observation field rejected", not p.Transfer.Encode(observation))
    end)
    RikUI = previous
    check("corpus/transfer fixture completes", ok, reason)
end
