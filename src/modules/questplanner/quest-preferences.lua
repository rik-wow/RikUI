-- Human-scale preferences; fixed units shared by every planner flavor.
local planner=RikUI.QuestPlanner
local schema,preferences=planner.Schema,{}
planner.Preferences=preferences
local FLAVORS={"Balanced","Efficient","Story","Explorer","Relaxed","Challenge"}
local PRESETS={
    Balanced={detour=.25,variety=.45,continuity=.5,discovery=.2,pressure=.5,difficulty="standard",grind="medium",maxRisk=.35},
    Efficient={detour=.05,variety=.05,continuity=.1,discovery=0,pressure=.3,difficulty="standard",grind="high",maxRisk=.4},
    Story={detour=.55,variety=.15,continuity=1,discovery=.1,pressure=.45,difficulty="standard",grind="medium",maxRisk=.35},
    Explorer={detour=.6,variety=.6,continuity=.2,discovery=1,pressure=.4,difficulty="standard",grind="low",maxRisk=.35},
    Relaxed={detour=.3,variety=.3,continuity=.4,discovery=.1,pressure=1,difficulty="easy",grind="low",maxRisk=.15},
    Challenge={detour=.35,variety=.5,continuity=.3,discovery=.2,pressure=.1,difficulty="hard",grind="medium",maxRisk=.5},
}
local CHOICES={difficulty={easy=true,standard=true,hard=true},group={solo=true,available=true},
    travel={localOnly=true,regional=true,world=true},grind={low=true,medium=true,high=true}}
local function flags(value)
    local result,count={},0
    if value==nil then return result end
    if not schema.PlainTable(value) then return nil end
    for id,enabled in pairs(value) do
        count=count+1
        if count>64 or not schema.ID(id) or type(enabled)~="boolean" then return nil end
        if enabled then result[id]=true end
    end
    return result
end
function preferences.Flavors() return schema.Clone(FLAVORS) end
function preferences.Preset(flavor) return schema.Clone(PRESETS[flavor]) end
function preferences.Normalize(raw)
    raw=raw or {}
    if not schema.PlainTable(raw) then return nil,"Invalid preferences" end
    local flavor=raw.flavor or "Balanced"
    if not PRESETS[flavor] then return nil,"Unknown flavor" end
    local result=schema.Clone(PRESETS[flavor])
    result.version,result.flavor=1,flavor
    result.sessionMinutes=raw.sessionMinutes or 60
    if not schema.Integer(result.sessionMinutes,5,480) then return nil,"Session length must be 5 to 480 minutes" end
    result.maxSeconds=result.sessionMinutes*60
    for key,choices in pairs(CHOICES) do
        result[key]=raw[key] or result[key] or (key=="group" and "solo" or "regional")
        if not choices[result[key]] then return nil,"Invalid "..key.." preference" end
    end
    result.explorationMinutes=raw.explorationMinutes or (flavor=="Explorer" and 15 or 5)
    if not schema.Integer(result.explorationMinutes,0,60) then return nil,"Exploration allowance must be 0 to 60 minutes" end
    for _,key in ipairs({"dungeons","spoilers","strictSession"}) do
        if raw[key]~=nil and type(raw[key])~="boolean" then return nil,"Invalid "..key end
        result[key]=raw[key]==true
    end
    result.services=raw.services~=false
    for _,key in ipairs({"pins","skips","avoids","defers","questGoals","zoneGoals"}) do
        result[key]=flags(raw[key])
        if not result[key] then return nil,"Invalid "..key.." constraints" end
    end
    result.readingSeconds=raw.readingSeconds or (flavor=="Story" and 45 or 10)
    if not schema.Integer(result.readingSeconds,0,180) then return nil,"Invalid reading time" end
    return result
end
function preferences.Conflict(policy,questID,zoneID)
    if not (policy.pins[questID] or policy.questGoals[questID]) then return end
    if policy.skips[questID] then return "Pinned quest is skipped; include it to resume" end
    if policy.defers[questID] then return "Pinned quest is deferred for this session" end
    if zoneID and policy.avoids[zoneID] then return "Pinned quest is in an avoided area" end
end
