-- Incremental attachment of a frozen player origin to a sourced travel graph.
local planner=RikUI.QuestPlanner
local JourneyGraph={}
planner.JourneyGraph=JourneyGraph
local function copy(v) local out={};for k,x in pairs(v or {}) do out[k]=x end;return out end
local function same(a,b) return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale end
local function cost(v) return type(v)=="number" and v==v and v>=0 and v<math.huge end
local function avoided(anchor,policy)
    local avoids=policy.avoids or {}
    return (anchor.mapID and avoids[anchor.mapID]) or (anchor.zoneID and avoids[anchor.zoneID])
end
function JourneyGraph.New(base,origin,anchors,bridge)
    local baseRevision=base:Revision()
    local revision=baseRevision..":origin:"..origin.revision
    local candidates,prefixes={},{}
    for i=1,math.min(8,#anchors) do candidates[i]=anchors[i] end
    local function valid() return base:Revision()==baseRevision and (not origin.valid or origin.valid()) end
    local graph={}
    function graph:Identity() return base:Identity() end
    function graph:Revision() return revision end
    function graph:Begin(from,destination,state,policy)
        if from~=origin.id then return base:Begin(from,destination,state,policy) end
        policy=policy or {}
        local limit=math.max(0,math.min(8192,math.floor(tonumber(policy.maxWork) or 8192)))
        local q={index=1,phase="prefix",work=0,labels=0,limited=#anchors>#candidates}
        local function finish(stale)
            if stale then q.result={status="budget-exhausted",reason=stale,path={},graphRevision=revision,optimalInGraph=false}
            elseif q.best then
                q.result=q.best;q.result.status=q.limited and "budget-exhausted" or "known";q.result.anchor=nil
            else q.result={status=q.limited and "budget-exhausted" or "no-known-route",path={},graphRevision=revision,optimalInGraph=false} end
            q.result.metrics={work=q.work,labels=q.labels};q.active,q.prefix=nil,nil
            return q.result
        end
        local function nextCandidate() q.index=q.index+1;q.phase,q.active,q.prefix="prefix",nil,nil end
        local function accept(result,anchor)
            if result.status=="budget-exhausted" then q.limited=true end
            q.labels=q.labels+((result.metrics and result.metrics.labels) or 0)
            if (result.status~="known" and result.status~="budget-exhausted")
                or not cost(result.seconds) or not cost(result.risk) or not cost(result.uncertainty) or type(result.path)~="table" then return end
            local prefix=q.prefix
            local seconds,risk,uncertainty=prefix.seconds+result.seconds,prefix.risk+result.risk,prefix.uncertainty+result.uncertainty
            if (policy.maxSeconds and seconds>policy.maxSeconds) or (policy.maxRisk and risk>policy.maxRisk)
                or (policy.maxUncertainty and uncertainty>policy.maxUncertainty) then return end
            local old=q.best
            local better=not old or seconds<old.seconds or (seconds==old.seconds and risk<old.risk)
                or (seconds==old.seconds and risk==old.risk and uncertainty<old.uncertainty)
                or (seconds==old.seconds and risk==old.risk and uncertainty==old.uncertainty and anchor.node<old.anchor)
            if not better then return end
            local path={{id=origin.id..":walk:"..anchor.node,from=origin.id,to=anchor.node,mode="walk",
                seconds=prefix.seconds,wait=0,source=prefix.source,meters=prefix.meters,
                geometryRef=prefix.geometryRef,nativeVerified=false}}
            for i=1,#result.path do path[#path+1]=result.path[i] end
            q.best={seconds=seconds,risk=risk,uncertainty=uncertainty,path=path,anchor=anchor.node,
                hearthUsed=result.hearthUsed,hearthAt=result.hearthAt,graphRevision=revision,optimalInGraph=false}
        end
        function q:Step(budget)
            if not valid() or not same(state.identity,origin.identity) then return finish("stale-or-incompatible-origin") end
            if self.result then return self.result end
            budget=math.max(0,math.min(128,math.floor(tonumber(budget) or 1)))
            while budget>0 do
                if self.index>#candidates then return finish() end
                if self.work>=limit then self.limited=true;return finish() end
                self.work,budget=self.work+1,budget-1
                local anchor=candidates[self.index]
                if avoided(anchor,policy) then nextCandidate()
                elseif self.phase=="prefix" then
                    local cached=prefixes[self.index]
                    if cached then self.prefix,self.phase=cached,"travel-start"
                    elseif not self.active then
                        self.active=bridge(anchor,limit-self.work)
                        if not self.active then nextCandidate() end
                    else
                        local result=self.active:Step(1)
                        if result then
                            if result.status=="modeled" and cost(result.seconds) and result.complete~=false
                                and not result.partial and not result.approach and anchor.terrain and result.revision==anchor.terrain.revision then
                                local prefix={seconds=result.seconds,meters=result.meters,revision=result.revision,
                                    risk=cost(result.risk) and result.risk or 0,
                                    uncertainty=cost(result.uncertainty) and result.uncertainty or .25,
                                    source=anchor.source,geometryRef=result.geometryRef}
                                prefixes[self.index]=prefix;self.prefix,self.active=prefix,nil;self.phase="travel-start"
                            else
                                if result.status=="partial" or result.status=="budget-exhausted" then self.limited=true end
                                nextCandidate()
                            end
                        end
                    end
                elseif self.phase=="travel-start" then
                    local prefix,remaining,rejected=self.prefix,copy(policy),false
                    for _,field in ipairs({"maxSeconds","maxRisk","maxUncertainty"}) do
                        local used=field=="maxSeconds" and prefix.seconds or field=="maxRisk" and prefix.risk or prefix.uncertainty
                        if remaining[field]~=nil then remaining[field]=remaining[field]-used;if remaining[field]<0 then rejected=true end end
                    end
                    remaining.maxWork=limit-self.work
                    if remaining.maxLabels then
                        remaining.maxLabels=remaining.maxLabels-self.labels
                        if remaining.maxLabels<=0 then self.limited,rejected=true,true end
                    end
                    if remaining.maxWork<=0 then self.limited,rejected=true,true end
                    if rejected then nextCandidate()
                    else
                        local arrival=copy(state);arrival.departure=state.departure+prefix.seconds
                        self.active=base:Begin(anchor.node,destination,arrival,remaining);self.phase="travel"
                        if not self.active then nextCandidate() end
                    end
                else
                    local result=self.active:Step(1)
                    if result then accept(result,anchor);nextCandidate() end
                end
            end
            if self.index>#candidates then return finish() end
            if self.work>=limit then self.limited=true;return finish() end
        end
        return q
    end
    function graph:Estimate(from,destination,state,policy)
        local query,reason=self:Begin(from,destination,state,policy)
        if not query then return {status="unknown",reason=reason,path={}} end
        local result;repeat result=query:Step(128) until result
        return result
    end
    return graph
end
