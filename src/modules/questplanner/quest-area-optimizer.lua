-- Bounded comparison of source areas using the currently loaded walking model.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local optimizer=planner.Optimizer
if not optimizer then return end
local MAX_CANDIDATES,MAX_WORK,SLICE=8,65536,32
function optimizer.BeginAreas(list,shared,identity,position)
    local candidates={}
    for _,value in ipairs(list) do
        value.shared=shared[value.area.id] or 1
        value.score=value.distance/math.min(value.shared,4)
        candidates[#candidates+1]=value
    end
    table.sort(candidates,function(a,b)
        if a.score~=b.score then return a.score<b.score end
        return tostring(a.area.id)<tostring(b.area.id)
    end)
    local initial=candidates[1]
    if not initial then return end
    local total=#candidates
    while #candidates>MAX_CANDIDATES do table.remove(candidates) end
    local at,active,work,best,attempted=1,nil,0,nil,0
    local query={initial=initial,limited=total>MAX_CANDIDATES,
        terrainAvailable=planner.Terrain and planner.Terrain.AreaRevision and planner.Terrain.AreaRevision()~=nil}
    function query:Step()
        if self.result then return self.result,true end
        if at>#candidates or work>=MAX_WORK then
            self.result=best or initial
            self.result.comparison={attempted=attempted,work=work,limited=self.limited or work>=MAX_WORK,terrainAvailable=self.terrainAvailable}
            return self.result,true
        end
        local candidate=candidates[at]
        if not active then
            if candidate.distance==math.huge then at=at+1;return end
            active=planner.Terrain and planner.Terrain.BeginAreaEstimate
                and planner.Terrain.BeginAreaEstimate(identity,position,candidate.area,math.min(32768,MAX_WORK-work))
            if not active then at=at+1;return end
            attempted=attempted+1
        end
        work=work+SLICE
        local result=active:Step(SLICE)
        if not result then return end
        if result.status=="modeled" and schema.Number(result.meters,0,1000000) then
            candidate.score=result.meters/math.min(candidate.shared,4)
            candidate.costBasis=result.approach and "modeled approach distance" or "modeled walking distance"
            candidate.modeledMeters=result.meters
            if not best or candidate.score<best.score then best=candidate end
        elseif result.status=="budget-exhausted" then self.limited=true end
        at=at+1;active=nil
    end
    return query
end

