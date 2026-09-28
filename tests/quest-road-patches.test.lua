-- Quest patch cells: the compact layout reads back as the same rows as the two-string layout.
-- Both texts of each cell come from tools/terrain/quest_pockets.py (encode_cell, compact_cell).
return function(check)
    local old,oldUtil,oldEnum=RikUI,C_EncodingUtil,Enum
    local ok,err=pcall(function()
        RikUI={}
        RikUI["Secret"]={IsSecret=function() return false end}
        C_EncodingUtil,Enum=nil,nil
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-path-codec.lua")
        dofile("src/modules/questplanner/quest-inflate.lua")
        RikUI.QuestPlanner.Roads={}
        dofile("src/modules/questplanner/quest-road-patches.lua")
        local planner=RikUI.QuestPlanner
        local roads,patches=planner.Roads,planner.RoadPatches
        local OLD,NEW=string.rep("a",64),string.rep("b",64)
        local KEY=2048*4096+2048     -- cell 0,0
        local FAR=2051*4096+2047     -- cell 3,-1: the origin is added to x and z
        local function graph(revision)
            return {revision=revision,cellYards=128,catalog={patchUnitsPerYard=1024}}
        end
        local function rows(revision,key)
            local result,reason
            local thread=coroutine.create(function() result,reason=patches.Decode(graph(revision),key) end)
            while coroutine.status(thread)~="dead" do assert(coroutine.resume(thread)) end
            return result,reason
        end
        local function same(a,b)
            if type(a)~=type(b) then return false end
            if type(a)~="table" then return a==b end
            for key,value in pairs(a) do if not same(value,b[key]) then return false end end
            for key in pairs(b) do if a[key]==nil then return false end end
            return true
        end

        local PLAIN="42FgYOABYjYgZgJiFiDmAGJGKJ+hoYGF4f9/5oYGDmQOSBlIFSMLEIJYzECtTILSAA=="
        local ODD="PY1RCoAwDEPTujEV8UcED+C//nu53ExvVrMhFh5pQ0hXAIuYhYskhk8nATIhopO07c7k+LtotvEpLbrFxZ1nHGbJc62rk+FuVuppXen15gU="
        check("the two-string layout registers",roads.Patch(OLD,KEY,6,2,2,44,
            "0000000000000000Du4h00000000000Du4h0Du4h00000000000Du4h00000000310000000000000310Du4h00000",
            "0RR911ONa500IC5009C3000620RRF3000C500aO900IC30RR910RRF3")==true)
        check("the compact layout registers",roads.Patch2(NEW,KEY,6,2,2,79,PLAIN)==true)
        local before,after=rows(OLD,KEY),rows(NEW,KEY)
        check("a compact cell reads back as the same rows",before~=nil and same(before,after),tostring(after))
        check("the rows are the two polygons with their shared edge",after and #after==2 and after[1].id==1 and after[2].id==2
            and #after[1].points==4 and after[1].points[3][1]==32 and after[1].points[3][3]==32
            and after[1].portals[1].to==2 and after[2].portals[1].to==1
            and after[2].portals[1].left[3]==0 and after[2].portals[1].right[3]==32)

        -- Heights, a portal that is no polygon edge, a vertex first used by a portal, a five-sided polygon.
        assert(roads.Patch(OLD,FAR,9,2,4,62,
            "0000000000000000Du4h00000000000Du4h0Du4h00000000000Du4h000000Du4h0000000sa600031000000Qdj@000310Du4h0000008jt`0H6Q>01N;C0FVIy0FVIy00000",
            "0RR911ONa500IC500II40006200062000310ssO4000F900jUB00IC900IF3000622LJ&8000O80ssI2"))
        assert(roads.Patch2(NEW,FAR,9,2,4,117,ODD))
        before,after=rows(OLD,FAR),rows(NEW,FAR)
        check("an irregular compact cell reads back as the same rows",before~=nil and same(before,after),tostring(after))
        check("the cell origin and the heights are kept",after and after[1].points[2][1]==3*128+32 and after[1].points[2][3]==-128
            and after[2].points[1][2]==1.5 and after[2].points[2][2]==-2.25 and #after[2].points==5
            and after[2].portals[2].left[1]==3*128+100)
        check("decoded rows are fresh tables",rows(NEW,KEY)[1].points[1]~=rows(NEW,KEY)[1].points[1])

        check("a cell that was never registered has no rows",rows(NEW,KEY+1)==nil)
        check("wrong counts and sizes are refused at registration",roads.Patch2(NEW,KEY,0,2,2,79,PLAIN)==nil
            and roads.Patch2(NEW,KEY,6,0,2,79,PLAIN)==nil and roads.Patch2(NEW,KEY,6,2,2,31,PLAIN)==nil
            and roads.Patch2("short",KEY,6,2,2,79,PLAIN)==nil and roads.Patch2(NEW,KEY,6,2,2,79,nil)==nil)
        local function refused(vertexCount,polygons,portals,rawBytes,text)
            assert(roads.Patch2(NEW,5,vertexCount,polygons,portals,rawBytes,text))
            return rows(NEW,5)==nil
        end
        check("a cell whose declared size is wrong is refused",refused(6,2,2,80,PLAIN) and refused(6,2,2,78,PLAIN))
        check("a cell with fewer vertices than it uses is refused",refused(5,2,2,79,PLAIN))
        check("a cell with more polygons than it holds is refused",refused(6,3,2,79,PLAIN))
        check("a cell with fewer polygons than it holds is refused",refused(6,1,2,79,PLAIN))
        check("a cell whose portal count is wrong is refused",refused(6,2,3,79,PLAIN))
        check("damaged text is refused",refused(6,2,2,79,PLAIN:sub(1,40)..PLAIN:sub(45)) and refused(6,2,2,79,"!!!!"))
    end)
    RikUI,C_EncodingUtil,Enum=old,oldUtil,oldEnum
    check("road patch fixture completes",ok,err)
end
