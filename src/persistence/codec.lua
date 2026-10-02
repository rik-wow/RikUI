-- Deterministic bounded settings codec shared by the CVar and macro stores.
-- The dictionary is append-only; valid v2 output remains byte-for-byte compatible.
local codec = {}
RikUI.Codec = codec
local MAX_DEPTH, MAX_NODES, MAX_TEXT = 32, 8192, 21600
local SKIP_KEYS = { chatHistory = true }
local STORABLE = { number = true, string = true, boolean = true, table = true }

local WORDS = { "point", "relativePoint", "x", "y", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT",
    "BOTTOMLEFT", "BOTTOMRIGHT", "positions", "profiles", "Default", "modules", "chat", "size", "width", "height",
    "scale", "characters", "account", "wizardDone", "applied", "askRole", "profile", "class", "role", "at",
    "presetVersion", "version", "community", "layout", "base", "moved", "locked", "fontSize", "gryphons", "tooltip",
    "questtracker", "collapsed", "main", "bar2", "bar3", "bar4", "bar5", "stance", "pet", "xpbar", "player", "target",
    "focus", "tot", "petframe", "party", "raid", "castplayer", "casttarget", "castfocus", "castpet", "buffs", "debuffs",
    "minimap", "micromenu", "durability", "mirrortimers", "swingtimer", "combopoints", "totems", "questtimers", "loot",
    "bags", "damagemeter", "WARRIOR", "dps", "tank", "nameplateCVars" }
function codec.Checksum(text)
    local a, b = 1.0, 0.0 -- float arithmetic also preserves unsigned sums in the browser Lua VM
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

function codec.ChecksumHex(text)
    local sum = codec.Checksum(text)
    return string.format("%04x%04x", math.floor(sum / 65536), sum % 65536)
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local CODES = {}
for index, word in ipairs(WORDS) do
    local high, low = math.floor(index / 36), index % 36
    CODES[word] = DIGITS:sub(high + 1, high + 1) .. DIGITS:sub(low + 1, low + 1)
end


local function finite(value)
    return value == value and value > -math.huge and value < math.huge
end

local function armour(text)
    return (text:gsub("[^%w]", function(char) return string.format("_%02x", char:byte()) end))
end

local function unarmour(text)
    if text:gsub("_%x%x", ""):find("_", 1, true) then error("invalid settings escape", 0) end
    return (text:gsub("_(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function numberText(value)
    local short = tostring(value):gsub("%.0$", "")
    return tonumber(short) == value and short or string.format("%.17g", value)
end

local function sortedKeys(value, context)
    local keys = {}
    for key in pairs(value) do
        context.entries = context.entries + 1
        if context.entries > MAX_NODES then error("too many settings entries", 0) end
        local kind = type(key)
        if kind == "number" and not finite(key) then error("non-finite settings key", 0) end
        if context.strict and kind ~= "string" and kind ~= "number" then error("unsupported settings key", 0) end
        if kind == "string" or kind == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    return keys
end

local function append(out, context, text)
    context.bytes = context.bytes + #text
    if context.bytes > MAX_TEXT then error("settings text exceeds limit", 0) end
    out[#out + 1] = text
end

local write
local function writeTable(value, out, top, context, depth)
    if depth > MAX_DEPTH then error("settings nesting exceeds limit", 0) end
    if context.active[value] then error("cyclic settings table", 0) end
    if context.strict and getmetatable(value) ~= nil then error("settings metatables are unsupported", 0) end
    context.active[value] = true
    append(out, context, "T")
    for _, key in ipairs(sortedKeys(value, context)) do
        local entry = value[key]
        if context.strict and not STORABLE[type(entry)] then error("unsupported settings value", 0) end
        if STORABLE[type(entry)] and not (top and SKIP_KEYS[key] and not context.strict) then
            write(key, out, false, context, depth)
            write(entry, out, false, context, depth)
        end
    end
    append(out, context, "E")
    context.active[value] = nil
end

write = function(value, out, top, context, depth)
    context.nodes = context.nodes + 1
    if context.nodes > MAX_NODES then error("settings structure exceeds limit", 0) end
    local kind = type(value)
    if kind == "number" then
        if not finite(value) then error("non-finite settings number", 0) end
        append(out, context, "n" .. armour(numberText(value)) .. "z")
    elseif kind == "string" then
        if #value > MAX_TEXT then error("settings text exceeds limit", 0) end
        local safe = armour(value)
        append(out, context, CODES[value] and "k" .. CODES[value] or "s" .. #safe .. "z" .. safe)
    elseif kind == "boolean" then append(out, context, value and "t" or "f")
    elseif kind == "table" then writeTable(value, out, top, context, depth + 1)
    else error("unsupported settings value", 0) end
end

function codec.Encode(value, strict)
    local out, context = {}, { nodes = 0, entries = 0, bytes = 0, active = {}, strict = strict == true }
    local ok, reason = pcall(write, value, out, true, context, 0)
    if not ok then return nil, tostring(reason) end
    return table.concat(out)
end

local read
local function readTable(text, at, context, depth)
    if depth > MAX_DEPTH then return nil end
    local result = {}
    while text:sub(at, at) ~= "E" do
        if at > #text then return nil end
        local key, value
        key, at = read(text, at, context, depth)
        local kind = type(key)
        if kind ~= "string" and kind ~= "number" then return nil end
        if kind == "number" and not finite(key) then return nil end
        if result[key] ~= nil then return nil end
        value, at = read(text, at, context, depth)
        if value == nil then return nil end
        result[key] = value
    end
    return result, at + 1
end

local function readWord(text, at)
    if #text < at + 2 then return nil end
    local high = DIGITS:find(text:sub(at + 1, at + 1), 1, true)
    local low = DIGITS:find(text:sub(at + 2, at + 2), 1, true)
    local word = high and low and WORDS[(high - 1) * 36 + low - 1] or nil
    if word == nil then return nil end
    return word, at + 3
end

local function readScalar(text, at, tag)
    local stop = (tag == "n" or tag == "s") and text:find("z", at + 1, true) or nil
    if not stop then return nil end
    local encoded = text:sub(at + 1, stop - 1)
    if tag == "n" then
        local number = tonumber((unarmour(encoded)))
        if number == nil or not finite(number) then return nil end
        return number, stop + 1
    end
    if not encoded:match("^%d+$") then return nil end
    local length = tonumber(encoded)
    if not length or length > MAX_TEXT or stop + length > #text then return nil end
    return unarmour(text:sub(stop + 1, stop + length)), stop + length + 1
end

read = function(text, at, context, depth)
    context.nodes = context.nodes + 1
    if context.nodes > MAX_NODES then return nil end
    local tag = text:sub(at, at)
    if tag == "t" then return true, at + 1 end
    if tag == "f" then return false, at + 1 end
    if tag == "T" then return readTable(text, at + 1, context, depth + 1) end
    if tag == "k" then return readWord(text, at) end
    return readScalar(text, at, tag)
end

function RikUI.Serialize(value) return codec.Encode(value, true) end
function RikUI.Deserialize(text) return codec.Decode(text) end

function codec.Decode(text)
    if type(text) ~= "string" or text == "" or #text > MAX_TEXT or not text:match("^[%w_]+$") then
        return nil, "not store text"
    end
    local ok, value, stop = pcall(read, text, 1, { nodes = 0 }, 0)
    if not ok or value == nil or stop ~= #text + 1 then return nil, "damaged store text" end
    return value
end
