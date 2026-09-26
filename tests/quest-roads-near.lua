-- Network nodes near a point (game X, Y), with height and piece size.
-- Usage: luajit tests/quest-roads-near.lua <network dir> <world> <gameX> <gameY> [radius]
local root,world=assert(arg[1]):gsub("\\","/"),assert(tonumber(arg[2]))
local gx,gy,radius=assert(tonumber(arg[3])),assert(tonumber(arg[4])),tonumber(arg[5]) or 300
package.path="tests/?.lua;"..package.path
require("wow_stub")
RikUI={Secret={IsSecret=function() return false end}}
for _,name in ipairs({"schema","path-codec","roads"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
local p=RikUI.QuestPlanner
local generated=dofile("tests/generated_stub.lua")
generated.Load(generated.Base(root),{"roads"})
C_AddOns={LoadAddOn=generated.PatchLoader(root)}
local g
for _=1,1000000 do g=p.Roads.Prepare({product="forever",build="1.60.1.69913",locale="enUS"},world);if g then break end end
local n=g:Nodes()
local adj={}
for i=1,n do adj[i]=adj[i] or {};local a,b=g:EdgeRange(i);for e=a,b do local t=g:Edge(e);adj[i][t]=true;adj[t]=adj[t] or {};adj[t][i]=true end end
local piece,size={}, {}
for s=1,n do if not piece[s] then local id=#size+1;size[id]=0;piece[s]=id;local st={s}
    while #st>0 do local u=table.remove(st);size[id]=size[id]+1;for v in pairs(adj[u]) do if not piece[v] then piece[v]=id;st[#st+1]=v end end end end end
local rows={}
for i=1,n do
    local x,z,y=g:Node(i)
    local d=math.sqrt((x-gy)^2+(z-gx)^2)
    if d<=radius then rows[#rows+1]={i,d,y,size[piece[i]]} end
end
table.sort(rows,function(a,b) return a[2]<b[2] end)
for k=1,math.min(25,#rows) do local r=rows[k];io.write(string.format("node %6d  %5.0f yd  height %7.1f  piece %d nodes\n",r[1],r[2],r[3],r[4])) end
