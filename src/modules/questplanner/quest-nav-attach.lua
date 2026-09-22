-- Local directed searches attach real walking surfaces to a prepared network.
-- Only loaded, validated portals contribute; geometric proximity never adds edges.
local planner=RikUI.QuestPlanner
local schema,geometry=planner.Schema,planner.NavGeometry
local attach={};planner.NavAttach=attach
local MAX_WORK,MAX_GATEWAYS,MAX_PATH=1048576,128,4096
local function less(a,b) return a.cost<b.cost or a.cost==b.cost and a.id<b.id end
local function heap()
    local rows,positions={},{}
    local function swap(a,b)
        rows[a],rows[b]=rows[b],rows[a];positions[rows[a].id]=a;positions[rows[b].id]=b
    end
    return {
        put=function(id,cost)
            local at=positions[id]
            if at then rows[at].cost=cost else at=#rows+1;rows[at]={id=id,cost=cost};positions[id]=at end
            while at>1 do
                local up=math.floor(at/2);if not less(rows[at],rows[up]) then break end
                swap(at,up);at=up
            end
        end,
        pop=function()
            local first=rows[1];if not first then return end
            local last=table.remove(rows);positions[first.id]=nil
            if #rows>0 then
                rows[1]=last;positions[last.id]=1
                local at=1
                while at*2<=#rows do
                    local next=at*2
                    if next<#rows and less(rows[next+1],rows[next]) then next=next+1 end
                    if not less(rows[next],rows[at]) then break end
                    swap(at,next);at=next
                end
            end
            return first
        end,
    }
end
local function legJob(parent,origin,target,reverse)
    local cancelled,done=false,false
    local worker=coroutine.create(function()
        local path,seen,node={},{},target
        while node do
            if seen[node] or #path>=MAX_PATH then return nil,"Local attachment output limit" end
            seen[node]=true;path[#path+1]=node
            if node==origin then break end
            node=parent[node]
            if not node then return nil,"Missing local attachment witness" end
            coroutine.yield()
        end
        if reverse then return path end
        local ordered={}
        for index=#path,1,-1 do ordered[#ordered+1]=path[index];coroutine.yield() end
        return ordered
    end)
    return {Cancel=function() cancelled=true end,Step=function(_,budget)
        if cancelled then return nil,"cancelled",true end
        if done then return nil,"Attachment witness already finished",true end
        if not schema.Integer(budget or 16,1,64) then return nil,"Invalid attachment witness budget",true end
        for _=1,budget or 16 do
            local ok,result,why=coroutine.resume(worker)
            if not ok then done=true;return nil,"Invalid local attachment witness",true end
            if coroutine.status(worker)=="dead" then done=true;return result,why,true end
        end
    end}
end
function attach.Begin(data,start,goal,graph)
    if not start or not goal or not data.polygons[start.id] or not data.polygons[goal.id]
        or not geometry.Point(start.point) or not geometry.Point(goal.point)
        or type(graph)~="table" or type(graph.Gateway)~="function" then return nil,"Attachment endpoints unavailable" end
    start,goal=schema.Clone(start),schema.Clone(goal)
    local cancelled,done,work=false,false,0
    local worker=coroutine.create(function()
        local reverse={}
        local function tick()
            work=work+1
            if work>MAX_WORK then error("Local attachment work limit") end
            coroutine.yield()
        end
        for _,id in ipairs(data.order) do
            reverse[id]=reverse[id] or {}
            for _,portal in ipairs(data.polygons[id].portals) do
                reverse[portal.to]=reverse[portal.to] or {}
                reverse[portal.to][#reverse[portal.to]+1]={to=id,meters=portal.meters}
                tick()
            end
            tick()
        end
        local function tree(origin,inward)
            local distance,parent,settled={}, {},{}
            local frontier=heap()
            distance[origin.id]=geometry.Distance(origin.point,data.polygons[origin.id].center)
            frontier.put(origin.id,distance[origin.id])
            while true do
                local row=frontier.pop()
                if not row then break end
                settled[row.id]=true;tick()
                local edges=inward and reverse[row.id] or data.polygons[row.id].portals
                for _,edge in ipairs(edges) do
                    local candidate=row.cost+edge.meters
                    if not settled[edge.to] and (distance[edge.to]==nil or candidate<distance[edge.to]) then
                        distance[edge.to]=candidate;parent[edge.to]=row.id;frontier.put(edge.to,candidate)
                    end
                    tick()
                end
            end
            return distance,parent
        end
        local outward,prefix=tree(start,false)
        local inward,suffix=tree(goal,true)
        local starts,goals,polygons={}, {},{}
        local startCount,goalCount=0,0
        for _,id in ipairs(data.order) do
            local gateway=graph:Gateway(id)
            if gateway then
                polygons[gateway]=id
                if outward[id]~=nil then starts[gateway]=outward[id];startCount=startCount+1 end
                if inward[id]~=nil then goals[gateway]=inward[id];goalCount=goalCount+1 end
                if startCount>MAX_GATEWAYS or goalCount>MAX_GATEWAYS then return nil,"Local attachment gateway limit" end
            end
            tick()
        end
        local direct=outward[goal.id] and outward[goal.id]+geometry.Distance(data.polygons[goal.id].center,goal.point)
        if start.id==goal.id then direct=geometry.Distance(start.point,goal.point) end
        return {
            starts=starts,goals=goals,directCost=direct,start=start,goal=goal,work=work,
            BeginPrefix=function(_,gateway)
                local target=polygons[gateway]
                if not target or starts[gateway]==nil then return nil,"Start cannot reach this gateway" end
                return legJob(prefix,start.id,target,false)
            end,
            BeginSuffix=function(_,gateway)
                local target=polygons[gateway]
                if not target or goals[gateway]==nil then return nil,"Gateway cannot reach destination" end
                return legJob(suffix,goal.id,target,true)
            end,
            BeginDirect=function()
                if direct==nil then return nil,"No local direct path" end
                return legJob(prefix,start.id,goal.id,false)
            end,
        }
    end)
    return {Cancel=function() cancelled=true end,Progress=function() return work end,Step=function(_,budget)
        if cancelled then return nil,"cancelled",true end
        if done then return nil,"Attachment search already finished",true end
        if not schema.Integer(budget or 16,1,64) then return nil,"Invalid attachment budget",true end
        for _=1,budget or 16 do
            local ok,result,why=coroutine.resume(worker)
            if not ok then done=true;return nil,work>MAX_WORK and "Local attachment work limit" or "Invalid local attachment",true end
            if coroutine.status(worker)=="dead" then done=true;return result,why,true end
        end
    end}
end
