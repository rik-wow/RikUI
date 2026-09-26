-- Which connected piece of a compiled road network each named place falls in.
-- Usage: luajit tests/quest-roads-pieces.lua <network dir> <world> "Name,uiMap,x,y" ...
local root,world=assert(arg[1]):gsub("\\","/"),assert(tonumber(arg[2]))
package.path="tests/?.lua;"..package.path
require("wow_stub")
RikUI={Secret={IsSecret=function() return false end}}
for _,name in ipairs({"schema","path-codec","roads"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
local p=RikUI.QuestPlanner
local generated=dofile("tests/generated_stub.lua")
generated.Load(generated.Base(root),{"roads"})
C_AddOns={LoadAddOn=generated.PatchLoader(root)}
local graph
for _=1,1000000 do graph=p.Roads.Prepare({product="forever",build="1.60.1.69913",locale="enUS"},world);if graph then break end end
local n=graph:Nodes()
local adj={}
for i=1,n do adj[i]=adj[i] or {} end
for i=1,n do
    local a,b=graph:EdgeRange(i)
    for e=a,b do local t=graph:Edge(e);adj[i][t]=true;adj[t]=adj[t] or {};adj[t][i]=true end
end
local piece,sizes={}, {}
for s=1,n do
    if not piece[s] then
        local id=#sizes+1;sizes[id]=0;piece[s]=id
        local stack={s}
        while #stack>0 do
            local u=table.remove(stack);sizes[id]=sizes[id]+1
            for v in pairs(adj[u]) do if not piece[v] then piece[v]=id;stack[#stack+1]=v end end
        end
    end
end
local order={}
for id=1,#sizes do order[#order+1]=id end
table.sort(order,function(a,b) return sizes[a]>sizes[b] end)
local rank={};for r,id in ipairs(order) do rank[id]=r end
io.write(string.format("world %d: %d nodes, %d pieces; largest %d, %d, %d\n",world,n,#sizes,sizes[order[1]],
    sizes[order[2]] or 0,sizes[order[3]] or 0))
for k=3,#arg do
    local name,m,x,y=arg[k]:match("([^,]+),(%d+),([%d.]+),([%d.]+)")
    local w,pt=p.Roads.Locate(tonumber(m),tonumber(x),tonumber(y))
    if w~=world then io.write(string.format("%-22s not in world %d\n",name,world)) else
        local best,bd=nil,math.huge
        for i=1,n do local nx,nz=graph:Node(i);local d=(nx-pt.x)^2+(nz-pt.z)^2;if d<bd then best,bd=i,d end end
        io.write(string.format("%-22s %4.0f yd from a node, piece rank %d (%d nodes)\n",name,math.sqrt(bd),rank[piece[best]],sizes[piece[best]]))
    end
end
