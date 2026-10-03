-- The first-login wizard's shell: one flat window, pages that register themselves (src/configuration/wizard/wizard-pages.lua),
-- one state table the pages write and Apply reads, and a footer with Skip, Back and Next. Nothing is
-- applied until the last page. It opens once for a character that was never set up and again on
-- /rik setup. Nothing here is a secure frame; it still stays away in combat, because Apply cannot run.
local core, skin, motion = RikUI, RikUI.Skin, RikUI.Motion
local controls = core.WizardControls
local wizard = { Pages = {}, Index = 1, title = "Wizard" }
core.Wizard = wizard

local WINDOW_NAME, WIDTH, HEIGHT, PAD = "RikUIWizard", 820, 584, 20
local HEADER_HEIGHT, FOOTER_HEIGHT, RULE_HEIGHT = 88, 44, 2
local PAGE_FADE, STEP_GAP, STEP_HEIGHT = 0.18, 6, 30
local STEP_LABELS = { welcome = "Character", role = "Role", keys = "Keybinds", layout = "Layout", modules = "Modules", summary = "Review" }
local STEPS = { "macros", "bars", "binds", "cvars", "layout" }
local TEXT = { next = "Next", apply = "Apply", close = "Close", reload = "Reload UI", back = "Back", skip = "Skip setup" }
local SKIPPED = "Setup skipped. /rik setup opens it again; /rik apply sets up without it."
local PAUSED = "Setup paused for combat; it returns when combat ends."
local DONE = "Setup complete. /rik undo restores the last setup operation."
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
    for name in pairs(core.Modules) do        if name ~= "wizard" then choices[name] = core.Profile.modules[name] ~= false end
    end
    return choices
end

-- A new character may belong to an experienced player. Replacements are opt-in.
function wizard.NewState()
    local _, class = UnitClass("player")
    local marker = core.CharDB and core.CharDB.applied
    local state = { class = class, role = nil, presetName = type(marker) == "table" and marker.class == class and marker.presetName or "",
        path = "keep", advanced = false, strafe = false, mouse45 = true, keepPositions = true,
        layoutPreset = core.Layout.MatchingPreset and core.Layout.MatchingPreset() or nil,
        modules = moduleChoices(), cvars = {}, steps = {} }
    state.layoutPreset = state.layoutPreset or core.Layouts.Order[1]
    for _, entry in ipairs(core.CVars.List) do state.cvars[entry.name] = true end
    for _, step in ipairs(STEPS) do state.steps[step] = false end
    return state
end

-- The options setup.Apply takes. A setting switched off is left out of the selection.
function wizard.SelectPreset(name)
    if applying or InCombatLockdown() then return nil, "Setup is busy." end
    local state = wizard.State
    if not state then return nil, "Open setup first." end
    local preset, reason = core.Setup.Source(state.class, name)
    if not preset then return nil, reason end
    if name ~= "" then
        local issues = core.Setup.ValidateSharedPreset(preset)
        if #issues > 0 then return nil, issues[1] end
    end
    state.presetName, state.role = name, nil
    wizard.Go(wizard.Index)    return true
end

function wizard.Options()
    local state = wizard.State
    local opts = { strafe = state.strafe, mouse45 = state.mouse45, allowEmpty = true, cvarSelection = {}, presetName = state.presetName ~= "" and state.presetName or nil }
    for _, step in ipairs(STEPS) do opts[step] = state.steps[step] == true end
    for name, chosen in pairs(state.cvars) do
        if chosen then opts.cvarSelection[name] = true end
    end
    if state.keepPositions then opts.layout = false else opts.layoutPreset = state.layoutPreset end
    return opts
end

function wizard.VisiblePages()
    local result, state = {}, wizard.State
    for index, page in ipairs(wizard.Pages) do
        local visible = not state or ((page.key ~= "role" and page.key ~= "keys") or state.path == "actions")
        if page.key == "modules" then visible = state and state.advanced == true end
        if visible then result[#result + 1] = index end
    end
    return result
end

function wizard.ChoosePath(path)
    if applying or finished or (path ~= "keep" and path ~= "actions") then return false end
    local state = wizard.State
    if not state then return false end
    state.path = path
    state.steps.macros, state.steps.bars = path == "actions", path == "actions"
    if path == "keep" then state.steps.binds = false end
    wizard.Go(wizard.Index)
    return true
end

local function pageNumber()
    local route = wizard.VisiblePages()
    for number, index in ipairs(route) do if index == wizard.Index then return number, #route end end
    return wizard.Index, #wizard.Pages
end

local function paintSteps()
    local route = wizard.VisiblePages()
    local width = (WIDTH - PAD * 2 - (#route - 1) * STEP_GAP) / #route
    for index, dot in ipairs(window.stepBackings) do
        window.stepItems[index]:Hide()
        local active, reviewed = not finished and index == wizard.Index, finished or index < wizard.Index
        dot:SetVertexColor(active and 0.1 or 0.065, active and 0.23 or 0.08, active and 0.3 or 0.11, 1)
        window.stepRails[index]:SetShown(active)
        window.stepChecks[index]:SetShown(reviewed)
        local color = (active or reviewed) and skin.INK or controls.MUTED
        window.stepLabels[index]:SetTextColor(unpack(color))
    end
    for number, index in ipairs(route) do
        local item = window.stepItems[index]
        item:ClearAllPoints(); item:SetSize(width, STEP_HEIGHT)
        item:SetPoint("TOPLEFT", PAD + (number - 1) * (width + STEP_GAP), -42)
        window.stepLabels[index]:SetText(number .. "  " .. (STEP_LABELS[wizard.Pages[index].key] or wizard.Pages[index].title))
        item:Show()
    end
end

local function paintFooter()
    local last = wizard.Index == #wizard.Pages
    local label = finished and (reloadNeeded and TEXT.reload or TEXT.close) or (last and TEXT.apply or TEXT.next)
    window.next.label:SetText(label)
    window.next:SetDisabled(applying)
    window.back:SetDisabled(applying or finished or wizard.Index == 1)
    window.skip:SetShown(not finished)
    window.skip:SetDisabled(applying)end

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
    local number, total = pageNumber()
    window.step:SetText("Step " .. number .. " of " .. total)
    paintSteps()
    paintFooter()
    return true
end

local function movePage(direction)
    local route = wizard.VisiblePages()
    for number, index in ipairs(route) do
        if index == wizard.Index and route[number + direction] then return wizard.Go(route[number + direction]) end
    end
    return false
end

function wizard.Back() return movePage(-1) end
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

local function onComplete(result)    applying = false
    if result.status == "applied" then
        reloadNeeded = writeModules(wizard.State) > 0
        finished = true
        paintSteps()
        core.CharDB.wizardDone = true
        core:Changed()
        window.status:SetText(reloadNeeded and "Module changes need a reload." or (result.unchanged and "Current setup kept." or DONE))
        if wizard.ShowCompletion then wizard.ShowCompletion(window.content, result, reloadNeeded) end
    else
        window.status:SetText("Setup stopped: " .. tostring(result.error) .. "\nNothing after that step was changed. Go back or try again.")
    end
    paintFooter()
end

function wizard.Apply()
    if applying or finished then return end
    if InCombatLockdown() then window.status:SetText("Wait until combat ends."); return end
    local changes = false
    local opts = wizard.Options()
    for _, step in ipairs(STEPS) do if opts[step] then changes = true end end
    if not changes then onComplete({ status = "applied", unchanged = true }); return end
    applying = true
    paintFooter()
    window.status:SetText("Applying...")
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
    movePage(1)end

local function header()
    window.title = controls.Text(window, "heading", "", skin.GOLD)
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -14)
    window.step = controls.Text(window, "small", "", controls.MUTED)
    window.step:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -16)
    window.title:SetPoint("TOPRIGHT", window, "TOPRIGHT", -160, -14)
    window.title:SetJustifyH("LEFT"); window.title:SetWordWrap(false)
    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(skin.FLAT)
    rule:SetVertexColor(controls.ACCENT[1], controls.ACCENT[2], controls.ACCENT[3], 1)
    rule:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -HEADER_HEIGHT + RULE_HEIGHT)
    rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -HEADER_HEIGHT + RULE_HEIGHT)
    rule:SetHeight(RULE_HEIGHT)
    window.rule = rule
end

local function stepTrack()
    window.stepBackings, window.stepLabels, window.stepRails, window.stepChecks, window.stepItems = {}, {}, {}, {}, {}
    local width = (WIDTH - PAD * 2 - (#wizard.Pages - 1) * STEP_GAP) / #wizard.Pages
    for index, page in ipairs(wizard.Pages) do
        local item = CreateFrame("Frame", nil, window)
        item:SetSize(width, STEP_HEIGHT)
        item:SetPoint("TOPLEFT", PAD + (index - 1) * (width + STEP_GAP), -42)
        window.stepItems[index] = item
        window.stepBackings[index] = skin.Fill(item)
        local label = controls.Text(item, "small", index .. "  " .. (STEP_LABELS[page.key] or page.title))
        label:SetPoint("LEFT", 8, 0); label:SetPoint("RIGHT", -24, 0)
        label:SetJustifyH("LEFT"); label:SetWordWrap(false)
        local rail = item:CreateTexture(nil, "OVERLAY")
        rail:SetTexture(skin.FLAT); rail:SetVertexColor(unpack(controls.ACCENT))
        rail:SetPoint("BOTTOMLEFT"); rail:SetPoint("BOTTOMRIGHT"); rail:SetHeight(2)        local mark = item:CreateTexture(nil, "OVERLAY")
        mark:SetTexture(core.Media.checked); mark:SetSize(12, 12); mark:SetPoint("RIGHT", -6, 0)
        mark:SetVertexColor(unpack(controls.ACCENT))
        window.stepLabels[index], window.stepRails[index], window.stepChecks[index] = label, rail, mark
    end
end

local function footer()
    window.skip = controls.Button(window, TEXT.skip, wizard.Skip)
    window.skip:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD, 12)
    window.next = controls.Button(window, TEXT.next, wizard.Next)
    window.next.primary = skin.Fill(window.next, { 0.1, 0.27, 0.36, 1 }, 1)
    window.next.primary:SetDrawLayer("BACKGROUND", -7)
    for _, edge in ipairs(window.next.edge) do edge:SetVertexColor(unpack(controls.ACCENT)) end
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
    window:SetClampedToScreen(true)
    window.chrome = skin.WindowChrome(window, HEADER_HEIGHT, FOOTER_HEIGHT)
    window.fade = motion.Tween(window, 0, 1, PAGE_FADE)    window.content = CreateFrame("Frame", nil, window)
    window.content:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -HEADER_HEIGHT - 12)
    window.content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, FOOTER_HEIGHT + 8)
    header()
    stepTrack()
    footer()
    window:SetScript("OnHide", function() if not paused then open = false end end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = WINDOW_NAME end
    wizard.Window = window
end

local function show()
    if not core.Profile or #wizard.Pages == 0 then return end
    if not window then build() end
    local fresh = wizard.NewState()
    if wizard.State then
        for key in pairs(wizard.State) do wizard.State[key] = nil end
        for key, value in pairs(fresh) do wizard.State[key] = value end
    else wizard.State = fresh end
    open, paused, applying, finished, reloadNeeded = true, false, false, false, false
    if wizard.Completion then wizard.Completion:Hide() end
    window.status:SetText("")
    window:Show()
    motion.Play(window.fade)
    wizard.Go(1)
end

-- Opening waits out combat: the last page's Apply could not run there anyway.
function wizard.Open()
    if applying then return false end
    if wizard.EndPractice then wizard.EndPractice() end
    if open then return true end
    core.Combat.Queue(show)
    return true
end

local function firstLogin()
    local character = core.CharDB
    if open or not character or character.applied ~= nil or character.wizardDone then return end    wizard.Open()
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