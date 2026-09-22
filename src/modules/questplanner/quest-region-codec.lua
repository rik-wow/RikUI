-- Numeric source pages are data, never Lua evaluation. Decode one bounded polygon at a time.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local codec={}
planner.RegionCodec=codec
function codec.Decode(line,admitted,regionCount)
    if type(line)~="string" or #line>16384 or #line==0 or line:find("[^%d%,%.%-%+eE]")
        or line:sub(1,1)=="," or line:sub(-1)=="," or line:find(",,",1,true) then return nil,"invalid regional record" end
    local values={}
    for text in line:gmatch("[^,]+") do
        local n=tonumber(text)
        if not n or n~=n or n==math.huge or n==-math.huge or #values>=280 then return nil,"invalid regional number" end
        values[#values+1]=n
    end
    local id,vertices,edges=values[1],values[2],values[3]
    if not schema.Integer(id,1,2147483647) or not schema.Integer(vertices,3,6) or not schema.Integer(edges,0,32)
        or #values~=3+vertices*3+edges*8 then return nil,"regional polygon shape" end
    local row={id=id,points={},portals={}};local at=4
    local function point()
        local p={values[at],values[at+1],values[at+2]};at=at+3
        for _,v in ipairs(p) do if not schema.Number(v,-100000,100000) then return nil end end
        return p
    end
    for i=1,vertices do row.points[i]=point();if not row.points[i] then return nil,"regional point" end end
    for _=1,edges do
        local target,owner=values[at],values[at+1];at=at+2
        local left,right=point(),point()
        if not schema.Integer(target,1,2147483647) or not schema.Integer(owner,1,regionCount)
            or not left or not right then return nil,"regional portal" end
        if admitted[owner] then row.portals[#row.portals+1]={to=target,left=left,right=right} end
    end
    return row,edges
end
function codec.Stream(ids,records,admitted,identity,regionCount)
    local region,page,offset=1,1,1
    return function()
        while region<=#ids do
            local pages=records[ids[region]]
            local payload=pages and pages[page]
            if not payload then region,page,offset=region+1,1,1
            elseif offset>#payload then page,offset=page+1,1
            else
                local last=payload:find("\n",offset,true)
                if not last then error("regional record terminator") end
                local row,reason=codec.Decode(payload:sub(offset,last-1),admitted,regionCount)
                if not row then error(reason) end
                offset=last+1
                return {identity=identity,polygons={row}}
            end
        end
    end
end
