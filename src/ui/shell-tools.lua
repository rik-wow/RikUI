-- Shared entry points; gameplay actions remain with their content.
local core, shell = RikUI, RikUI.Shell
local function outOfCombat() return not InCombatLockdown() end
local function optionsPage(id) core.Options.Open(id) end
local function add(id, group, label, order, action, enabled)
    shell.Register(id, { group = group, label = label, order = order, action = action, enabled = enabled })
end

local function registerPartyPreview()
    local party = core.UnitFrames and core.UnitFrames.Party
    if not party then return end
    shell.Register("party-preview", { group = "Interface", order = 35,
        label = function() return party.Testing and "Hide party preview" or "Preview party frames" end,
        visible = function() return core.UnitFrames.enabled ~= false and party.Holder ~= nil end,
        enabled = outOfCombat, action = function()
            local ok, reason = party.SetTest(not party.Testing)
            if not ok then core:Print(reason) end
        end })
end

local function registerTools()
    add("settings", "Interface", "Settings", 10, function() optionsPage("general") end)
    add("profiles", "Interface", "Profiles", 20, function() optionsPage("profiles") end)
    add("move", "Interface", function() return core.Layout.IsMoving() and "Finish moving frames" or "Move frames" end,
        30, function()
            if core.Layout.IsMoving() then core.Layout.LockAll() else core.Layout.UnlockAll() end
        end, outOfCombat)
    if core.Wizard then add("setup", "Interface", "Setup wizard", 40, core.Wizard.Open, outOfCombat) end
    registerPartyPreview()
    local planner = core.QuestPlanner
    if planner and planner.View then
        shell.Register("quests", { group = "Tools", label = "Quest planner", order = 20,
            action = planner.View.Open, visible = function() return planner.enabled ~= false end, enabled = outOfCombat })
    end
    add("maintenance", "Support", "Setup and maintenance", 20, function() optionsPage("setup") end)
    add("reload", "Support", "Reload interface", 30, function() if type(ReloadUI) == "function" then ReloadUI() end end, outOfCombat)
end

local function reporterReady()
    local reporter = PTR_IssueReporter
    return reporter and reporter.Data and reporter.Data.IsLoaded == true
        and reporter.ReportBug and type(reporter.TriggerEvent) == "function"
        and reporter.ReportEventTypes and reporter.ReportEventTypes.UIButtonClicked
end

local function openReporter()
    if not reporterReady() then return end
    local reporter = PTR_IssueReporter
    local ok, reason = pcall(reporter.TriggerEvent, reporter.ReportEventTypes.UIButtonClicked,
        reporter.Data.CurrentBugButtonContext, reporter.Data.ButtonDataPackage)
    if not ok then core:Print("Issue reporter unavailable: " .. tostring(reason)) end
end

function shell.AdoptReporter()
    if not reporterReady() or InCombatLockdown() or shell.Reporter == PTR_IssueReporter then return end
    shell.Initialize()
    if not shell.Entries.report then
        add("report", "Support", "Report an issue", 10, openReporter, function() return outOfCombat() and reporterReady() end)
    end
    -- Keep native OnUpdate and survey machinery running; only replace the launcher.
    for _, frame in ipairs({ PTR_IssueReporter, PTR_IssueReporter.ReportBug, PTR_IssueReporter.InfoButton }) do
        frame:EnableMouse(false)
        frame:SetAlpha(0)
    end
    shell.Reporter = PTR_IssueReporter
end

local function discover()
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, function() shell.Anchor(); shell.AdoptReporter() end)
    else shell.AdoptReporter() end
end

core:RegisterEvent("PLAYER_LOGIN", function() registerTools(); discover() end)
core:RegisterEvent("PLAYER_ENTERING_WORLD", discover)
core:RegisterEvent("PLAYER_REGEN_ENABLED", discover)
core:RegisterEvent("ADDON_LOADED", function(_, name) if name == "Blizzard_PTRFeedback" then discover() end end)
