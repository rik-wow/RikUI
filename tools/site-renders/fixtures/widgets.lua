-- Objective widgets: the simulator has no widget data, so the fixture answers C_UIWidgetManager for one
-- top-centre set and lets Blizzard's manager build the frames; RikUI's widget module skins them.

local WIDGET_BASE = { shownState = 1, enabledState = 1, hasTimer = false, orderIndex = 0, widgetTag = "", inAnimType = 0,
    outAnimType = 0, widgetScale = 0, layoutDirection = 0, modelSceneLayer = 0, scriptedAnimationEffectID = 0,
    widgetSizeSetting = 0, textureKit = "", frameTextureKit = "", tooltip = "", tooltipLoc = 0 }

local function widgetInfo(fields)
    for key, value in pairs(WIDGET_BASE) do
        if fields[key] == nil then fields[key] = value end
    end
    return fields
end

-- kinds: a list of "status", "double", "capture", "icon", "texture"; the widgets appear in that order
-- in UIWidgetTopCenterContainerFrame, which the capture holds.
function RikRenderWidgets(kinds)
    local T = Enum.UIWidgetVisualizationType
    local M = C_UIWidgetManager
    local TYPES = { status = T.StatusBar, double = T.DoubleStatusBar, capture = T.CaptureBar, icon = T.IconAndText, texture = T.TextureAndText }
    local set = {}
    for index, kind in ipairs(kinds) do
        set[#set + 1] = { widgetID = index, widgetType = assert(TYPES[kind], "Unknown widget kind " .. tostring(kind)), widgetSetID = 1 }
    end
    M.GetTopCenterWidgetSetID = function() return 1 end
    M.GetBelowMinimapWidgetSetID = function() return 2 end
    M.GetPowerBarWidgetSetID = function() return 3 end
    M.GetObjectiveTrackerWidgetSetID = function() return 4 end
    M.GetAllWidgetsBySetID = function(id) return id == 1 and set or {} end
    M.GetWidgetSetInfo = function() return { layoutDirection = 0, verticalPadding = 0 } end
    M.GetStatusBarWidgetVisualizationInfo = function() return widgetInfo({ barMin = 0, barMax = 100, barValue = 64,
        text = "Morale 64%", barValueTextType = 0, overrideBarText = "", overrideBarTextShownType = 0, colorTint = 0,
        partitionValues = {}, fillMotionType = 0, barTextEnabledState = 1, barTextFontType = 0, barTextSizeType = 0,
        textEnabledState = 1, textFontType = 0, textSizeType = 0 }) end
    M.GetDoubleStatusBarWidgetVisualizationInfo = function() return widgetInfo({ leftBarMin = 0, leftBarMax = 100, leftBarValue = 40,
        leftBarTooltip = "", rightBarMin = 0, rightBarMax = 100, rightBarValue = 70, rightBarTooltip = "",
        text = "Alliance 40  Horde 70", leftBarTooltipLoc = 0, rightBarTooltipLoc = 0, fillMotionType = 0 }) end
    M.GetCaptureBarWidgetVisualizationInfo = function() return widgetInfo({ barValue = 60, barMinValue = 0, barMaxValue = 100,
        neutralZoneSize = 20, neutralZoneCenter = 50, glowAnimType = 0, fillDirectionType = 0 }) end
    M.GetIconAndTextWidgetVisualizationInfo = function() return widgetInfo({ text = "Kobold Vermin slain: 6/10", dynamicTooltip = "", state = 1, textSizeType = 0 }) end
    M.GetTextureAndTextVisualizationInfo = function() return widgetInfo({ text = "Fargodeep Mine", textSizeType = 0 }) end
    local container = UIWidgetTopCenterContainerFrame
    container:RegisterForWidgetSet(1)
    A_Admin.FireEvent("UPDATE_ALL_UI_WIDGETS")
    return container
end
