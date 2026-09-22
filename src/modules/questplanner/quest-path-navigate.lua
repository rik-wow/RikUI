-- Sliced local attachment, compact network search and exact corridor reconstruction.
local planner=RikUI.QuestPlanner
local schema,navigate=planner.Schema,{}
planner.PathNavigate=navigate
function navigate.Begin(mesh,graph,start,goal,options)
    options=options or {}
    local speed=options.speed or 7
    if not schema.Number(speed,.1,100) then return nil,"Invalid walking speed" end
    local attachments,why=mesh:BeginAttachments(start,goal,graph)
    if not attachments then return nil,why end
    local active=attachments
    local cancelled,output,work=false,nil,0
    local function result(status,detail)
        return {status=status,detail=detail,nativeVerified=false,metrics={work=work},revision=mesh:Revision(),hybrid=true}
    end
    local worker=coroutine.create(function()
        local endpoints
        while true do
            local value,reason,done=attachments:Step(1);work=work+1
            if done then
                if not value then return result("budget-exhausted",reason) end
                endpoints=value;break
            end
            coroutine.yield()
        end
        active=planner.PathSearch.Begin(graph,endpoints.starts,endpoints.goals,endpoints.directCost)
        local coarse
        while not coarse do coarse=active:Step(1);work=work+1;coroutine.yield() end
        if coarse.status~="modeled" then
            return result(coarse.status=="no-model-path" and "no-known-path" or coarse.status,coarse.reason)
        end
        active=planner.PathRoute.Begin(mesh,graph,endpoints,coarse,{speed=speed,maxPath=4096})
        while true do
            local route=active:Step(1);work=work+1
            if route then
                route.hybrid=true;route.networkCost=coarse.cost
                route.metrics=route.metrics or {};route.metrics.attachmentWork=endpoints.work
                route.metrics.networkWork=coarse.metrics.work;route.metrics.pipelineWork=work
                return route
            end
            coroutine.yield()
        end
    end)
    return {Cancel=function()
        cancelled=true;if active and active.Cancel then active:Cancel() end
    end,Step=function(_,budget)
        if cancelled then return result("cancelled","Navigation request changed") end
        if output then return output end
        if not schema.Integer(budget or 32,1,128) then return result("invalid","Invalid navigation slice") end
        for _=1,budget or 32 do
            local ok,value=coroutine.resume(worker)
            if not ok then output=result("invalid","Prepared corridor construction failed")
            elseif coroutine.status(worker)=="dead" then output=value end
            if output then active=nil;return output end
        end
    end}
end
