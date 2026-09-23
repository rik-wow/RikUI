-- Character-scoped planner preferences in the shared RikUI configuration.
local core, planner = RikUI, RikUI.QuestPlanner
local controls, inputs, refreshing = {}, {}, false
planner.PlanControls = controls
local function policy() return planner.Controller.Policy() end
local function command(value) planner.Command(value) end
local function report(ok, reason)
    if not ok then core:Print(reason or "Quest preference unavailable.") end
    return ok
end
local function choices(values)
    local result = {}
    for _, value in ipairs(values) do result[#result + 1] = { value = value, text = tostring(value) } end
    return result
end
local function setting(kind, key, label, extra)
    local spec = { type = kind, key = key, label = label,
        get = function() return policy()[key] end,
        set = function(value) return planner.Controller.Preference(key, value) end }
    for name, value in pairs(extra or {}) do spec[name] = value end
    return spec
end
local function dropdown(key, label, values) return setting("dropdown", key, label, { values = values }) end
local function checkbox(key, label) return setting("checkbox", key, label) end
local function slider(key, label, minimum, maximum, step)
    return setting("slider", key, label, { min = minimum, max = maximum, step = step })
end
local function heading(label) return { type = "heading", label = label } end
local function action(key, label, text, callback)
    return { type = "button", key = key, label = label, text = text, action = callback }
end
local function commandAction(key, label, text, value)
    return action(key, label, text, function() command(value) end)
end
local function inputValue(key)
    if inputs[key] ~= nil then return inputs[key] end
    return key == "rewardTargetInput" and tostring(policy().rewardTarget or "") or ""
end
local function input(key, label)
    return { type = "text", key = key, label = label, get = function() return inputValue(key) end,
        set = function(value) inputs[key] = value or ""; return true end }
end
local function toggleGoal(field, inputKey, label)
    local id = tonumber(inputValue(inputKey))
    if not planner.Schema.ID(id) then core:Print("Enter a positive " .. label .. " ID."); return end
    local active = policy()[field][id] == true
    if report(planner.Controller.Toggle(field, id)) then
        core:Print((active and "Removed " or "Added ") .. label .. " goal " .. id .. ".")
    end
end
local function applyRewardTarget()
    local value = inputValue("rewardTargetInput"):match("^%s*(.-)%s*$")
    local id = value ~= "" and tonumber(value) or nil
    if value ~= "" and not planner.Schema.ID(id) then
        core:Print("Enter a positive reward target ID, or leave it empty to clear.")
        return
    end
    if report(planner.Controller.Preference("rewardTarget", id)) then inputs.rewardTargetInput = nil end
end
local function observation()
    local observer = planner.PlanObserver
    return observer and observer.Status and observer.Status() or {}
end
local function timing(kind, label)
    return { type = "checkbox", key = "timing." .. kind, label = label,
        get = function() return observation().phase == kind end,
        disabled = function() return observation().active ~= true end,
        set = function(value)
            if (observation().phase == kind) == value then return true end
            return planner.Controller.Feedback(kind)
        end }
end
planner.Options = { title = "Quest planner", group = "Gameplay", settings = {
    heading("Journey"),
    dropdown("flavor", "Questing style", choices(planner.Preferences.Flavors())),
    dropdown("difficulty", "Difficulty", { { value = "easy", text = "Easy" },
        { value = "standard", text = "Standard" }, { value = "hard", text = "Hard" } }),
    dropdown("group", "Group content", { { value = "solo", text = "Solo" }, { value = "available", text = "Group available" } }),
    dropdown("travel", "Travel distance", { { value = "localOnly", text = "Nearby only" },
        { value = "regional", text = "Within the region" }, { value = "world", text = "Anywhere" } }),
    dropdown("grind", "Repetition tolerance", { { value = "low", text = "Low" },
        { value = "medium", text = "Medium" }, { value = "high", text = "High" } }),
    slider("explorationMinutes", "Exploration allowance (minutes)", 0, 60, 5),
    slider("readingSeconds", "Reading time per quest (seconds)", 0, 180, 5),
    checkbox("services", "Include optional services"), checkbox("dungeons", "Include dungeons"),
    checkbox("spoilers", "Show future story details"),
    heading("Session"),
    slider("sessionMinutes", "Session length (minutes)", 5, 480, 5),
    checkbox("strictSession", "Enforce the session time budget"),
    commandAction("newSession", "Restore quests deferred this session", "New session", "new-session"),
    commandAction("declineExploration", "Stop optional exploration", "Decline exploration", "decline-exploration"),
    heading("Rewards"),
    dropdown("rewardFocus", "Reward focus", { { value = "xp", text = "Experience" },
        { value = "equipment", text = "Equipment" }, { value = "reputation", text = "Reputation" },
        { value = "currency", text = "Money" }, { value = "unlocks", text = "Spell unlocks" } }),
    heading("Advanced goals"),
    input("rewardTargetInput", "Target item, faction or spell ID (empty = any)"),
    action("applyRewardTarget", "Apply the reward target", "Apply", applyRewardTarget),
    input("questGoalInput", "Quest goal ID"),
    action("toggleQuestGoal", "Add or remove this quest goal", "Toggle goal", function() toggleGoal("questGoals", "questGoalInput", "quest") end),
    input("zoneGoalInput", "Zone goal map ID"),
    action("toggleZoneGoal", "Add or remove this zone goal", "Toggle goal", function() toggleGoal("zoneGoals", "zoneGoalInput", "map") end),
    heading("Recovery and timing"),
    commandAction("unavailable", "Current action cannot be completed", "Mark unavailable", "unavailable"),
    commandAction("retryAction", "Reconsider the current action", "Retry action", "retry-action"),
    timing("waiting", "Currently waiting for the action"), timing("recovery", "Currently recovering between actions"),
    commandAction("resetLearning", "Clear learned duration estimates", "Reset learned times", "reset-learning"),
    commandAction("resetConstraints", "Clear quest, goal and area constraints", "Reset constraints", "reset"),
} }

function controls.Refresh()
    if refreshing then return end
    local options = core.Options
    local panel = options and options.Panel and options.Panel()
    local page = panel and panel.pages and panel.pages[panel.current]
    if not panel or not panel:IsShown() or not page or page.id ~= "questplanner" then return end
    controls.Window, refreshing = panel, true
    local ok, reason = pcall(options.Refresh)
    refreshing = false
    if not ok then error(reason, 0) end
end
function controls.Open()
    if not planner.enabled then return end
    core.Combat.Queue(function()
        local options = core.Options
        if not options or not options.Open then core:Print("Quest settings are unavailable."); return end
        if planner.View and planner.View.Window then planner.View.Window:Hide() end
        options.Open("questplanner")
        controls.Window = options.Panel and options.Panel()
    end, "questplanner:preferences")
end
