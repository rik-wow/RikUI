-- Evidence-driven travel progression. Time and map proximity never complete a ride.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local journey={}
planner.Journey=journey
local modes={walk=true,flight=true,transport=true,hearth=true,elevator=true}
local function text(v) return schema.Text(v) and #v>0 and #v<=256 end
local function key(v) return schema.ID(v) or text(v) end
local function revision(v) return schema.Integer(v,0,2147483647) or text(v) end
local function same(a,b) return schema.Identity(a) and schema.Identity(b) and a.product==b.product and a.build==b.build and a.locale==b.locale end
local function floor(v) return v==nil or text(v) or schema.Integer(v,-2147483648,2147483647) end
local function arrival(e,node,radius)
    if not schema.PlainTable(e.arrivals) then return false end
    local a=e.arrivals[node.id]
    return schema.PlainTable(a) and a.sequence==e.sequence and a.anchorVerified==true
        and a.connected==true and a.partial==false and a.mapID==node.mapID
        and (node.instanceID==nil or a.instanceID==node.instanceID)
        and (node.floor==nil or a.floor==node.floor)
        and (node.anchorRevision==nil or a.anchorRevision==node.anchorRevision)
        and schema.Number(a.distance,0,radius)
end
function journey.New(identity,generation,rawLegs,lookup,radius)
    radius=radius or 4
    if not schema.Identity(identity) or not revision(generation) or type(lookup)~="function"
        or not schema.Number(radius,.1,20) then return nil,"invalid journey" end
    local legs,problem=schema.CopyLimited(rawLegs,8192,65536,12)
    if not legs or not schema.List(legs,128) then return nil,problem or "invalid legs" end
    identity=schema.Clone(identity)
    local path,nodes={},{}
    for i,leg in ipairs(legs) do
        if not schema.PlainTable(leg) or not key(leg.id) or not key(leg.from) or not key(leg.to)
            or not modes[leg.mode] or not schema.Source(leg.source) or not same(leg.source,identity)
            or leg.source.authority~="verified" then return nil,"invalid leg" end
        if i>1 and path[i-1].to~=leg.from then return nil,"discontinuous journey" end
        for _,id in ipairs({leg.from,leg.to}) do
            if not nodes[id] then
                local n=schema.Copy(lookup(id))
                if not schema.PlainTable(n) or n.id~=id or not schema.ID(n.mapID)
                    or not schema.Number(n.x,0,1) or not schema.Number(n.y,0,1) or not floor(n.floor)
                    or (n.instanceID~=nil and not schema.Integer(n.instanceID,0,2147483647))
                    or (n.anchorRevision~=nil and not revision(n.anchorRevision)) then return nil,"invalid anchor" end
                nodes[id]={id=id,mapID=n.mapID,x=n.x,y=n.y,instanceID=n.instanceID,
                    floor=n.floor,anchorRevision=n.anchorRevision}
            end
        end
        path[i]={id=leg.id,from=leg.from,to=leg.to,mode=leg.mode,source=leg.source}
    end
    local s={index=1,sequence=0,time=0,paused=false,phase="approach",boarded=false,exited=false}
    local handle={}
    function handle:Snapshot(reason)
        local leg=path[s.index]
        if not leg then return {generation=generation,complete=true,phase="arrived",paused=s.paused,suppressSteering=true,reason=reason} end
        local moving=s.phase=="riding" or s.phase=="riding-unknown"
        local destinationID=(leg.mode=="walk" or s.exited) and leg.to or leg.from
        return {generation=generation,complete=false,index=s.index,legID=leg.id,mode=leg.mode,
            from=leg.from,to=leg.to,phase=s.phase,source=schema.Clone(leg.source),
            destination=not moving and not s.recovery and schema.Clone(nodes[destinationID]) or nil,
            boarded=s.boarded,exited=s.exited,paused=s.paused,needsReplan=s.recovery==true,
            suppressSteering=s.paused or moving or s.recovery==true or s.phase=="waiting",reason=reason}
    end
    local function advance(e)
        s.index=s.index+1;s.boarded,s.exited,s.originAt=false,false,nil
        s.unknownRide,s.recovery,s.phase=false,false,"approach"
        local nextLeg=path[s.index]
        if nextLeg and arrival(e,nodes[nextLeg.from],radius) then s.originAt=e.time end
    end
    local function recover() s.recovery,s.phase=true,"recovery" end
    -- Borrow the compact evidence for this observation; never retain caller tables.
    function handle:Observe(e)
        if not schema.PlainTable(e) then return self:Snapshot("invalid-evidence") end
        if not same(e.identity,identity) or e.generation~=generation then return self:Snapshot("stale-plan") end
        if not schema.Integer(e.sequence,1,2147483647) or e.sequence<=s.sequence
            or not schema.Number(e.time,0,1e12) or e.time<s.time then return self:Snapshot("stale-observation") end
        if (e.taxi~=nil and type(e.taxi)~="boolean") or (e.paused~=nil and type(e.paused)~="boolean") then return self:Snapshot("invalid-evidence") end
        local taxiRise=s.lastTaxi==false and e.taxi==true and s.taxiAt~=nil and e.time-s.taxiAt<=2
        s.sequence,s.time,s.paused=e.sequence,e.time,e.paused==true
        s.lastTaxi=e.taxi;s.taxiAt=e.taxi~=nil and e.time or nil
        local leg=path[s.index]
        if not leg or s.recovery then return self:Snapshot() end
        local atFrom,atTo=arrival(e,nodes[leg.from],radius),arrival(e,nodes[leg.to],radius)
        if atFrom then s.originAt=e.time end
        local recentOrigin=s.originAt~=nil and e.time-s.originAt<=5
        if leg.mode=="walk" then
            if e.taxi==true then s.unknownRide,s.phase=true,"riding-unknown"
            elseif s.unknownRide then if e.taxi==false then recover() end
            else s.phase="walking";if atTo then advance(e) end end
            return self:Snapshot()
        end
        if leg.mode=="flight" then
            if not s.boarded and taxiRise and recentOrigin then s.boarded=true end
            if not s.boarded and e.taxi==true then s.unknownRide=true end
            if s.boarded and e.taxi==false then s.exited=true end
            if s.unknownRide and not s.boarded and e.taxi==false then recover() end
            if s.exited and e.taxi==true then recover() end
        else
            local t=e.transition
            local matched=schema.PlainTable(t) and t.verified==true and t.sequence==e.sequence
                and t.index==s.index and t.legID==leg.id and t.mode==leg.mode and t.from==leg.from and t.to==leg.to
            if matched and t.started==true and recentOrigin then s.boarded=true end
            if matched and t.ended==true then if s.boarded then s.exited=true else recover() end end
        end
        if s.recovery then return self:Snapshot() end
        if s.boarded and s.exited and atTo then advance(e)
        elseif not s.boarded and atTo and not atFrom then recover()
        elseif s.boarded then s.phase=s.exited and "exiting" or "riding"
        elseif s.unknownRide then s.phase="riding-unknown"
        else s.phase=atFrom and "waiting" or "approach" end
        return self:Snapshot()
    end
    return handle
end
