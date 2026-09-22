return function(check)
    local Q=dofile("tests/quest-route-quality.lua")
    local q=Q.New()
    q:Observe({0,0,0},{x=3,z=4},0)
    q:Observe({3,12,4},{x=6,z=8},.5)
    check("quality records horizontal and elevation distances",q.distance==5 and q.spatial==13)
    local jitter=Q.New()
    for at,angle in ipairs({0,5,-5,5}) do
        local x,a=at-1,angle*math.pi/180
        jitter:Observe({x,0,0},{x=x+math.cos(a),z=math.sin(a)},at*.1)
    end
    check("quality separates deliberate movement and small aim oscillations",
        jitter.aim.oscillations==2 and math.abs(jitter.aim.total-25)<1e-8 and jitter.movement.total==0)
    local timing=Q.Timing({4,1,3,2})
    check("timing percentiles preserve worst callback",timing.p50==2 and timing.p95==4 and timing.maximum==4)
    local allocation=Q.Allocations(function() local value={1,2,3};assert(value[2]==2) end,10)
    check("allocation result is explicitly an automated GC-paused estimate",
        allocation.bytesPerCallback>=0 and allocation.evidence=="automated-replay")
    local gc,operations=collectgarbage,{}
    collectgarbage=function(op) operations[#operations+1]=op;return 100 end
    local ok=pcall(Q.Allocations,function() error("fixture") end,1)
    collectgarbage=gc
    check("allocation benchmark restarts GC on failure",not ok and operations[#operations]=="restart")
end
