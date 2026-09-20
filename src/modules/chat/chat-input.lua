-- Typing. Up and Down recall sent lines without holding Alt (the edit box's own
-- SetAltArrowKeyMode), and chat types Blizzard resets after every send stay selected: the edit box
-- reads ChatTypeInfo[type].sticky when a line is sent. Blizzard's values are kept and written back
-- when the option is switched off.
local core = RikUI
local chat = core.Chat

local STICKY = 1
local STICKY_TYPES = { "PARTY", "RAID", "INSTANCE_CHAT", "GUILD", "OFFICER", "WHISPER", "BN_WHISPER", "CHANNEL" }
local stock = {}

local function arrowHistory() return chat.Settings().arrowHistory ~= false end
local function stickyChannels() return chat.Settings().stickyChannels ~= false end

function chat.ApplyArrowKeys()
    for frame in pairs(chat.Frames) do
        local box = frame.editBox
        if chat.IsFrame(box) and type(box.SetAltArrowKeyMode) == "function" then box:SetAltArrowKeyMode(not arrowHistory()) end
    end
end

function chat.ApplySticky()
    if type(ChatTypeInfo) ~= "table" then return end
    local wanted = stickyChannels()
    for _, kind in ipairs(STICKY_TYPES) do
        local info = ChatTypeInfo[kind]
        if type(info) == "table" then
            if wanted and stock[kind] == nil then
                stock[kind] = { value = info.sticky }
                info.sticky = STICKY
            elseif not wanted and stock[kind] then
                info.sticky = stock[kind].value
                stock[kind] = nil
            end
        end
    end
end

local function setter(key, apply)
    return function(value)
        chat.Settings()[key] = value == true
        apply()
        return true
    end
end

function chat.EnableInput()
    chat.ApplyArrowKeys()
    chat.ApplySticky()
end

table.insert(chat.Options.settings, { type = "checkbox", key = "arrowHistory", label = "Up and Down recall sent lines without Alt",
    get = arrowHistory, set = setter("arrowHistory", chat.ApplyArrowKeys) })
table.insert(chat.Options.settings, { type = "checkbox", key = "stickyChannels", label = "Stay on the last channel used",
    get = stickyChannels, set = setter("stickyChannels", chat.ApplySticky) })
