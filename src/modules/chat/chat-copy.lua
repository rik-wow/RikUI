-- Copy window and clickable addresses for the chat module. Lines come from GetMessageInfo with
-- secret strings skipped. Addresses become "addon" hyperlinks: on 69913 SetItemRef hands that link
-- type to EventRegistry and stops, so a click never reaches the item tooltip.
local core, media, ui = RikUI, RikUI.Media, RikUI.UI
local chat = core.Chat

local WINDOW_NAME, WIDTH, HEIGHT, PAD, TITLE_HEIGHT, CLOSE_SIZE, EDGE = "RikUIChatCopy", 560, 400, 8, 24, 18, 1
local BACKGROUND, BORDER = { 0.03, 0.035, 0.045, 0.97 }, { 0.25, 0.28, 0.32, 1 }
local SCROLL_STEP, TEXT_FLAGS = 40, ""
local COPY_TITLE, LINK_TITLE = "Chat copy: ", "Link"
local LINK_PREFIX, LINK_COLOR, LINK_EVENT = "addon:RikUI:", "|cff4e96f7", "SetItemRef"
local LINK_PATTERN = "^" .. LINK_PREFIX .. "(.+)$"
local HYPERLINK = "|H.-|h.-|h"
-- The frontier keeps a match at the start of a word, so "xhttp://" and the "www" inside a linked
-- "https://www" are skipped. %w rather than %S: Lua treats the start of the string as a NUL byte,
-- which %S matches.
local URL_PATTERNS, TRAILING = { "%f[%w]https?://%S+", "%f[%w]www%.%S+" }, "[%.,;:!%?%)%]]+$"
local STRIP = { { "|T.-|t", "" }, { "|A.-|a", "" }, { "|H.-|h(.-)|h", "%1" }, { "|c%x%x%x%x%x%x%x%x", "" }, { "|r", "" } }
local EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_SYSTEM" }
local window

local function usable(text)
    return not core.Secret.IsSecret(text) and type(text) == "string"
end

local function linkFor(address)
    local trail = address:match(TRAILING) or ""
    address = address:sub(1, #address - #trail)
    return LINK_COLOR .. "|H" .. LINK_PREFIX .. address .. "|h[" .. address .. "]|h|r" .. trail
end

local function linkifyPlain(text)
    for _, pattern in ipairs(URL_PATTERNS) do text = text:gsub(pattern, linkFor) end
    return text
end

-- Existing hyperlinks pass through whole; only the text between them goes through the rewrite.
function chat.MapPlain(text, rewrite)
    local parts, position = {}, 1
    while true do
        local start, stop = text:find(HYPERLINK, position)
        if not start then break end
        parts[#parts + 1] = rewrite(text:sub(position, start - 1))
        parts[#parts + 1] = text:sub(start, stop)
        position = stop + 1
    end
    parts[#parts + 1] = rewrite(text:sub(position))
    return table.concat(parts)
end

function chat.Linkify(text) return chat.MapPlain(text, linkifyPlain) end

-- Filter contract on 69913: discard flag first; a second value replaces the whole argument list.
local function filter(_, _, message, ...)
    if not usable(message) then return false end
    local linked = chat.Linkify(message)
    if linked == message then return false end
    return false, linked, ...
end

-- The 69913 registry, or its deprecated alias; nil on a client with neither.
function chat.FilterAdder()
    local add = type(ChatFrameUtil) == "table" and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    return type(add) == "function" and add or nil
end

local function registerFilters()
    local add = chat.FilterAdder()
    if not add then
        chat.Warn("links", "message filters unavailable on this client")
        return false
    end
    for _, event in ipairs(EVENTS) do add(event, filter) end
    return true
end

local function onLink(_, link)
    if not usable(link) then return end
    local address = link:match(LINK_PATTERN)
    if address then chat.OpenCopy(nil, address) end
end

local function registerClicks()
    if type(EventRegistry) ~= "table" or type(EventRegistry.RegisterCallback) ~= "function" then
        chat.Warn("clicks", "EventRegistry unavailable on this client")
        return false
    end
    EventRegistry:RegisterCallback(LINK_EVENT, onLink, chat)
    return true
end

function chat.EnableLinks()
    local filters, clicks = registerFilters(), registerClicks()
    chat.LinksReady = filters and clicks
end

local function plain(text)
    for _, rule in ipairs(STRIP) do text = text:gsub(rule[1], rule[2]) end
    return text
end

local function readLines(frame)
    local lines = {}
    for index = 1, frame:GetNumMessages() do
        local text = frame:GetMessageInfo(index)
        if usable(text) then lines[#lines + 1] = plain(text) end
    end
    return table.concat(lines, "\n")
end

function chat.PlainText(frame)
    local ok, text = pcall(readLines, frame)
    if ok then return text end
    chat.Warn("copy", text)
    return ""
end

-- Whisper tabs can carry a secret name; those fall back to the frame's own name.
local function frameTitle(frame)
    local tab = _G[frame:GetName() .. "Tab"]
    local label = type(tab) == "table" and type(tab.Text) == "table" and tab.Text:GetText() or nil
    if not usable(label) or label == "" then label = frame:GetName() end
    return COPY_TITLE .. label
end

local function scrollWheel(self, delta)
    local current, range = self:GetVerticalScroll(), self:GetVerticalScrollRange()
    if type(current) ~= "number" or type(range) ~= "number" then return end
    self:SetVerticalScroll(math.max(0, math.min(range, current - delta * SCROLL_STEP)))
end

function chat.CloseCopy()
    if not window then return end
    window.edit:ClearFocus()
    if window.search then window.search:ClearFocus() end
    window:Hide()
end

local function createClose()
    local close = CreateFrame("Button", nil, window)
    close:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -PAD / 2)
    close.icon = media.Icon(close, "close", 10, "OVERLAY")
    close.icon:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetHighlightTexture(media.highlight, "ADD")
    close:SetScript("OnClick", chat.CloseCopy)
    return close
end

function chat.ApplyCopySearch()
    if not window then return end
    local query=window.search:GetText() or ""
    if not usable(query) then return end
    query=query:lower()
    local lines,total={},0
    for line in ((window.snapshot or "").."\n"):gmatch("(.-)\n") do
        if line~="" then
            total=total+1
            if query=="" or line:lower():find(query,1,true) then lines[#lines+1]=line end
        end
    end
    window.edit:SetText(query=="" and (window.snapshot or "") or table.concat(lines,"\n"))
    window.count:SetText(#lines.." / "..total.." lines")
    window.scroll:SetVerticalScroll(0)
end

function chat.RefreshCopy()
    if not window or not window.source then return end
    window.snapshot=chat.PlainText(window.source)
    chat.ApplyCopySearch()
end

local function createSearch()
    local label=window:CreateFontString(nil,"OVERLAY")
    media.Font(label,"label");label:SetText("Search")
    label:SetPoint("TOPLEFT",window,"TOPLEFT",PAD,-32)
    local search=CreateFrame("EditBox",nil,window)
    search:SetSize(180,22);search:SetPoint("TOPLEFT",window,"TOPLEFT",64,-28)
    search:SetAutoFocus(false);search:SetFont(media.font,media.Size("label"),TEXT_FLAGS)
    search:SetMaxLetters(128)
    chat.Flat(search,BACKGROUND)
    search:SetScript("OnTextChanged",chat.ApplyCopySearch)
    search:SetScript("OnEscapePressed",chat.CloseCopy)
    search:SetScript("OnEnterPressed",function() search:ClearFocus();window.edit:SetFocus();window.edit:HighlightText() end)
    window.search=search
    local clear=CreateFrame("Button",nil,window)
    clear:SetSize(48,22);clear:SetPoint("LEFT",search,"RIGHT",8,0)
    clear:SetNormalFontObject(GameFontNormal);clear:SetText("Clear")
    clear:SetHighlightTexture(media.highlight,"ADD")
    clear:SetScript("OnClick",function() search:SetText("");chat.ApplyCopySearch();search:SetFocus() end)
    window.clear=clear
    window.count=window:CreateFontString(nil,"OVERLAY");media.Font(window.count,"label")
    window.count:SetPoint("LEFT",clear,"RIGHT",8,0)
    local refresh=CreateFrame("Button",nil,window)
    refresh:SetSize(70,22);refresh:SetPoint("TOPRIGHT",window,"TOPRIGHT",-PAD,-28)
    refresh:SetNormalFontObject(GameFontNormal);refresh:SetText("Refresh")
    refresh:SetHighlightTexture(media.highlight,"ADD")
    refresh:SetScript("OnClick",chat.RefreshCopy)
    window.refresh=refresh
end

local function createEdit()
    local scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -(PAD + TITLE_HEIGHT + 28))
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, PAD)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", scrollWheel)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetWidth(WIDTH - 2 * PAD)
    edit:SetFont(media.font, media.Size("label"), TEXT_FLAGS)
    edit:SetScript("OnEscapePressed", chat.CloseCopy)
    scroll:SetScrollChild(edit)
    return scroll, edit
end

local function createWindow()
    window = CreateFrame("Frame", WINDOW_NAME, UIParent)
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window.rikBackground = window:CreateTexture(nil, "BACKGROUND")
    window.rikBackground:SetAllPoints()
    window.rikBackground:SetColorTexture(unpack(BACKGROUND))
    window.rikBorder = ui.Edges(window, EDGE, "BORDER")
    for _, line in ipairs(window.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    window.title = window:CreateFontString(nil, "OVERLAY")
    media.Font(window.title, "label")
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -PAD)
    window.close = createClose()
    window.scroll, window.edit = createEdit()
    createSearch()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, WINDOW_NAME) end
    window:Hide()
    core.Motion.BindEntrance(window, true)
    chat.Window = window
end

-- With a frame: that frame's lines. With text alone: the text, for an address link.
function chat.OpenCopy(frame, text)
    if not window then createWindow() end
    window.title:SetText(frame and frameTitle(frame) or LINK_TITLE)
    window.source=text==nil and frame or nil
    window.refresh:SetShown(window.source~=nil)
    window.snapshot=text or chat.PlainText(frame)
    window.search:SetText("")
    chat.ApplyCopySearch()
    window:Show()
    window.edit:SetFocus()
    window.edit:HighlightText()
end
