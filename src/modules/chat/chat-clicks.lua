-- Modifier clicks on a name in chat: Alt invites, Ctrl runs a who. A post-hook on SetItemRef sees
-- every link click after Blizzard handled it. Blizzard's plain left click on a player link opens a
-- whisper to them, which also happens with Alt or Ctrl held, so that edit box is closed again when
-- nothing has been typed in it. Shift-click and right-click stay Blizzard's.
local core = RikUI
local chat = core.Chat

local PLAYER_LINK, LEFT_BUTTON = "^player:([^:]+)", "LeftButton"
local WHO_FORMAT = "n-\"%s\""

local function enabled() return chat.Settings().nameClicks ~= false end

local function held(name)
    local reader = _G[name]
    return type(reader) == "function" and reader() == true
end

local function call(namespace, method, argument)
    local api = _G[namespace]
    if type(api) ~= "table" or type(api[method]) ~= "function" then return false end
    local ok, reason = pcall(api[method], argument)
    if not ok then chat.Warn("name click", reason) end
    return ok
end

local function closeEmptyWhisper()
    local util = ChatFrameUtil
    if type(util) ~= "table" or type(util.GetActiveWindow) ~= "function" or type(util.DeactivateChat) ~= "function" then return end
    local box = util.GetActiveWindow()
    if chat.IsFrame(box) and box:GetText() == "" then util.DeactivateChat(box) end
end

local function onLink(link, _, button)
    if not enabled() or button ~= LEFT_BUTTON or core.Secret.IsSecret(link) or type(link) ~= "string" then return end
    local name = link:match(PLAYER_LINK)
    if not name then return end
    local acted = false
    if held("IsAltKeyDown") then
        acted = call("C_PartyInfo", "InviteUnit", name)
    elseif held("IsControlKeyDown") then
        acted = call("C_FriendList", "SendWho", WHO_FORMAT:format(name:match("^[^-]+")))
    end
    if acted then closeEmptyWhisper() end
end

function chat.SetNameClicks(value)
    chat.Settings().nameClicks = value == true
    return true
end

function chat.EnableClicks()
    if type(SetItemRef) == "function" then hooksecurefunc("SetItemRef", onLink) end
end

table.insert(chat.Options.settings, { type = "checkbox", key = "nameClicks", label = "Alt-click a name to invite, Ctrl-click for who",
    get = enabled, set = chat.SetNameClicks })
