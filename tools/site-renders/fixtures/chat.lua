-- Chat history, input, scrolling and chat bubbles.

-- Chat lines the way the client formats them, through AddMessage; RikUI's line filters then
-- shorten tags, colour names and add timestamps as configured.
local function chatColor(kind)
    local info = ChatTypeInfo and ChatTypeInfo[kind]
    if info then return info.r, info.g, info.b end
    return 1, 1, 1
end

local CHAT_SAMPLE = {
    { "SYSTEM", "Quest accepted: Kobold Camp Cleanup" },
    { "SAY", "|Hplayer:Mira|h[Mira]|h says: Anyone heading to the Deadmines later?" },
    { "PARTY", "|Hchannel:PARTY|h[Party]|h |Hplayer:Mira|h[Mira]|h: Meet at the inn first." },
    { "PARTY", "|Hchannel:PARTY|h[Party]|h |Hplayer:Rik|h[Rik]|h: On my way." },
    { "GUILD", "|Hchannel:GUILD|h[Guild]|h |Hplayer:Toddrick|h[Toddrick]|h: Grats on 10!" },
    { "WHISPER", "|Hplayer:Mira|h[Mira]|h whispers: Do you still need linen?" },
    { "CHANNEL", "|Hchannel:channel:1|h[1. General]|h |Hplayer:Remy|h[Remy]|h: WTS Linen Cloth, 10s a stack" },
    { "LOOT", "You receive loot: |cffffffff|Hitem:118|h[Minor Healing Potion]|h|rx2." },
}

function RikRenderChatLines(lines)
    -- Lines fade two minutes after they arrive in the client; these have just arrived.
    ChatFrame1:SetFading(false)
    for _, line in ipairs(lines or CHAT_SAMPLE) do
        ChatFrame1:AddMessage(line[2], chatColor(line[1]))
    end
end

-- The edit box open on a channel, with text typed.
function RikRenderChatInput(text, chatType)
    local box = ChatFrame1EditBox
    box:SetAttribute("chatType", chatType or "PARTY")
    if ChatEdit_UpdateHeader then pcall(ChatEdit_UpdateHeader, box) end
    box:Show()
    box:SetText(text or "")
    box:SetFocus()
    box:SetAlpha(1)
    if RikUI.Chat.RefreshInputLayout then RikUI.Chat.RefreshInputLayout() end
    return box
end

-- Scrolled up: the jump-to-newest button appears.
function RikRenderChatScrolled()
    for _ = 1, 3 do ChatFrame1:ScrollUp() end
    local handler = ChatFrame1:GetScript("OnScrollChanged") or ChatFrame1:GetScript("OnMessageScrollChanged")
    if handler then handler(ChatFrame1) end
end

-- Chat bubbles: the engine pools its bubbles and lists them through C_ChatBubbles. A bubble here
-- is Blizzard's ChatBubbleTemplate under a holder, listed the same way, over a named actor.
local bubbles = {}

function RikRenderBubble(name, text, actorName, nth, dx, dy)
    local actor = type(actorName) == "table" and actorName or RikRenderActor(actorName, nth)
    local bubble = CreateFrame("Frame", name, UIParent)
    bubble:SetSize(1, 1)
    bubble:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", actor.x + (dx or 0), RikRenderWorld.height - actor.y + (dy or 44))
    local frame = CreateFrame("Frame", nil, bubble, "ChatBubbleTemplate")
    frame.String:SetWidth(0)
    frame.String:SetText(text)
    frame.String:ClearAllPoints()
    frame.String:SetPoint("BOTTOM", bubble, "TOP", 0, 16)
    bubbles[#bubbles + 1] = bubble
    C_ChatBubbles.GetAllChatBubbles = function() return bubbles end
    A_Admin.FireEvent("CHAT_MSG_SAY", text, actorName)
    local scanner = RikUI.ChatBubbles.Scanner
    local handler = scanner and scanner:GetScript("OnUpdate")
    if handler then handler(scanner, 1) end
    return bubble
end
