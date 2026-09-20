-- Flat skin for the social toasts: Battle.net friend toasts, the play-time alert, the shard transfer
-- notice and the voice chat prompts. They are ContainedAlertFrames shown through ChatAlertFrame, so
-- they never pass AlertFrame_ShowNewAlert and src/modules/alerts/alerts.lua does not see them. SocialToastTemplate
-- fades a toast in and out with its own animation groups; this file adds no tween, because a second
-- alpha animation would fight Blizzard's. Art is removed on every show, the rest is written once.
local core, skin = RikUI, RikUI.Skin
local toasts = { Hooked = {}, Skinned = {} }
core.Toasts = toasts

local TARGETS = { "BNToastFrame", "TimeAlertFrame", "ShardTransferImminentFrame", "VoiceChatPromptActivateChannel",
    "VoiceChatChannelActivatedNotification" }
-- The pieces BackdropTemplate builds from backdropInfo. It recolours them through vertex colour,
-- never through SetAlpha, so a fade lasts.
local BACKDROP = { "Center", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner",
    "BottomLeftCorner", "BottomRightCorner" }
local ICON_KEYS, GLOW_SUFFIX, ICON_EDGE_INSET = { "IconTexture", "Icon" }, "GlowFrame", -1
local failed, warnings = {}, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Toasts " .. operation .. ": " .. tostring(reason))
end

-- Blizzard animates the glow's alpha, so it is emptied instead of faded.
local function removeArt(frame, name)
    skin.Strip(frame, BACKDROP)
    local glow = _G[name .. GLOW_SUFFIX]
    if skin.IsRegion(glow) then skin.Blank(glow, { "glow" }) end
end

local function typefaces(frame)
    if type(frame.GetRegions) ~= "function" then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if skin.IsRegion(region) and region:GetObjectType() == "FontString" then skin.Typeface(region) end
    end
end

local function icon(frame)
    for _, key in ipairs(ICON_KEYS) do
        if skin.IsRegion(frame[key]) and type(frame[key].SetTexCoord) == "function" then return frame[key] end
    end
    return nil
end

-- The strings are listed before the fill exists, because GetRegions returns addon-made regions too.
local function decorate(frame)
    typefaces(frame)
    frame.rikFill = skin.Fill(frame)
    frame.rikBorder = skin.Outline(frame)
    local art = icon(frame)
    if not art then return end
    skin.CropIcon(art)
    -- One pixel outside the icon: the lines are in a lower layer than the icon and would be covered.
    frame.rikIconBorder = skin.Outline(frame, nil, ICON_EDGE_INSET, art)
end

local function apply(frame, name)
    removeArt(frame, name)
    if toasts.Skinned[name] then return end
    decorate(frame)
    toasts.Skinned[name] = true
end

-- A failed toast is not retried: half a skin applied twice is worse than half a skin.
local function show(frame, name)
    if failed[name] then return end
    local ok, reason = pcall(apply, frame, name)
    if not ok then
        failed[name] = true
        return warn("skin " .. name, reason)
    end
    if core.Controls then core.Controls.Walk(frame) end
end

local function hook(name)
    local frame = _G[name]
    if toasts.Hooked[name] or not skin.IsRegion(frame) or type(frame.HookScript) ~= "function" then return end
    toasts.Hooked[name] = true
    frame:HookScript("OnShow", function(self) show(self, name) end)
    if frame:IsShown() then show(frame, name) end
end

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

function toasts:OnEnable()
    for _, name in ipairs(TARGETS) do hook(name) end
end

function toasts:Debug()
    core:Print("Toasts hooked=" .. count(toasts.Hooked) .. " skinned=" .. count(toasts.Skinned)
        .. " failed=" .. count(failed))
end

core:RegisterModule("toasts", toasts)
