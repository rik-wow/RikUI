return function(report)
local old,oldQuest,oldTime=RikUI,C_QuestLog,GetTime
local ok,err=pcall(function()
local cases, checks = 0, 0
local clock, calls, rereads, E
local function check(value, message) checks = checks + 1; assert(value, message) end
local function fresh()
    clock, calls, rereads = 0, {}, 0
    _G.GetTime = function() return clock end
    _G.C_QuestLog = {RequestLoadQuestByID = function(id) calls[#calls + 1] = id end}
    _G.RikUI = {Secret = {IsSecret = function() return false end}}
    dofile('src/modules/questplanner/quest-schema.lua')
    RikUI.QuestPlanner.Context = {Call = function(fn, ...) return pcall(fn, ...) end}
    RikUI.QuestPlanner.Request = function() rereads = rereads + 1 end
    dofile('src/modules/questplanner/quest-enrichment.lua')
    E = RikUI.QuestPlanner.Enrichment
    cases = cases + 1
end
local function snapshot(count)
    local result = {origin = 'native', identity = {product = 'forever', build = '16001', locale = 'enUS'}, quests = {}, order = {}}
    for id = 1, count do result.order[id] = id; result.quests[id] = {title = nil, unknown = {title = true, objectives = true}} end
    return result
end
fresh()
local s = snapshot(80)
E.Ensure(s)
check(E.Step() == 2 and #calls == 2, 'two requests first step')
check(E.Step() == 0, 'two in-flight cap')
check(s.quests[1].title == nil and rereads == 0, 'submitted request not metadata')
for _ = 1, 20 do
    for id = 1, 80 do E.OnResult(id, true) end
    E.Step()
end
check(#calls == 40 and E.Status().exhausted, '40 request session cap')
check(rereads == 40 and s.quests[1].title == nil and s.quests[1].objectives == nil, 'success rereads without mutation')
check(E.Status().requests == 40 and E.Status().accepted == 40, 'auditable submitted and accepted counts')
check(#E.Status().log <= 80, 'bounded log')
local copy = E.Status(); copy.log[1].status = 'mutation'; check(E.Status().log[1].status ~= 'mutation', 'status owns log copies')
print('cap case: requested=' .. #calls .. ' rereads=' .. rereads)

fresh(); s = snapshot(1); E.Ensure(s); E.Step(); E.OnResult(1, false)
for _ = 1, 10 do E.Ensure(snapshot(1)); E.Step() end
check(#calls == 1, 'new snapshots do not reset retry cooldown')
clock = 29; E.Step(); check(#calls == 1, 'retry before cooldown refused')
clock = 30; E.Step(); check(#calls == 2, 'one bounded retry')
E.OnResult(1, false); clock = 60; E.Ensure(snapshot(1)); E.Step(); check(#calls == 2, 'two attempt cap')
check(E.Status().failed == 2, 'failed callback count')
print('retry case: requested=' .. #calls .. ' rereads=' .. rereads)

fresh(); s = snapshot(1); s.origin = 'imported-untrusted'
check(E.Ensure(s) == false and E.Step() == 0 and #calls == 0, 'imports cannot request')
s = snapshot(1); s.quests[1].origin = 'imported-untrusted'; E.Ensure(s); E.Step(); check(#calls == 0, 'imported quest cannot request')
s = snapshot(1); s.quests[1] = {title = 'Known', objectives = {}, unknown = {title = false, objectives = false}}
E.Ensure(s); E.Step(); check(#calls == 0, 'known metadata does not request')
s.quests[2] = {unknown = {title = true}}; E.Ensure(s); E.Step(); check(#calls == 0, 'unobserved ID not scanned')

fresh(); s = snapshot(1); E.Ensure(s); E.Step(); E.Ensure(snapshot(0)); check(not E.OnResult(1, true), 'dropped callback rejected'); check(rereads == 0, 'dropped no reread')
E.Ensure(s); E.Step(); check(#calls == 2, 'returned quest retains one remaining attempt')
E.OnResult(1, false); clock = 60; E.Step(); check(#calls == 2, 'dropped quest attempts preserved')

fresh(); s = snapshot(1); E.Ensure(s); E.Step(); s.identity.locale = 'deDE'; E.Ensure(s)
check(E.Step() == 0 and not E.OnResult(1, true), 'old identity event isolated')
check(E.Status().requests == 0 and rereads == 0, 'identity reset counts with no old adoption')
check(E.Step() == 1 and #calls == 2, 'new identity can request after old callback')

fresh(); s = snapshot(1); E.Ensure(s); E.Step(); clock = 30; E.Step()
check(E.Status().failed == 1 and #calls == 1, 'timeout recorded without immediate retry')
check(not E.OnResult(1, true) and rereads == 0, 'timed out callback ignored')
clock = 60; E.Step(); check(#calls == 2, 'timeout retry after cooldown')

fresh(); s = snapshot(1); E.Ensure(s); _G.C_QuestLog = nil
check(E.Step() == 0 and not E.Status().available, 'missing API guarded')
_G.C_QuestLog = {RequestLoadQuestByID = function() error('load failed') end}
check(E.Step() == 1 and E.Status().failed == 1 and rereads == 0, 'request failure not metadata')

fresh(); s = snapshot(1); E.Ensure(s); E.Step(); E.OnResult(1, true); E.Ensure(snapshot(1)); E.Step()
check(#calls == 1 and rereads == 1, 'still missing success waits for retry')
clock = 30; E.Step(); check(#calls == 2, 'still missing success can retry once')
s.quests[1] = {title = 'Resolved', objectives = {}, unknown = {title = false, objectives = false}}
E.OnResult(1, true); E.Ensure(s); clock = 100; E.Step(); check(#calls == 2 and E.Status().unresolved == 0, 'authoritative complete metadata resolves')
fresh(); s = snapshot(3); E.Ensure(s); E.Step()
check(E.Status().nextAt == 30, 'full concurrency waits for callback or timeout instead of polling')
clock = 31; check(not E.OnResult(1, true) and rereads == 0, 'expired callback rejected without prior Step')

fresh(); s = snapshot(1); E.Ensure(s); E.Step(); s.identity.locale = 'frFR'; E.Ensure(s)
check(E.Status().nextAt == 30, 'old identity tombstone schedules expiry')

fresh(); s = snapshot(1); E.Ensure(s); E.Step(); E.OnResult(1, true)
s.quests[1] = {title = 'Known', objectives = {}}; E.Ensure(s)
clock = 30; E.Ensure(snapshot(1)); check(E.Step() == 1, 'later missing metadata can use remaining attempt')
print('PASS enrichment cases=' .. cases .. ' checks=' .. checks)

end)
RikUI,C_QuestLog,GetTime=old,oldQuest,oldTime
report("bounded native metadata enrichment",ok,err)
end

