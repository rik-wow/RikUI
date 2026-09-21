-- Moving lifts are explicit directed connections, never static mesh adjacency.
local planner, schema = RikUI.QuestPlanner, RikUI.QuestPlanner.Schema
local elevators = {}
planner.Elevators = elevators
local MAX_CLOCK, MAX_SECONDS = 2147483647, 86400
local function token(value)
    return schema.Text(value) and #value > 0 and #value <= 128 and value:match("^[%w_.:%-]+$") ~= nil
end
function elevators.Valid(edge)
    return edge.from ~= edge.to and token(edge.transport) and token(edge.schedule)
        and schema.Number(edge.period, 1, MAX_SECONDS) and schema.Number(edge.offset, 0, edge.period)
        and schema.Number(edge.boardingWindow, 0, edge.period) and edge.boardingWindow < edge.period
        and schema.Number(edge.boardSeconds, .001, edge.boardingWindow)
        and schema.Number(edge.rideSeconds, .001, MAX_SECONDS)
        and schema.Number(edge.exitSeconds, 0, MAX_SECONDS)
        and edge.boardingWindow + edge.rideSeconds <= edge.period
        and math.abs(edge.seconds - edge.boardSeconds - edge.rideSeconds - edge.exitSeconds) < .000001
end
function elevators.Context(raw, departure)
    if raw == nil then return {} end
    if not schema.PlainTable(raw) then return nil end
    local result, count = {}, 0
    for id, value in pairs(raw) do
        count = count + 1
        if count > 512 or not token(id) or not schema.PlainTable(value) then return nil end
        local entry = schema.CopyLimited(value, 32, 2048, 4)
        if not entry or type(entry.available) ~= "boolean" or not token(entry.schedule)
            or not schema.Number(entry.epoch, 0, MAX_CLOCK)
            or not schema.Number(entry.observedAt, 0, departure)
            or not schema.Number(entry.expiresAt, entry.observedAt, MAX_CLOCK) then return nil end
        result[id] = entry
    end
    return result
end
function elevators.Cost(edge, state, now)
    local phase = state[edge.transport]
    if not phase or phase.available ~= true then return nil, "elevator-unavailable-or-unknown" end
    if phase.schedule ~= edge.schedule then return nil, "elevator-schedule-changed" end
    if now < phase.observedAt or now > phase.expiresAt then return nil, "elevator-phase-stale" end
    local position = (now - phase.epoch - edge.offset) % edge.period
    local beforeBoard, onboardWait
    if position <= edge.boardingWindow - edge.boardSeconds then
        beforeBoard = 0
        onboardWait = edge.boardingWindow - position - edge.boardSeconds
    else
        beforeBoard = edge.period - position
        onboardWait = edge.boardingWindow - edge.boardSeconds
    end
    local elapsed = beforeBoard + edge.boardSeconds + onboardWait + edge.rideSeconds + edge.exitSeconds
    if now + elapsed > phase.expiresAt then return nil, "elevator-phase-expires-before-arrival" end
    return elapsed, nil, {
        transport=edge.transport, schedule=edge.schedule, boardAt=now+beforeBoard,
        observedAt=phase.observedAt, expiresAt=phase.expiresAt,
        departAt=now+beforeBoard+edge.boardSeconds+onboardWait,
        arriveAt=now+elapsed, beforeBoard=beforeBoard, board=edge.boardSeconds,
        onboardWait=onboardWait, ride=edge.rideSeconds, exit=edge.exitSeconds,
        instruction="Wait at the boarding stop, board the lift, ride, then exit at the destination stop",
    }
end
