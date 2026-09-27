-- Local browsing never changes the active route; only Do now requests that change.
local core, planner = RikUI, RikUI.QuestPlanner
local view, ui = planner.View, planner.View.WindowUI
local page, filterIndex, focused = 1, 1, nil
local objectiveFocus
local FILTERS = { "All quests", "Available", "Excluded" }

local function excluded(quest)
    return quest.skipped or quest.deferred or quest.groupBlocked or quest.avoided or quest.failed
end

local function key(quest)
    if not quest then return nil end
    if planner.Schema.ID(quest.questID) then return "quest:" .. quest.questID end
    return "action:" .. tostring(quest.actionID or (quest.planAction and quest.planAction.id) or quest.title)
end

local function quests()
    local result = {}
    for _, quest in ipairs(planner.Controller.Quests()) do
        if filterIndex == 1 or (filterIndex == 2 and not excluded(quest)) or (filterIndex == 3 and excluded(quest)) then
            result[#result + 1] = quest
        end
    end
    return result
end

local function enable(button, value)
    button:SetEnabled(value == true); button:SetAlpha(value and 1 or 0.4)
end

local function rowState(quest, model)
    if quest.skipped then return "Skipped" end
    if quest.deferred then return "Deferred for this session" end
    if quest.groupBlocked then return "Needs a group" end
    if quest.avoided then return "Area avoided" end
    if quest.failed then return "Failed quest" end
    if key(quest) == key(model.selected) then return "Active route" end
    return quest.kind == "turnin" and "Ready to turn in" or (quest.destination and "Available" or "Location unknown")
end

local function guideRows(quest)
    local snapshot=planner.GetSnapshot()
    return quest and snapshot and planner.ObjectiveGuide and planner.ObjectiveGuide.Rows(snapshot,quest.questID) or {}
end

local function guideText(entry)
    local lines={(entry.finished and "Complete: " or entry.index==0 and "Turn-in: " or "Objective "..entry.index..": ")..(entry.text or "Turn in")}
    if not entry.finished then
        lines[#lines+1]=entry.instruction
        if entry.limited then lines[#lines+1]="Showing a limited set of source locations." end
        local p=entry.destination
        if p then
            local ok,info=planner.Context.Call(C_Map and C_Map.GetMapInfo,p.mapID)
            local map=ok and type(info)=="table" and info.name or ("Map "..p.mapID)
            lines[#lines+1]=string.format("%s — %.1f, %.1f (%d known locations)",map,p.x*100,p.y*100,entry.locations)
            lines[#lines+1]="Source: "..(entry.source or "quest data").."; current spawn and floor unknown."
        end
    end
    return planner.Guidance.Text(table.concat(lines,"\n"),2048)
end

local function bodyText(quest)
    if not quest then return "Choose a quest from the list to see its objectives and actions." end
    local snapshot = planner.GetSnapshot()
    local observed = snapshot and snapshot.quests and snapshot.quests[quest.questID]
    local lines, detail = {}, planner.Schema.Text(quest.detail) and planner.Guidance.Text(quest.detail, 2048)
    if detail and detail ~= "" then lines[1] = detail end
    local entries=guideRows(quest)
    for _,entry in ipairs(entries) do lines[#lines+1]=guideText(entry) end
    for _, objective in ipairs(#entries==0 and observed and observed.objectives or {}) do
        local text = planner.Schema.Text(objective.text) and planner.Guidance.Text(objective.text, 2048) or "Objective details unavailable"
        if text ~= detail then lines[#lines + 1] = (objective.finished and "Complete: " or "- ") .. text end
    end
    if #lines == 0 then lines[1] = "Open the quest log for more information." end
    return table.concat(lines, "\n\n")
end

local function readingText(pane, label, value)
    local changed = label:GetText() ~= value
    label:SetText(value); label:SetHeight(0)
    local height = math.max(pane.height or 1, (label:GetStringHeight() or 0) + 8)
    label:SetHeight(height); core.Scroll.SetContentHeight(pane, height)
    if changed then core.Scroll.SetOffset(pane, 0) end
end

local function refreshObjectives(panel,quest)
    local entries=guideRows(quest)
    local chosen
    for _,entry in ipairs(entries) do
        if objectiveFocus and objectiveFocus.questID==entry.questID and objectiveFocus.index==entry.index and not entry.finished then chosen=entry end
    end
    if not chosen then for _,entry in ipairs(entries) do if not entry.finished then chosen=entry;break end end end
    panel.objectiveEntry=chosen
    panel.objective:SetShown(chosen~=nil);panel.location:SetShown(chosen~=nil)
    if chosen then
        objectiveFocus={questID=chosen.questID,index=chosen.index}
        panel.objective.label:SetText(chosen.index==0 and "Turn in" or ("Objective "..chosen.index.." / "..#entries))
        enable(panel.location,chosen.locations>1)
    end
    panel.scroll:ClearAllPoints();panel.scroll:SetPoint("TOPLEFT",16,chosen and -150 or -114)
    panel.scroll:SetSize(430,chosen and 110 or 146)
end

local function refreshSelection(list, model)
    local selected
    for _, quest in ipairs(list) do if key(quest) == focused then selected = quest; break end end
    if not selected then
        for _, quest in ipairs(list) do if key(quest) == key(model.selected) then selected = quest; break end end
        selected = selected or list[1]; focused = key(selected)
    end
    for index, quest in ipairs(list) do
        if key(quest) == focused then page = math.ceil(index / ui.PAGE_SIZE); break end
    end
    local panel, policy = view.Window.selection, planner.Controller.Policy()
    panel.quest = selected
    panel.title:SetText(selected and selected.title or "No quest selected")
    panel.state:SetText(selected and rowState(selected, model) or "Browse the quest list")
    refreshObjectives(panel,selected)
    readingText(panel.scroll, panel.body, bodyText(selected))
    local valid = selected and planner.Schema.ID(selected.questID) == true
    for _, name in ipairs({ "pin", "defer", "skip", "log" }) do enable(panel[name], valid) end
    enable(panel.area, selected ~= nil and selected.destination ~= nil)
    enable(panel.route, valid and (panel.objectiveEntry and panel.objectiveEntry.destination~=nil or not panel.objectiveEntry and selected.destination~=nil) and not excluded(selected))
    panel.route.label:SetText(panel.objectiveEntry and "Route to objective" or selected and key(selected) == key(model.selected) and "Current route" or "Do now")
    panel.pin.label:SetText(valid and policy.pins[selected.questID] and "Unpin" or "Pin")
    panel.defer.label:SetText(selected and selected.deferred and "Resume quest" or "Defer quest")
    panel.skip.label:SetText(selected and selected.skipped and "Include quest" or "Skip quest")
    panel.area.label:SetText(selected and selected.avoided and "Allow area" or "Avoid area")
end

local function refreshRows(list, model)
    local window = view.Window
    local pages = math.max(1, math.ceil(#list / ui.PAGE_SIZE))
    page = math.min(page, pages); window.page:SetText(page .. " / " .. pages)
    enable(window.previous, page > 1); enable(window.following, page < pages)
    window.filter.label:SetText(FILTERS[filterIndex]); window.empty:SetShown(#list == 0)
    window.empty:SetText(filterIndex == 2 and "No available quests. Choose All quests to restore excluded ones."
        or filterIndex == 3 and "No excluded quests." or "No quests observed yet. Open your quest log to update the list.")
    for index, row in ipairs(window.rows) do
        local quest = list[(page - 1) * ui.PAGE_SIZE + index]
        row.quest, row.questID = quest, quest and quest.questID
        row:SetShown(quest ~= nil)
        if quest then
            row.label:SetText(quest.title); row.meta:SetText(rowState(quest, model))
            row.selected:SetShown(key(quest) == focused)
        end
    end
end

local function refreshRouteDetails(model)
    local window, policy = view.Window, planner.Controller.Policy()
    local route = planner.Terrain and planner.Terrain.Guidance()
    readingText(window.details.scroll, window.instructions, planner.Guidance.Details(model, planner.GetSnapshot(), route))
    local ids = {}
    for id in pairs(policy.avoids) do ids[#ids + 1] = id end
    table.sort(ids)
    local id = ids[1]
    window.restoreArea.mapID = id; window.restoreArea:SetShown(id ~= nil)
    if id then
        local ok, info = planner.Context.Call(C_Map and C_Map.GetMapInfo, id)
        local name = ok and planner.Schema.PlainTable(info) and planner.Schema.Text(info.name) and planner.Guidance.Text(info.name)
        window.restoreArea.label:SetText("Allow " .. (name or ("map " .. id)))
    end
end

function view.RefreshWindow()
    local window = view.Window
    if not window or not window:IsShown() then return end
    local model = planner.Controller.Get()
    view.RefreshSummary(window.summary, model)
    window.summary.eyebrow:SetText(model.status == "paused" and "GUIDANCE PAUSED" or "CURRENT OBJECTIVE")
    window.automatic:SetShown(model.manual == true)
    local list = quests()
    refreshSelection(list, model); refreshRows(list, model); refreshRouteDetails(model)
end

function view.Browse(row)
    if not row.quest then return end
    focused = key(row.quest)
    view.RefreshWindow()
end

function view.CycleObjective()
    local panel=view.Window.selection
    local entries=guideRows(panel.quest)
    local at=0
    for index,entry in ipairs(entries) do
        if objectiveFocus and entry.questID==objectiveFocus.questID and entry.index==objectiveFocus.index then at=index end
    end
    for offset=1,#entries do
        local entry=entries[(at+offset-1)%#entries+1]
        if not entry.finished then objectiveFocus={questID=entry.questID,index=entry.index};break end
    end
    view.RefreshWindow()
end

function view.RouteObjective(cycle)
    local entry=view.Window.selection.objectiveEntry
    if not entry then return end
    local ok,reason=planner.Controller.SelectObjective(entry.questID,entry.index,cycle)
    if not ok then core:Print(reason) end
end

function view.ActOnSelection(action)
    local quest = view.Window.selection.quest
    if not quest then return end
    if action=="route" and view.Window.selection.objectiveEntry then view.RouteObjective(false)
    elseif action == "area" then
        if quest.destination then view.Command("avoid " .. quest.destination.mapID) end
    elseif planner.Schema.ID(quest.questID) then
        if action == "log" then planner.OpenQuest(quest.questID)
        elseif action ~= "route" or (quest.destination and not excluded(quest)) then
            view.Command(action .. " " .. quest.questID)
        end
    end
    view.RefreshWindow()
end

function view.ChangePage(delta)
    local list = quests()
    page = math.max(1, math.min(math.max(1, math.ceil(#list / ui.PAGE_SIZE)), page + delta))
    focused = key(list[(page - 1) * ui.PAGE_SIZE + 1])
    view.RefreshWindow()
end

function view.NextFilter()
    filterIndex = filterIndex % #FILTERS + 1; page = 1; focused = nil; view.RefreshWindow()
end

function view.ToggleDetails()
    local window = view.Window
    local open = not window.details:IsShown()
    window.details:SetShown(open); window.questList:SetShown(not open); window.selection:SetShown(not open)
    window.detailToggle.label:SetText(open and "Back to quests" or "Route details")
    if open then refreshRouteDetails(planner.Controller.Get()) end
end

function view.Open()
    if not planner.enabled then return end
    core.Combat.Queue(function()
        if not view.Window then view.Window = ui.Create() end
        view.Window:Show(); view.Refresh()
    end, "questplanner:window")
end
