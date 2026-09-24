return function(check)
    local previous = RikUI
    RikUI = { Presets = {} }
    dofile("src/persistence/codec.lua")
    for _, class in ipairs({ "warrior", "hunter", "mage", "rogue", "priest", "warlock", "shaman", "paladin", "druid" }) do
        dofile("presets/" .. class .. ".lua")
    end
    local codec = RikUI.Codec
    local function equal(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    for class, preset in pairs(RikUI.Presets) do
        local text = RikUI.Serialize and RikUI.Serialize(preset)
        check("strict codec round-trips complete " .. class .. " preset", text and equal(preset, RikUI.Deserialize(text)))
    end
    check("strict encoding rejects functions instead of dropping them", codec.Encode({ x = function() end }, true) == nil)
    check("strict encoding rejects non-scalar keys", codec.Encode({ [{}] = 1 }, true) == nil)
    check("strict encoding rejects metatables", codec.Encode(setmetatable({}, {}), true) == nil)
    local text = codec.Encode({ chatHistory = { "literal field" } }, true)
    check("strict encoding keeps all supported fields", codec.Decode(text).chatHistory ~= nil)
    check("legacy encoding retains filtering", codec.Decode(codec.Encode({ x = function() end, keep = false })).keep == false
        and codec.Decode(codec.Encode({ chatHistory = {} })).chatHistory == nil)
    local cycle = {}; cycle.self = cycle
    check("strict codec rejects cycles", codec.Encode(cycle, true) == nil)
    check("strict codec rejects oversized values", codec.Encode({ x = string.rep("a", 21601) }, true) == nil)
    check("strict codec rejects excessive nesting", codec.Decode(string.rep("Ts1zx", 33) .. "t" .. string.rep("E", 33)) == nil)
    check("strict codec rejects trailing and executable input", codec.Decode("TEx") == nil and codec.Decode("return {}") == nil)
    local value = { [12] = "\000\255\n|quote\"", nested = { yes = true, no = false }, n = 1.23456789012345 }
    check("strict codec preserves binary strings and precision", equal(value, codec.Decode(codec.Encode(value, true))))
    RikUI = previous
end
