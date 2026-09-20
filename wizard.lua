-- The first-login wizard's shell: one flat window, pages that register themselves (wizard-pages.lua),
-- one state table the pages write and Apply reads, and a footer with Skip, Back and Next. Nothing is
-- applied until the last page. It opens once for a character that was never set up and again on
-- /rik setup. Nothing here is a secure frame; it still stays away in combat, because Apply cannot run.
local core, skin, motion = RikUI, RikUI.Skin, RikUI.Motion
local controls = core.WizardControls
local wizard = { Pages = {}, Index = 1, title = "Wizard" }
core.Wizard = wizard

local WINDOW_NAME, WIDTH, HEIGHT, PAD = "RikUIWizard", 820, 540, 20
local HEADER_HEIGHT, FOOTER_HEIGHT, RULE_HEIGHT, DOT, DOT_GAP = 44, 44, 2, 8, 6
local PAGE_FADE, DOT_PULSE = 0.18, 0.4
local STEPS = { "macros", "bars", "binds", "cvars", "layout" }
local TEXT = { next = "Next", apply = "Apply", close = "Close", reload = "Reload UI", back = "Back", skip = "Skip setup" }
local SKIPPED = "Setup skipped. /rik setup opens it again; /rik apply sets up without it."
local PAUSED = "Setup paused for combat; it returns when combat ends."
local DONE = "Done. Type /rik undo to revert everything the setup changed."
local window, open, paused, applying, finished, reloadNeeded = nil, false, false, false, false, false

function wizard.IsOpen() return open end

-- page = { key, title, build(frame, state), refresh(frame, state) }; pages show in the order they register.
function wizard.AddPage(page)
    assert(type(page) == "table" and type(page.key) == "string" and type(page.title) == "string"
        and type(page.build) == "function", "Wizard.AddPage needs a key, a title and a build function")
    wizard.Pages[#wizard.Pages + 1] = page
end

local function moduleChoices()
    local choices = {}
    for name in pairs(core.Modules) do
        if name ~= "wizard" then choices[name] = core.Profile.modules[name] ~= false end
    end
    return choices
end

-- Everything on, as the design says; the layout starts on whatever the screen looks like now.
function wizard.NewState()
    local _, class = UnitClass("player")
    local state = { class = class, role = nil, strafe = false, mouse45 = true, keepPositions = false,
        layoutPreset = core.Layout.MatchingPreset and core.Layout.MatchingPreset() or nil,
        modules = moduleChoices(), cvars = {}, steps = {} }
    state.layoutPreset = state.layoutPreset or core.Layouts.Order[1]
    for _, entry in ipairs(core.CVars.List) do state.cvars[entry.name] = true end
    for _, step in ipairs(STEPS) do state.steps[step] = true end
    return state
end

-- The options setup.Apply takes. A setting switched off is left out of the selection.
function wizard.Options()
    local state = wizard.State
    local opts = { strafe = state.strafe, mouse45 = state.mouse45, allowEmpty = true, cvarSelection = {} }
    for _, step in ipairs(STEPS) do opts[step] = state.steps[step] == true end
    for name, chosen in pairs(state.cvars) do
        if chosen then opts.cvarSelection[name] = true end
    end
    if state.keepPositions then opts.layout = false else opts.layoutPreset = state.layoutPreset end
    return opts
end

local function paintDots()
    for index, dot in ipairs(window.dots) do
        local color = index == wizard.Index and controls.ACCENT or skin.LINE
        dot:SetVertexColor(color[1], color[2], color[3], 1)
    end
    motion.Play(window.dots[wizard.Index].pulse)
end

local function paintFooter()
    local last = wizard.Index == #wizard.Pages
    local label = finished and (reloadNeeded and TEXT.reload or TEXT.close) or (last and TEXT.apply or TEXT.next)
    window.next.label:SetText(label)
    window.next:SetDisabled(applying)
    window.back:SetDisabled(applying or finished or wizard.Index == 1)
    window.skip:SetShown(not finished)
end

local function pageFrame(page)
    if page.frame then return page.frame end
    local frame = CreateFrame("Frame", nil, window.content)
    frame:SetAllPoints()
    frame.fade = motion.Tween(frame, 0, 1, PAGE_FADE)
    page.frame = frame
    page.build(frame, wizard.State)
    return frame
end

function wizard.Go(index)
    if not window or applying or index < 1 or index > #wizard.Pages then return false end
    for _, page in ipairs(wizard.Pages) do
        if page.frame then page.frame:Hide() end
    end
    wizard.Index = index
    local page = wizard.Pages[index]
    local frame = pageFrame(page)
    if page.refresh then page.refresh(frame, wizard.State) end
    frame:Show()
    motion.Play(frame.fade)
    window.title:SetText(page.title)
    window.step:SetText("Step " .. index .. " of " .. #wizard.Pages)
    paintDots()
    paintFooter()
    return true
end

function wizard.Back() return wizard.Go(wizard.Index - 1) end

function wizard.Close()
    open, paused = false, false
    if window then window:Hide() end
end

function wizard.Skip()
    core.CharDB.wizardDone = true
    core:Changed()
    wizard.Close()
    core:Print(SKIPPED)
end

-- Module switches are profile flags that take effect on reload; returns how many changed.
local function writeModules(state)
    local changed = 0
    for name, chosen in pairs(state.modules) do
        if (core.Profile.modules[name] ~= false) ~= chosen then changed = changed + 1 end
        core.Profile.modules[name] = chosen
    end
    return changed
end

local function stepLine(result)
    local parts = {}
    for _, step in ipairs(STEPS) do
        local stats = result.steps and result.steps[step]
        if stats then parts[#parts + 1] = step .. " " .. (stats.placed + stats.edited) end
    end
    return table.concat(parts, ", ")
end

local function onComplete(result)
    applying = false
    if result.status == "applied" then
        finished = true
        core.CharDB.wizardDone = true
        window.status:SetText(DONE .. "\n" .. stepLine(result) .. (reloadNeeded and "\nSwitched modules need a reload." or ""))
    else
        window.status:SetText("Setup stopped: " .. tostring(result.error) .. "\nNothing after that step was changed. Go back or try again.")
    end
    paintFooter()
end

function wizard.Apply()
    if applying or finished then return end
    applying = true
    reloadNeeded = writeModules(wizard.State) > 0
    paintFooter()
    window.status:SetText("Applying...")
    local opts = wizard.Options()
    opts.onComplete = onComplete
    local result, reason = core.Setup.Apply(wizard.State.class, wizard.State.role, opts)
    if not result then onComplete({ status = "failed", error = reason }) end
end

function wizard.Next()
    if finished then
        wizard.Close()
        if reloadNeeded then ReloadUI() end
        return
    end
    if wizard.Index == #wizard.Pages then return wizard.Apply() end
    wizard.Go(wizard.Index + 1)
end

local function header()
    window.title = controls.Text(window, "heading", "", skin.GOLD)
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -14)
    window.step = controls.Text(window, "small", "", controls.MUTED)
    window.step:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -12)
    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(skin.FLAT)
    rule:SetVertexColor(controls.ACCENT[1], controls.ACCENT[2], controls.ACCENT[3], 1)
    rule:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -HEADER_HEIGHT + RULE_HEIGHT)
    rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -HEADER_HEIGHT + RULE_HEIGHT)
    rule:SetHeight(RULE_HEIGHT)
    window.rule = rule
end

local function dots()
    window.dots = {}
    for index = 1, #wizard.Pages do
        local dot = window:CreateTexture(nil, "ARTWORK")
        dot:SetTexture(skin.FLAT)
        dot:SetSize(DOT, DOT)
        dot:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD - (#wizard.Pages - index) * (DOT + DOT_GAP), -28)
        dot.pulse = motion.Tween(dot, 0.3, 1, DOT_PULSE)
        window.dots[index] = dot
    end
end

local function footer()
    window.skip = controls.Button(window, TEXT.skip, wizard.Skip)
    window.skip:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD, 12)
    window.next = controls.Button(window, TEXT.next, wizard.Next)
    window.next:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, 12)
    window.back = controls.Button(window, TEXT.back, wizard.Back)
    window.back:SetPoint("RIGHT", window.next, "LEFT", -8, 0)
    window.status = controls.Text(window, "small", "", controls.MUTED)
    window.status:SetPoint("LEFT", window.skip, "RIGHT", 16, 0)
    window.status:SetPoint("RIGHT", window.back, "LEFT", -16, 0)
    window.status:SetJustifyH("LEFT")
end

local function build()
    window = CreateFrame("Frame", WINDOW_NAME, UIParent)
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    skin.Fill(window, skin.BACKING)
    skin.Outline(window)
    window.fade = motion.Tween(window, 0, 1, PAGE_FADE)
    window.content = CreateFrame("Frame", nil, window)
    window.content:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -HEADER_HEIGHT - 12)
    window.content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, FOOTER_HEIGHT + 8)
    header()
    dots()
    footer()
    window:SetScript("OnHide", function() if not paused then open = false end end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = WINDOW_NAME end
    wizard.Window = window
end

local function show()
    if not core.Profile or #wizard.Pages == 0 then return end
    if not window then build() end
    wizard.State = wizard.NewState()
    open, paused, applying, finished, reloadNeeded = true, false, false, false, false
    window.status:SetText("")
    window:Show()
    motion.Play(window.fade)
    wizard.Go(1)
end

-- Opening waits out combat: the last page's Apply could not run there anyway.
function wizard.Open()
    if open then return true end
    core.Combat.Queue(show)
    return true
end

local function firstLogin()
    local character = core.CharDB
    if open or not character or character.applied ~= nil or character.wizardDone then return end
    wizard.Open()
end

function wizard:OnEnable()
    core:RegisterEvent("PLAYER_ENTERING_WORLD", firstLogin)
    core:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        if not open or not window or not window:IsShown() then return end
        paused = true
        window:Hide()
        core:Print(PAUSED)
    end)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if not paused then return end
        paused = false
        window:Show()
    end)
end

function wizard:Debug()
    core:Print("Wizard open=" .. tostring(open) .. " page=" .. wizard.Index .. "/" .. #wizard.Pages
        .. " done=" .. tostring(core.CharDB.wizardDone == true))
end

core:RegisterCommand("setup", function()
    if InCombatLockdown() then core:Print("The setup wizard opens when combat ends.") end
    if open then wizard.Close() end
    wizard.Open()
end, "Open the setup wizard")

core:RegisterModule("wizard", wizard)
