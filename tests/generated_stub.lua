-- Host-side loader for RikUI's generated data layout, shared by replay scripts.
-- Base(root)        : the directory holding generated/ (an installed RikUI folder,
--                     an AddOns root containing RikUI, or a compiler output dir).
-- Load(base, which) : runs every Lua file listed by generated/<family>/<family>.xml,
--                     as the client does at addon load. Returns counts and timings.
-- PatchLoader(root) : a C_AddOns.LoadAddOn stand-in for the LoadOnDemand patch
--                     packs beside RikUI, reading <root>/<name>/<name>.toc.
local M={}
local FAMILIES={"roads","corpus"}

local function exists(path)
    local f=io.open(path,"r");if f then f:close();return true end;return false
end

function M.Base(root)
    root=root:gsub("\\","/"):gsub("/$","")
    for _,family in ipairs(FAMILIES) do
        if exists(root.."/generated/"..family.."/"..family..".xml") then return root end
    end
    return root.."/RikUI"
end

local function scripts(xmlPath)
    local f=io.open(xmlPath,"r");if not f then return nil end
    local text=f:read("*a");f:close()
    local out={}
    for file in text:gmatch('<Script%s+file="([^"]+)"') do out[#out+1]=file:gsub("\\","/") end
    return out
end

function M.Load(base,which)
    base=base:gsub("\\","/"):gsub("/$","")
    local loaded,stats={},{files=0,ms=0,peakMS=0}
    for _,family in ipairs(which or FAMILIES) do
        local dir=base.."/generated/"..family
        local list=scripts(dir.."/"..family..".xml")
        if list then
            for _,file in ipairs(list) do
                assert(file:match("^[%w_%-]+%.lua$"),"unsafe generated path: "..file)
                local began=os.clock()
                assert(loadfile(dir.."/"..file))()
                local ms=(os.clock()-began)*1000
                stats.files=stats.files+1;stats.ms=stats.ms+ms;stats.peakMS=math.max(stats.peakMS,ms)
            end
            loaded[family]=#list
        end
    end
    return loaded,stats
end

function M.PatchLoader(root,onLoad)
    root=root:gsub("\\","/"):gsub("/$","")
    local loaded={}
    return function(name)
        assert(type(name)=="string" and name:match("^[%w_]+$"),"unsafe addon name")
        if loaded[name] then return true end
        local toc=io.open(root.."/"..name.."/"..name..".toc","r")
        if not toc then return false,"MISSING" end
        local began=os.clock()
        for line in toc:lines() do
            line=line:gsub("\r",""):match("^%s*(.-)%s*$")
            if line~="" and line:sub(1,1)~="#" then
                assert(line:match("^[%w_.%-]+%.lua$"),"unsafe addon file: "..line)
                assert(loadfile(root.."/"..name.."/"..line))()
            end
        end
        toc:close();loaded[name]=true
        if onLoad then onLoad(name,(os.clock()-began)*1000) end
        return true
    end
end

return M
