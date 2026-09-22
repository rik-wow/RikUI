-- Human-scale planner controls; one engine and identical hard feasibility across styles.
local core,planner,media=RikUI,RikUI.QuestPlanner,RikUI.Media
local controls={}
planner.PlanControls=controls
local window,fields,styles
local function label(parent,value,x,y,width)
    local text=parent:CreateFontString(nil,"OVERLAY");media.Font(text,"small")
    text:SetPoint("TOPLEFT",x,y);text:SetWidth(width);text:SetJustifyH("LEFT");text:SetWordWrap(true);text:SetText(value)
    return text
end
local function button(parent,value,x,y,width,fn)
    local control=CreateFrame("Button",nil,parent);control:SetSize(width,24);control:SetPoint("TOPLEFT",x,y)
    control:SetHighlightTexture(media.highlight)
    control.label=label(control,value,6,-4,width-12);control.label:SetHeight(18)
    control:SetScript("OnClick",fn);return control
end
local function command(text)
    planner.Command(text)
    controls.Refresh()
end
local function cycle(key,choices)
    local current=planner.Controller.Policy()[key]
    local at=0;for index,value in ipairs(choices) do if value==current then at=index end end
    local ok,reason=planner.Controller.Preference(key,choices[at%#choices+1])
    if not ok then core:Print(reason) end
    controls.Refresh()
end
local function selected(verb)
    local row=planner.Controller.Get().selected
    if row and row.questID and row.questID>0 then command(verb.." "..row.questID) end
end
local function create()
    window=CreateFrame("Frame","RikUIQuestPlannerPreferences",UIParent)
    window:SetSize(680,628);window:SetPoint("CENTER");window:SetClampedToScreen(true);window:SetFrameStrata("DIALOG");window:EnableMouse(true)
    local fill=window:CreateTexture(nil,"BACKGROUND");fill:SetAllPoints();fill:SetColorTexture(.04,.05,.07,.99)
    label(window,"Questing preferences",16,-14,480)
    button(window,"Close",598,-8,66,function() window:Hide() end)
    label(window,"Choose a style. Session length is advisory; change your mind at any time.",16,-44,640)
    styles={}
    for index,flavor in ipairs(planner.Preferences.Flavors()) do
        local chosen=flavor
        styles[flavor]=button(window,flavor,16+((index-1)%3)*216,-76-math.floor((index-1)/3)*30,208,function()
            command("flavor "..chosen)
        end)
    end
    fields={}
    local rows={
        {"sessionMinutes","Session (minutes)",{15,30,60,120,240,480}},
        {"difficulty","Difficulty",{"easy","standard","hard"}},
        {"group","Group content",{"solo","available"}},
        {"travel","Travel",{"localOnly","regional","world"}},
        {"grind","Repetition tolerance",{"low","medium","high"}},
        {"explorationMinutes","Exploration (minutes)",{0,5,15,30,60}},
        {"services","Optional services",{true,false}},
        {"dungeons","Dungeons",{false,true}},
        {"spoilers","Future story details",{false,true}},
        {"strictSession","Strict time budget",{false,true}},
        {"rewardFocus","Reward focus",{"xp","equipment","reputation","currency","unlocks"}},
    }
    for index,row in ipairs(rows) do
        local key,title,choices=row[1],row[2],row[3]
        fields[key]={title=title,button=button(window,title,16+((index-1)%2)*328,-150-math.floor((index-1)/2)*30,320,
            function() cycle(key,choices) end)}
    end
    label(window,"Goals: quest / map ID; reward target: item / faction / spell ID (empty = any)",16,-342,620)
    window.goal=CreateFrame("EditBox",nil,window)
    media.Font(window.goal,"small")
    local inputFill=window.goal:CreateTexture(nil,"BACKGROUND");inputFill:SetAllPoints();inputFill:SetColorTexture(.12,.15,.18,1)
    window.goal:SetSize(100,24);window.goal:SetPoint("TOPLEFT",22,-370);window.goal:SetAutoFocus(false);window.goal:SetNumeric(true)
    window.goal:SetMaxLetters(10)
    button(window,"Toggle quest goal",132,-370,170,function() command("quest-goal "..window.goal:GetText()) end)
    button(window,"Toggle zone goal",310,-370,170,function() command("zone-goal "..window.goal:GetText()) end)
    button(window,"Reward target",490,-370,172,function() command("reward-target "..window.goal:GetText()) end)
    window.goals=label(window,"",16,-402,640)
    button(window,"Pin current",16,-438,154,function() selected("pin") end)
    button(window,"Defer / restore",180,-438,154,function() selected("defer") end)
    button(window,"Unavailable",344,-438,154,function() command("unavailable") end)
    button(window,"Skip / restore",508,-438,154,function() selected("skip") end)
    button(window,"Decline exploration",16,-472,206,function() command("decline-exploration") end)
    button(window,"New session",238,-472,206,function() command("new-session") end)
    button(window,"Reset learned times",460,-472,202,function() command("reset-learning") end)
    button(window,"Start / stop waiting",16,-502,206,function() command("waiting") end)
    button(window,"Start / stop recovery",238,-502,206,function() command("recovery") end)
    button(window,"Retry action",460,-502,202,function() command("retry-action") end)
    window.note=label(window,"",16,-540,640);window.note:SetHeight(70)
    if type(UISpecialFrames)=="table" then table.insert(UISpecialFrames,"RikUIQuestPlannerPreferences") end
    controls.Window=window
end
function controls.Refresh()
    if not window or not window:IsShown() then return end
    local policy=planner.Controller.Policy()
    for name,control in pairs(styles) do control.label:SetText((policy.flavor==name and "Selected: " or "")..name) end
    for key,row in pairs(fields) do
        local value=policy[key]
        if type(value)=="boolean" then value=value and "on" or "off" end
        row.button.label:SetText(row.title..": "..tostring(value))
    end
    local quests,zones,deferred=0,0,0
    for _ in pairs(policy.questGoals or {}) do quests=quests+1 end
    for _ in pairs(policy.zoneGoals or {}) do zones=zones+1 end
    for _ in pairs(policy.defers or {}) do deferred=deferred+1 end
    window.goals:SetText("Goals: "..quests.." quests, "..zones.." zones. Reward target: "..tostring(policy.rewardTarget or "any")..". Deferred: "..deferred..".")
    local model=planner.Controller.Get()
    local note=model.reason or model.detail or "Live instructions remain available while future options are evaluated."
    for _,conflict in ipairs(model.conflicts or {}) do note=note.." "..conflict end
    window.note:SetText(note)
end
function controls.Attach(parent)
    local open=button(parent,"Preferences",250,-8,126,controls.Open)
    parent.preferences=open
    local defer=button(parent,"Defer current",386,-8,122,function() selected("defer") end)
    parent.deferCurrent=defer
end
function controls.Open()
    if not planner.enabled then return end
    core.Combat.Queue(function()
        if not window then create() end
        window:Show();controls.Refresh()
    end,"questplanner:preferences")
end
