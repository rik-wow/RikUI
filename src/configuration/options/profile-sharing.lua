-- Portable UI preferences only: no account/character records, history or undo journals.
local core, sharing = RikUI, RikUI.Sharing
local function number(low, high, whole)
    return function(value)
        return type(value) == "number" and value >= low and value <= high and (not whole or value % 1 == 0)
    end
end
local function boolean(value) return type(value) == "boolean" end
local function identifier(value)
    return type(value) == "string" and #value <= 64 and value:match("^[%w_.-]+$") ~= nil
end
local anchors = { TOP=true, BOTTOM=true, LEFT=true, RIGHT=true, CENTER=true,
    TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true }
local function anchor(value) return type(value) == "string" and anchors[value] == true end
local schema = {
    scale=number(0.25,3), textScale=number(0.85,1.3), gryphons=boolean, ghosts=boolean, showStockBars=boolean, lootAtCursor=boolean,
    modules={ wildcard=boolean },
    positions={ wildcard={ point=anchor, relativePoint=anchor, x=number(-32768,32768), y=number(-32768,32768) } },
    borderColor={ [1]=number(0,1), [2]=number(0,1), [3]=number(0,1) },
    barFade={ main=boolean, bar2=boolean, bar3=boolean, bar4=boolean, bar5=boolean },
    tooltip={ hideInCombat=boolean, ownedCounts=boolean, followCursor=boolean },
    chat={ fontSize=number(10,24), size={ width=number(250,1200), height=number(120,800) } },
    bags={ autoRepair=boolean, columns=number(10,16,true) },
    questtracker={ collapsed=boolean, collapseInCombat=boolean, hideCompleted=boolean, readyFirst=boolean },
    minimap={ serverTime=boolean, coordinates=boolean, dayNight=boolean },
    swingtimer={ kiting=boolean, stopLead=number(0.1,1.5) },
    druidmana={ show=boolean }, worldmap={ fog=boolean }, nameplates={ threatText=boolean },
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

function sharing.ExportProfile()
    if not core.Profile then return nil, "Still loading." end
    local ok, value = pcall(visit, core.Profile, schema, "profile", true)
    if not ok then return nil, value end
    return sharing.Encode("profile", value)
end

function sharing.ImportProfile(name, text)
    if InCombatLockdown() then return nil, "Cannot import a profile in combat." end
    if not core.DB then return nil, "Still loading." end
    if type(name) ~= "string" or #name == 0 or #name > 64 or not name:match("^%S")
        or not name:match("%S$") or name:find("[%c|]") then return nil, "Use a new name of 1..64 characters without markup." end
    if core.DB.profiles[name] ~= nil then return nil, "Profile already exists: " .. name end
    local value, reason = sharing.Decode(text, "profile")
    if not value then return nil, reason end
    local ok, profile = pcall(visit, value, schema, "profile", false)
    if not ok then return nil, profile end
    core.DB.profiles[name] = profile
    core:Changed()
    return true
end

function sharing.OpenProfileExport()
    local text, reason = sharing.ExportProfile()
    if not text then core:Print(reason); return nil end
    return sharing.OpenDialog("Export UI profile", text, nil,
        "Copy with Ctrl-C. Shares UI preferences and frame positions; excludes chat history and character data.")
end

function sharing.OpenProfileImport()
    return sharing.OpenDialog("Import UI profile", nil, sharing.ImportProfile,
        "Enter a new profile name and paste below. Your current profile stays selected.",
        "Saved. Select the new profile in Profiles, then reload to apply all module settings.")
end

core:RegisterCommand("profileexport", function() sharing.OpenProfileExport() end, "Copy UI preferences: /rik profileexport")
core:RegisterCommand("profileimport", function() sharing.OpenProfileImport() end, "Import UI preferences: /rik profileimport")
