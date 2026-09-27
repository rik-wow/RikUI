-- Fake of the 69913 tooltip surface RikUI touches: a GameTooltip with its NineSlice backdrop and
-- GUID-watched unit health bar, text lines, the shared anchor and backdrop functions, the tooltip
-- font objects and a TooltipDataProcessor that records post-calls so a test can replay them.
local stub = { postCalls = {} }

local function region(parent, kind)
    local r = { kind = kind, parent = parent, text = "" }
    function r:SetText(text) self.text = text end
    function r:GetText() return self.text end
    function r:SetTextColor(...) self.color = { ... } end
    function r:SetTexture(texture) self.texture = texture end
    function r:SetColorTexture(...) self.color = { ... } end
    function r:SetVertexColor(...) self.color = { ... } end
    function r:SetAllPoints() self.allPoints = true end
    function r:SetPoint(...) self.points = self.points or {}; table.insert(self.points, { ... }) end
    function r:SetHeight(height) self.height = height end
    function r:SetWidth(width) self.width = width end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    return r
end

local function fontObject()
    local object = {}
    function object:SetFont(path, size, flags) self.fontPath, self.fontSize, self.flags = path, size, flags; return true end
    function object:SetTextColor(...) self.color = { ... } end
    function object:SetShadowColor(...) self.shadow = { ... } end
    function object:SetShadowOffset(...) self.offset = { ... } end
    return object
end

-- GameTooltipUnitHealthBarMixin surface: SetWatch/ClearWatch drive the bar in secure code.
local function statusBar(tip)
    local bar = CreateFrame("StatusBar", tip:GetName() .. "StatusBar", tip)
    bar.shown = false
    -- rawget: the shared Frame metatable answers unknown fields with a no-op function.
    function bar:SetWatch(guid) self.watched, self.shown, self.watches = guid, true, (rawget(self, "watches") or 0) + 1 end
    function bar:ClearWatch() self.watched, self.shown = nil, false end
    function bar:SetValue() self.valueWrites = (rawget(self, "valueWrites") or 0) + 1 end
    function bar:SetMinMaxValues() self.valueWrites = (rawget(self, "valueWrites") or 0) + 1 end
    function bar:SetStatusBarTexture(texture) self.texture = texture end
    function bar:SetStatusBarColor(...) self.color = { ... } end
    function bar:SetHeight(height) self.height = height end
    function bar:CreateTexture(_, layer) local t = region(self, "Texture"); t.layer = layer; return t end
    return bar
end

function stub.tooltip(name)
    local tip = CreateFrame("GameTooltip", name, UIParent)
    tip.animationGroups = {}
    function tip:CreateAnimationGroup()
        local group = require("widget_stub").animationGroup()
        self.animationGroups[#self.animationGroups + 1] = group
        return group
    end
    tip.scale = 1
    function tip:GetScale() return self.scale end
    function tip:SetScale(value) self.scale = value end
    tip.NineSlice = CreateFrame("Frame", nil, tip)
    function tip.NineSlice:SetCenterColor(...) self.center = { ... } end
    tip.StatusBar = statusBar(tip)
    tip.lines, tip.textures = {}, {}
    function tip:SetOwner(owner, anchor) self.owner, self.anchorType = owner, anchor end
    function tip:SetUnit(unit) self.unit, self.shown = unit, true; return true end
    function tip:SetAction(slot) self.action, self.shown = slot, true; return true end
    function tip:SetShapeshift(index) self.shapeshift, self.shown = index, true; return true end
    function tip:SetPetAction(index) self.petAction, self.shown = index, true; return true end
    function tip:GetOwner() return self.owner end
    function tip:ClearAllPoints() self.point = nil end
    function tip:SetPoint(...) self.point = { ... } end
    function tip:NumLines() return #self.lines end
    function tip:AddLine(text, r, g, b)
        local line = region(self, "FontString")
        line.text, line.color = text, { r, g, b }
        table.insert(self.lines, line)
    end
    function tip:GetLeftLine(index) return self.lines[index] end
    function tip:CreateTexture(_, layer) local t = region(self, "Texture"); t.layer = layer; table.insert(self.textures, t); return t end
    local hide = tip.Hide
    function tip:Hide() hide(self); self.StatusBar:ClearWatch() end -- GameTooltip_OnHide clears the watch
    return tip
end

-- Sample the first rendered opacity after Show, including an active alpha animation.
function stub.visibleAlpha(tip)
    if not tip:IsShown() then return 0 end
    local alpha = rawget(tip, "alpha") or 1
    for _, group in ipairs(tip.animationGroups) do
        if group:IsPlaying() and group.animation.kind == "Alpha" then alpha = group.animation.from end
    end
    return alpha
end

-- Replaces the tooltip's lines the way a native SetUnit/SetItem would before post-calls run.
function stub.setLines(tip, texts)
    tip.lines = {}
    for _, text in ipairs(texts) do tip:AddLine(text, 1, 1, 1) end
    tip.shown = true
end

-- Runs the recorded post-calls for one tooltip type like the client after the lines are built.
function stub.process(kind, tip, data)
    tip.shown = true
    for _, callback in ipairs(stub.postCalls[Enum.TooltipDataType[kind]] or {}) do callback(tip, data) end
end

local function installGlobals()
    function GameTooltip_SetDefaultAnchor(tip, parent)
        tip:SetOwner(parent, "ANCHOR_NONE")
        tip:SetPoint("BOTTOMRIGHT", GameTooltipDefaultContainer, "BOTTOMRIGHT", 0, 0)
    end
    function SharedTooltip_SetBackdropStyle(tip)
        tip.NineSlice:Show()
        tip.NineSlice:SetCenterColor(0.09, 0.09, 0.19, 1)
    end
    GameTooltipText, GameTooltipHeaderText, GameTooltipTextSmall = fontObject(), fontObject(), fontObject()
    Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Corpse = 3 }
    TooltipDataProcessor = {
        AllTypes = "ALL",
        AddTooltipPreCall = function() end,
        AddTooltipPostCall = function(kind, callback)
            stub.postCalls[kind] = stub.postCalls[kind] or {}
            table.insert(stub.postCalls[kind], callback)
        end,
    }
    function UnitTokenFromGUID(guid) return stub.guids[guid] end
    function UnitGUID(unit)
        for guid, token in pairs(stub.guids) do
            if token == unit then return guid end
        end
    end
    function GetGuildInfo(unit) return stub.guilds[unit] end
    C_Item.GetDetailedItemLevelInfo = function(item) return stub.itemLevels[item] end
end

-- Fresh tooltips, globals and recorders; call again for every scenario that reloads the addon.
function stub.install(env)
    stub.env, stub.postCalls = env, {}
    stub.guids, stub.guilds, stub.itemLevels = { ["Creature-0-1"] = "target", ["Player-1"] = "player" }, {}, {}
    GameTooltipDefaultContainer = CreateFrame("Frame", "GameTooltipDefaultContainer", UIParent)
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
        _G[name] = stub.tooltip(name)
    end
    installGlobals()
end

return stub
