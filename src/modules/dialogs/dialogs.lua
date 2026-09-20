-- Flat skin for the small dialogs that are neither static popups nor windows: ready check, role
-- poll, stack split, queue-ready dialogs, ticket status, autocomplete list, legacy dropdown lists,
-- colour picker, add-friend and report. One generic pass driven by keys, so a dialog that lacks a
-- piece keeps that piece stock. Nothing is moved, resized, reparented, shown, hidden or given a new
-- script: only region alpha, fonts and new child regions are written, so a first show in combat is
-- safe. Disable the module and reload for the stock look.
local core, skin, motion = RikUI, RikUI.Skin, RikUI.Motion
local dialogs = { Hooked = {}, Skinned = {} }
core.Dialogs = dialogs

-- backdrop names a child frame that only exists as a global: <dialog name> .. backdrop.
local TARGETS = {
    { name = "ReadyCheckListenerFrame" }, { name = "RolePollPopup" }, { name = "StackSplitFrame" },
    { name = "LFGDungeonReadyDialog" }, { name = "LFGDungeonReadyStatus" }, { name = "LFGInvitePopup" },
    { name = "PVPReadyDialog" }, { name = "TicketStatusFrame" }, { name = "AutoCompleteBox" },
    { name = "DropDownList1", backdrop = "MenuBackdrop" }, { name = "DropDownList2", backdrop = "MenuBackdrop" },
    { name = "DropDownList3", backdrop = "MenuBackdrop" }, { name = "ColorPickerFrame" },
    { name = "AddFriendFrame" }, { name = "ReportFrame" },
    -- The last audit. The two dialogs of Blizzard_CommunitiesSecure and SecureTransferDialog are left
    -- out: addon code may not be allowed to index them.
    { name = "GuildInviteFrame" }, { name = "FriendsFriendsFrame" }, { name = "BattleNetInviteFrame" },
    { name = "CreateChannelPopup" }, { name = "LFDRoleCheckPopup" }, { name = "LFGReadyCheckPopup" },
    { name = "LFGListApplicationDialog" }, { name = "LFGListInviteDialog" }, { name = "PVPRoleCheckPopup" },
    { name = "QuickJoinRoleSelectionFrame" }, { name = "ReportCheatingDialog" },
    { name = "CommunitiesAvatarPickerDialog" }, { name = "CommunitiesSettingsDialog" },
    { name = "CommunitiesTicketManagerDialog" }, { name = "CommunitiesGuildTextEditFrame" },
    { name = "CommunitiesGuildLogFrame" }, { name = "CommunitiesGuildNewsFiltersFrame" },
    { name = "ClassTalentLoadoutCreateDialog" }, { name = "ClassTalentLoadoutEditDialog" },
    { name = "ClassTalentLoadoutImportDialog" }, { name = "BankCleanUpConfirmationPopup" },
    { name = "GuildRenameFrame" }, { name = "EditModeImportLayoutLinkDialog" },
    { name = "EditModeSystemSettingsDialog" }, { name = "OpacityFrame" }, { name = "RatingMenuFrame" },
    { name = "CurrencyTransferMenu" },
}
-- Shared dialog art, then TranslucentFrameTemplate's pieces, then the backdrop mixin's nine pieces.
local DIALOG_ART = { "Border", "NineSlice", "Bg", "BG", "PortraitContainer", "SingleItemSplitBackground",
    "MultiItemSplitBackground", "background", "filigree", "bottomArt",
    "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopBorder", "BottomBorder", "LeftBorder", "RightBorder",
    "Center", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }
local HEADER_ART = { "LeftBG", "RightBG", "CenterBG" }
local CLOSE_KEYS, CLOSE_SUFFIX = { "CloseButton", "CloseXButton" }, "CloseButton"
local failed, warnings = {}, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Dialogs " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    return skin.IsRegion(value) and type(value.HookScript) == "function"
end

local function gold(region)
    if not skin.IsRegion(region) or type(region.SetFont) ~= "function" then return end
    skin.Font(region, "label")
    region:SetTextColor(unpack(skin.GOLD))
end

local function titles(frame)
    local container, header = frame.TitleContainer, frame.Header
    gold(skin.IsRegion(container) and container.TitleText or frame.TitleText)
    if not skin.IsRegion(header) then return end
    skin.Strip(header, HEADER_ART)
    gold(header.Text)
end

-- The dialog's own strings take the typeface at Blizzard's size and keep Blizzard's colour.
local function typefaces(frame)
    if type(frame.GetRegions) ~= "function" then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if skin.IsRegion(region) and region:GetObjectType() == "FontString" then skin.Typeface(region) end
    end
end

local function closeButton(frame, name)
    local close = core.Panels and core.Panels.Skin.Close
    if not close then return end
    for _, key in ipairs(CLOSE_KEYS) do
        if skin.IsRegion(frame[key]) then return close(frame[key]) end
    end
    close(_G[name .. CLOSE_SUFFIX])
end

-- The art goes first: if the client refuses that write nothing else has been added. The strings are
-- listed before the fill exists, because GetRegions returns addon-made regions too.
local function apply(frame, target)
    skin.Strip(frame, DIALOG_ART)
    local backdrop = target.backdrop and _G[target.name .. target.backdrop] or nil
    if skin.IsRegion(backdrop) then backdrop:SetAlpha(0) end
    typefaces(frame)
    titles(frame)
    frame.rikFill = skin.Fill(frame)
    frame.rikBorder = skin.Outline(frame)
    closeButton(frame, target.name)
    frame.rikFade = motion.Tween(frame, 0, 1, skin.FADE_SECONDS)
end

-- A failed dialog is not retried: half a skin applied twice is worse than half a skin. The controls
-- walk runs on every show because dialogs such as the report frame build their content late.
local function show(frame, target)
    local name = target.name
    if not dialogs.Skinned[name] and not failed[name] then
        local ok, reason = pcall(apply, frame, target)
        if ok then dialogs.Skinned[name] = true else failed[name] = true; warn("skin " .. name, reason) end
    end
    if not dialogs.Skinned[name] then return end
    if core.Controls then core.Controls.Walk(frame) end
    motion.Play(frame.rikFade)
end

local function hook(target)
    local frame = _G[target.name]
    if dialogs.Hooked[target.name] or not isFrame(frame) then return end
    dialogs.Hooked[target.name] = true
    frame:HookScript("OnShow", function(self) show(self, target) end)
    if frame:IsShown() then show(frame, target) end
end

-- Runs at login and again for every addon that loads, which is how load-on-demand dialogs arrive.
function dialogs.Discover()
    for _, target in ipairs(TARGETS) do hook(target) end
end

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

function dialogs:OnEnable()
    dialogs.Discover()
    core:RegisterEvent("ADDON_LOADED", dialogs.Discover)
end

function dialogs:Debug()
    core:Print("Dialogs hooked=" .. count(dialogs.Hooked) .. " skinned=" .. count(dialogs.Skinned)
        .. " failed=" .. count(failed))
end

core:RegisterModule("dialogs", dialogs)
