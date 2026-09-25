-- Shared constraints for restored and portable UI preferences.
local service = {}
RikUI.ProfileSchema = service
local function number(low, high, whole)
    return function(value)
        return type(value) == "number" and value >= low and value <= high and (not whole or value % 1 == 0)
    end
end
local function fontChoice(value) return value == "bundled" or value == "game" end
local function textMode(value) return value == "both" or value == "current" or value == "hidden" end
local function boolean(value) return type(value) == "boolean" end
local function identifier(value)
    return type(value) == "string" and #value <= 64 and value:match("^[%w_.-]+$") ~= nil
end
local anchors = { TOP=true, BOTTOM=true, LEFT=true, RIGHT=true, CENTER=true,
    TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true }
local function anchor(value) return type(value) == "string" and anchors[value] == true end
local schema = {
    scale=number(0.25,3), textScale=number(0.85,1.3), font=fontChoice, reducedMotion=boolean, gryphons=boolean, showEmptySlots=boolean, showHotkeys=boolean, showCooldownNumbers=boolean, ghosts=boolean, showStockBars=boolean, lootAtCursor=boolean,
    modules={ wildcard=boolean },
    positions={ wildcard={ point=anchor, relativePoint=anchor, x=number(-32768,32768), y=number(-32768,32768) } },
    borderColor={ [1]=number(0,1), [2]=number(0,1), [3]=number(0,1) },
    barFade={ main=boolean, bar2=boolean, bar3=boolean, bar4=boolean, bar5=boolean },
    tooltip={ itemID=boolean, spellID=boolean, itemLevel=boolean, hideInCombat=boolean, ownedCounts=boolean, followCursor=boolean, scale=number(0.75,1.5) },
    chat={ fontSize=number(10,24), size={ width=number(250,1200), height=number(120,800) } },
    panels={ questTextSize=function(value) return value == 0 or number(12,24,true)(value) end,
        skins={ character=boolean, spells=boolean, quests=boolean, professions=boolean, commerce=boolean, maps=boolean } },
    bags={ autoRepair=boolean, itemLevels=boolean, repairGuild=boolean, autoSellJunk=boolean, columns=number(10,16,true), capacityHUD=boolean,
        capacityLowOnly=boolean, capacityThreshold=number(0,20,true) },
    durability={ showPercent=boolean },
    questtracker={ collapsed=boolean, collapseInCombat=boolean, hideCompleted=boolean, readyFirst=boolean },
    minimap={ serverTime=boolean, coordinates=boolean, dayNight=boolean },
    swingtimer={ kiting=boolean, stopLead=number(0.1,1.5) },
    druidmana={ show=boolean }, worldmap={ fog=boolean }, nameplates={ healthHeight=number(12,24,true), nameHeight=number(12,24,true), threatText=boolean, selectedScale=number(1,1.5), otherAlpha=number(0.2,1) },
    unitframes={ healthText=textMode, powerText=textMode },
    castbars={ widthScale=number(0.75,1.5), height=number(16,36,true), timeText=boolean },
    xpbar={ compact=boolean, text=boolean, animations=boolean, ticks=boolean },
}
for _, key in ipairs({ "timestamps", "locked", "panel", "classColors", "shortTags", "mentions", "collapseRepeats",
    "jumpButton", "history", "arrowHistory", "stickyChannels", "channelStrip", "editColor", "tabsVisible", "nameClicks" }) do
    schema.chat[key] = boolean
end

local function visit(value, spec, path, exporting)
    if type(spec) == "function" then
        if not spec(value) then error(path .. ": invalid value", 0) end
        return value
    end
    if type(value) ~= "table" or getmetatable(value) ~= nil then error(path .. ": expected plain settings", 0) end
    local result = {}
    for key, entry in pairs(value) do
        local child = spec[key] or (spec.wildcard and identifier(key) and spec.wildcard)
        if child then result[key] = visit(entry, child, path .. "." .. tostring(key), exporting)
        elseif not exporting then error(path .. ": unknown field " .. tostring(key), 0) end
    end
    if spec.point and (not result.point or not result.relativePoint or result.x == nil or result.y == nil) then
        error(path .. ": incomplete anchor", 0)
    end
    if spec[1] and (result[1] == nil or result[2] == nil or result[3] == nil) then error(path .. ": incomplete colour", 0) end
    if spec.width and (result.width == nil or result.height == nil) then error(path .. ": incomplete size", 0) end
    return result
end


function service.Project(value, exporting)
    return visit(value, schema, "profile", exporting)
end

local function repair(value, spec, defaults)
    if type(spec) == "function" then
        if spec(value) then return value end
        return defaults
    end
    if type(value) ~= "table" or getmetatable(value) then return nil end
    for key, entry in pairs(value) do
        local child = spec[key] or (spec.wildcard and identifier(key) and spec.wildcard)
        local default
        if type(defaults) == "table" then default = defaults[key] end
        if child then value[key] = repair(entry, child, default) end
    end
    -- These optional structures must be complete; saved anchors may remain partial.
    if spec[1] and (value[1] == nil or value[2] == nil or value[3] == nil) then return nil end
    if spec.width and (value.width == nil or value.height == nil) then return nil end
    return value
end

function service.Repair(value, defaults)
    return repair(value, schema, defaults)
end

