-- Offline synthetic protocol probe. No client API or native UI is used.
RikUI = { Secret = { IsSecret = function() return false end } }
dofile(arg[1])
dofile(arg[2])
local transfer = RikUI.QuestPlanner.Transfer
if arg[3] == "encode" then
    local observation = {
        identity = { product = "forever", build = "1.60.1.69913", locale = "enUS" },
        order = { 98319, 96608 }, observedCount = 2, reportedCount = 2,
        coverage = "log-complete", origin = "local-session", fixture = true,
        quests = {
            [98319] = { id = 98319, title = "Synthetic fixture A\tB\nC", level = 7, objectivesComplete = false, objectives = {} },
            [96608] = { id = 96608, title = "Synthetic fixture " .. string.char(195,169) .. " |Hlink|h : " .. string.char(0),
                objectivesComplete = true, objectives = { { text = "Synthetic objective", numFulfilled = 2, numRequired = 3 } } },
        },
        mixed = { [1] = "numeric key", ["1"] = "string key", [string.char(255)] = string.char(254,0,255) },
        numbers = { -2147483647, 2147483647, -0.0, 2^-1074 },
    }
    math.randomseed(8675309)
    for index = 1, 1024 do
        observation.numbers[#observation.numbers + 1] = ((index % 2 == 0) and 1 or -1) * math.random() * 2147483647 / 10^math.random(0, 300)
    end
    io.write(assert(transfer.Encode(observation)), "\n")
elseif arg[3] == "decode" then
    for packet in io.lines(arg[4]) do
        local restored = transfer.Decode(packet)
        assert(not restored or restored.origin == "imported-untrusted")
        io.write(restored and "1\n" or "0\n")
    end
else
    error("expected encode or decode mode")
end
