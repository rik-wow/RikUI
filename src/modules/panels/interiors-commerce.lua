local interiors, skin = RikUI.Interiors, RikUI.Skin
local LABELS = { "Name", "Sender", "Subject", "Money", "Amount", "Duration", "Count", "BagCost", "BagText" }
local ART = { "SlotTexture", "NameFrame", "Background", "Bg", "Left", "Middle", "Right" }

-- Old trade and inbox templates publish regions as globals instead of parent keys.
local function part(frame, key)
    if skin.IsRegion(frame[key]) then return frame[key] end
    local name = type(frame.GetName) == "function" and frame:GetName()
    return type(name) == "string" and _G[name .. key] or nil
end

local function mailDetails(frame)
    local sender, subject = part(frame, "Sender"), part(frame, "Subject")
    if not skin.IsRegion(sender) or not skin.IsRegion(subject)
        or type(sender.GetText) ~= "function" or type(subject.GetText) ~= "function" then return end
    local state = interiors.State(frame)
    if not state then return end
    state.subjectPlate = skin.TextPlate(frame, subject, { 0.13, 0.12, 0.085, 0.8 }, 3)
    if not state.mailRule then
        state.mailRule = frame:CreateTexture(nil, "BORDER")
        state.mailRule:SetTexture(skin.FLAT)
        state.mailRule:SetVertexColor(0.7, 0.57, 0.3, 0.8)
        state.mailRule:SetPoint("TOPLEFT", state.subjectPlate, "TOPLEFT")
        state.mailRule:SetPoint("BOTTOMLEFT", state.subjectPlate, "BOTTOMLEFT")
        state.mailRule:SetWidth(1)
    end
    state.mailRule:SetShown(state.subjectPlate:IsShown())
    state.durationPlate = skin.TextPlate(frame, part(frame, "Duration"), nil, 3)
end

local function commerce(frame)
    local icon = interiors.Icon(frame)
    if skin.IsRegion(icon) then interiors.Item(frame) end
    local isRow = skin.IsRegion(part(frame, "Name")) or skin.IsRegion(part(frame, "Sender"))
        or skin.IsRegion(part(frame, "Subject")) or skin.IsRegion(frame.SlotTexture)
    if isRow then
        interiors.Row(frame)
        for _, key in ipairs(ART) do
            local art = part(frame, key)
            if skin.IsRegion(art) and type(art.SetTexture) == "function" then art:SetAlpha(0) end
        end
    end
    mailDetails(frame)
    for _, key in ipairs(LABELS) do skin.Typeface(part(frame, key)) end
    if type(frame.GetRegions) == "function" then
        for _, region in ipairs({ frame:GetRegions() }) do
            if skin.IsRegion(region) and region:GetObjectType() == "FontString" then skin.Typeface(region) end
        end
    end
end
interiors.Commerce = commerce
interiors.Register("commerce", { "MerchantFrame", "BankFrame", "MailFrame", "OpenMailFrame",
    "SendMailFrame", "TradeFrame" }, commerce)
interiors.RegisterRefresh("commerce", { "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "MAIL_INBOX_UPDATE",
    "MAIL_SEND_INFO_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED" },
    { "MerchantFrame_Update", "InboxFrame_Update", "OpenMail_Update", "TradeFrame_Update" })

