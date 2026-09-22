-- Offline route quality and callback instrumentation; never included in the addon.
local Q={}
local function turn(a,b) return (a-b+180)%360-180 end
local function heading(state,dx,dz,time,distance)
    if dx*dx+dz*dz<1e-12 then return end
    local angle=math.atan2(dz,dx)*180/math.pi
    if not state.previous then state.previous=angle;state.anchor=angle;return end
    local signed=turn(angle,state.previous)
    if math.abs(signed)>=5 then
        if state.pairedTurn and signed*state.pairedTurn<0 and distance-state.pairedDistance<=2 then
            state.shortReversals=(state.shortReversals or 0)+1
            state.maximumPairedTurn=math.max(state.maximumPairedTurn or 0,math.abs(signed),math.abs(state.pairedTurn))
        end
        state.pairedTurn,state.pairedDistance=signed,distance
    end
    local difference=math.abs(signed)
    state.total=state.total+difference;state.maximum=math.max(state.maximum,difference);state.previous=angle
    local significant=turn(angle,state.anchor)
    if math.abs(significant)<1 then return end
    state.anchor=angle
    if state.last and significant*state.last<0 and math.abs(significant)<=20
        and math.abs(state.last)<=20 and time-state.time<=.5 then state.oscillations=state.oscillations+1 end
    state.last,state.time=significant,time
end
function Q.New()
    local value={distance=0,spatial=0,movement={total=0,maximum=0,oscillations=0},aim={total=0,maximum=0,oscillations=0}}
    function value:Observe(point,target,time)
        if self.previous then
            local a=self.previous
            local dx,dy,dz=point[1]-a[1],point[2]-a[2],point[3]-a[3]
            self.distance=self.distance+math.sqrt(dx*dx+dz*dz)
            self.spatial=self.spatial+math.sqrt(dx*dx+dy*dy+dz*dz)
            heading(self.movement,dx,dz,time,self.distance)
        end
        if target then heading(self.aim,target.x-point[1],target.z-point[3],time,self.distance) end
        self.previous=point
    end
    return value
end
function Q.Timing(values)
    table.sort(values)
    local function percentile(p) return values[math.max(1,math.ceil(#values*p))] or 0 end
    return {samples=#values,p50=percentile(.5),p95=percentile(.95),p99=percentile(.99),maximum=percentile(1)}
end
function Q.Allocations(callback,count)
    assert(count>=1 and count<=1000)
    collectgarbage("collect")
    local before=collectgarbage("count")
    collectgarbage("stop")
    local ok,reason=pcall(function() for at=1,count do callback(at) end end)
    local growth=collectgarbage("count")-before
    collectgarbage("restart")
    if not ok then error(reason) end
    collectgarbage("collect")
    return {evidence="automated-replay",gc="paused-allocation-estimate",callbacks=count,
        bytesPerCallback=growth*1024/count,retainedKB=collectgarbage("count")-before}
end
return Q
