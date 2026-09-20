local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Health travels reader-to-sink into an own bar; target and threat state are copied from Blizzard's
-- regions. Re-parenting Blizzard's text, the target CVars and the easing argument need a beta check.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local API = { "C_NamePlate", "PixelUtil", "UnitClassification" }
    local saved, savedCVar, savedInfoEnum = {}, C_CVar, Enum.NamePlateInfoDisplay
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local stub = {}
    local function group()
        local result = { plays = 0, stops = 0 }
        function result:CreateAnimation() return setmetatable({}, { __index = function() return function() end end }) end
        function result:Play() self.plays, self.playing = self.plays + 1, true end
        function result:Stop() self.stops, self.playing = self.stops + 1, false end
        function result:SetLooping(mode) self.looping = mode end
        return result
    end
    local function common(value)
        function value:SetAlpha(alpha) self.alpha = alpha end
        function value:SetShown(shown)
            if type(rawget(self, "scripts")) == "table" and rawget(self, "kind") ~= "Texture"
                and rawget(self, "kind") ~= "FontString" then
                if shown then self:Show() else self:Hide() end
                return
            end
            self.shown = shown == true
        end
        function value:SetHeight(height) self.height = height end
        function value:SetWidth(width) self.width = width end
        function value:SetParent(parent) self.parent = parent end
        function value:CreateAnimationGroup() return group() end
        function value:ClearAllPoints() self.points = {} end
        function value:SetPoint(...)
            local points = rawget(self, "points") or {}
            points[#points + 1] = { ... }
            self.points = points
        end
        return value
    end
    local function region(value)
        common(value)
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetTextColor(...) self.color = { ... } end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetJustifyH(justify) self.justify = justify end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        common(frame)
        function frame:GetParent() return self.parent end
        function frame:GetEffectiveScale() return 2 end
        function frame:GetFrameLevel() return rawget(self, "level") or 1 end
        function frame:SetFrameLevel(level) self.level = level end
        function frame:SetStatusBarTexture(texture) self.barTexture = texture end
        function frame:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
        function frame:SetMinMaxValues(low, high) self.range = { low, high } end
        function frame:SetValue(value, easing) self.value, self.easing = value, easing end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function toggled(texture)
        texture.shown = false
        function texture:Hide() self.shown = false end
        function texture:IsShown() return self.shown end
        return texture
    end
    local function castBar(frame)
        frame.CastBarsContainer = CreateFrame("Frame", nil, frame)
        local bar = CreateFrame("StatusBar", nil, frame.CastBarsContainer)
        bar.Border, bar.BorderShield, bar.Background, bar.Icon = bar:CreateTexture(), bar:CreateTexture(),
            bar:CreateTexture(), bar:CreateTexture()
        bar.Text, bar.CastTargetNameText = bar:CreateFontString(), bar:CreateFontString()
        frame.CastBarsContainer.castBar = bar
    end
    -- Blizzard's layout pass puts the atlases, fonts and anchors back, as UpdateAnchors does.
    local function unitFrame()
        local frame = CreateFrame("Button", nil, UIParent)
        frame.HealthBarsContainer = CreateFrame("Frame", nil, frame)
        local bar = CreateFrame("StatusBar", nil, frame.HealthBarsContainer)
        bar.barTexture, bar.bgTexture = bar:CreateTexture(), bar:CreateTexture()
        bar.selectedBorder = toggled(bar:CreateTexture())
        bar.Text, bar.LeftText, bar.RightText = bar:CreateFontString(), bar:CreateFontString(), bar:CreateFontString()
        frame.HealthBarsContainer.healthBar = bar
        frame.name = toggled(frame:CreateFontString())
        frame.name.shown = true
        local level = CreateFrame("Frame", nil, frame)
        level.playerLevelDiffText, level.playerLevelDiffIcon = level:CreateFontString(), level:CreateTexture()
        level.selectedBorder = level:CreateTexture()
        frame.PlayerLevelDiffFrame = level
        frame.AurasFrame = CreateFrame("Frame", nil, frame)
        frame.AurasFrame.DebuffListFrame = CreateFrame("Frame", nil, frame.AurasFrame)
        castBar(frame)
        frame.aggroHighlight = toggled(frame:CreateTexture())
        frame.aggroHighlightTextures = { frame:CreateTexture(), frame:CreateTexture() }
        frame.aggroHighlightTextures[1].texture = "flare"
        function frame:UpdateAggroHighlight() end
        function frame:IsShowOnlyName() return self.nameOnly == true end
        function frame:UpdateAnchors()
            bar.bgTexture.texture, self.name.fontPath, self.HealthBarsContainer.height = "atlas-bg", "stock-font", 8
        end
        return frame
    end
    local function plate(unit, forbidden)
        local result = { UnitFrame = unitFrame() }
        function result:IsForbidden() return forbidden == true end
        stub.plates[unit] = result
        return result
    end
    local function installCVars()
        stub.cvars = { nameplateSelectedScale = "1", nameplateNotSelectedAlpha = "1", nameplateInfoDisplay = "0" }
        stub.bits = {}
        C_CVar = {
            GetCVarInfo = function(name) return stub.cvars[name] end,
            GetCVar = function(name) return stub.cvars[name] end,
            SetCVar = function(name, value)
                assert(not InCombatLockdown(), "CVar written in combat")
                stub.cvars[name] = value
            end,
            SetCVarBitfield = function(name, index, value) stub.bits[name .. ":" .. index] = value end,
        }
        Enum.NamePlateInfoDisplay = { CurrentHealthPercent = 1 }
    end
    local function load(profile, combat, missingContainer)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, combat == true, {}
        env.auraContainerMissing = missingContainer == true
        stub.plates, stub.classification = {}, "normal"
        C_NamePlate = { GetNamePlateForUnit = function(unit) return stub.plates[unit] end }
        PixelUtil = { GetNearestPixelSize = function(size, scale) return size / scale end }
        UnitClassification = function() return stub.classification end
        installCVars()
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes, profile.modules.auras, profile.modules.unitauras = false, false, false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
            "src/modules/auras/auras.lua", "src/modules/auras/auras-button.lua", "src/modules/nameplates/nameplates.lua",
            "src/modules/nameplates/nameplates-skin.lua", "src/modules/nameplates/nameplates-target.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Nameplates
    end
    local ok, reason = pcall(function()
        local module = load()
        local media = RikUI.Media
        check("the client's target scale, non-target alpha and health percent are switched on",
            stub.cvars.nameplateSelectedScale == "1.15" and stub.cvars.nameplateNotSelectedAlpha == "0.6"
            and stub.bits["nameplateInfoDisplay:1"] == true)
        check("the original settings are kept in the profile", RikUI.Profile.nameplateCVars.nameplateSelectedScale == "1"
            and RikUI.Profile.nameplateCVars.nameplateInfoDisplay == "0")

        stub.classification = "elite"
        local first = plate("nameplate1")
        local frame, bar = first.UnitFrame, first.UnitFrame.HealthBarsContainer.healthBar
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        local parts = module.Parts[frame]
        local own = parts.bar
        check("the plate gets an own bar over Blizzard's with the RikUI texture and Blizzard's fill faded",
            own.parent == bar and own.barTexture == media.statusbar and bar.barTexture.alpha == 0)
        check("the bar is 14 high on a flat one-pixel backing", frame.HealthBarsContainer.height == 14
            and bar.bgTexture.texture == "Interface\\BUTTONS\\WHITE8X8" and bar.bgTexture.points[1][4] == -0.5)
        check("health reaches the own bar as a secret without easing on the first fill", own.value == 42
            and own.range[2] == 100 and own.easing == Enum.StatusBarInterpolation.Immediate)
        check("the bar takes the unit's reaction or class colour", type(own.barColor) == "table" and #own.barColor == 3)
        check("the name is centred inside its plaque in the RikUI font and truncates instead of wrapping",
            rawget(frame.name, "parent") == frame and frame.name.fontPath == media.font and frame.name.justify == "CENTER"
            and #frame.name.points == 2 and frame.name.points[1][2] == parts.plaque
            and frame.name.points[2][2] == parts.plaque and frame.name.points[2][4] < 0)
        check("the plaque is a flat bordered box exactly as wide as the bar and level box, sharing their top edge",
            parts.plaque.shown == true and parts.plaque.texture == "Interface\\BUTTONS\\WHITE8X8"
            and parts.plaque.color[1] < 0.2 and parts.plaque.height == 13
            and parts.plaque.points[1][1] == "BOTTOMLEFT" and parts.plaque.points[1][2] == bar.bgTexture
            and parts.plaque.points[1][3] == "TOPLEFT" and parts.plaque.points[1][5] == -0.5
            and parts.plaque.points[2][1] == "BOTTOMRIGHT" and parts.plaque.points[2][2] == parts.levelBox
            and #parts.plaqueBorder == 4 and parts.plaqueBorder[1].height == 0.5
            and parts.plaqueBorder[1].shown == true)
        frame.name:Hide()
        check("the plaque hides when Blizzard hides the name", parts.plaque.shown == false
            and parts.plaqueBorder[3].shown == false)
        frame.name:SetShown(true)
        check("and returns with it", parts.plaque.shown == true)
        check("all three of Blizzard's health texts are centred inside the bar", bar.LeftText.parent == own
            and bar.LeftText.fontPath == media.font and bar.LeftText.points[1][1] == "CENTER"
            and bar.LeftText.points[1][2] == own and bar.RightText.points[1][2] == own
            and bar.Text.points[1][2] == own and #bar.Text.points == 1)
        check("an elite gets a gold star left of the bar", own.marker.rikIcon == "star" and own.marker:IsShown()
            and own.marker.color[2] > 0.8 and own.marker.color[4] == nil
            and own.marker.points[1][3] == "LEFT")
        check("an added plate fades in", parts.fade.plays == 1)

        local level = frame.PlayerLevelDiffFrame
        check("the level box takes the bar's height, loses Blizzard's art and centres the number",
            level.playerLevelDiffIcon.alpha == 0 and level.selectedBorder.alpha == 0 and #parts.levelBox.points == 4
            and parts.levelBox.points[3][2] == bar and parts.levelBorder[1].height == 0.5
            and level.playerLevelDiffText.points[1][2] == parts.levelBox)

        env.fire("UNIT_HEALTH", "nameplate1")
        check("a health event eases the bar and flashes it", own.easing == Enum.StatusBarInterpolation.ExponentialEaseOut
            and own.flashAnim.plays == 1 and own.flash.alpha == 0)
        env.fire("UNIT_MAXHEALTH", "nameplate1")
        check("a maximum health event refills without a flash", own.flashAnim.plays == 1)
        env.fire("UNIT_HEALTH", "nameplate9")
        env.fire("UNIT_HEALTH", env.SECRET)
        check("health events for other or secret tokens are ignored", own.flashAnim.plays == 1 and #env.printed == 0)
        stub.classification = "rare"
        env.fire("UNIT_CLASSIFICATION_CHANGED", "nameplate1")
        check("a classification change updates the marker", own.marker.rikIcon == "diamond")
        stub.classification = env.SECRET
        env.fire("UNIT_CLASSIFICATION_CHANGED", "nameplate1")
        check("a secret classification clears the marker without printing", not own.marker:IsShown() and #env.printed == 0)

        check("Blizzard's selection art is faded and the target indicators start hidden", bar.selectedBorder.alpha == 0
            and parts.arrowLeft.shown == false and parts.arrowRight.shown == false and parts.accent.shown == false)
        bar.selectedBorder:SetShown(true)
        check("Blizzard selecting the plate shows the arrows and the pulsing accent line", parts.arrowLeft.shown
            and parts.arrowRight.shown and parts.accent.shown and parts.accentPulse.playing
            and parts.accentPulse.looping == "BOUNCE" and parts.arrowLeft.appear.plays == 1)
        bar.selectedBorder:SetShown(true)
        check("a repeated selection does not restart the animations", parts.arrowLeft.appear.plays == 1)
        bar.selectedBorder:Hide()
        check("deselecting hides them and stops the pulse", parts.arrowLeft.shown == false
            and parts.accent.shown == false and parts.accentPulse.playing == false)
        check("arrows flank the marker and the level box; the accent line runs under the backing",
            parts.arrowLeft.points[1][2] == own and parts.arrowRight.points[1][2] == parts.levelBox
            and parts.accent.points[1][2] == bar.bgTexture and parts.accent.points[1][3] == "BOTTOMLEFT"
            and parts.accent.height == 1)

        check("Blizzard's aggro flare art is blanked and the threat line starts hidden",
            rawget(frame.aggroHighlightTextures[1], "texture") == nil and parts.threat.shown == false)
        frame.aggroHighlight.shown = true
        frame:UpdateAggroHighlight()
        check("the threat line follows Blizzard's aggro state", parts.threat.shown == true
            and parts.threat.color[1] == 1 and parts.threat.points[1][3] == "TOPLEFT")
        frame.aggroHighlight.shown = false
        frame:UpdateAggroHighlight()
        check("and hides with it", parts.threat.shown == false)

        local cast = frame.CastBarsContainer.castBar
        check("the cast bar goes flat with its fill left to Blizzard", cast.Border.alpha == 0
            and cast.Background.texture == "Interface\\BUTTONS\\WHITE8X8" and cast.Text.fontPath == media.font
            and #parts.castBorder == 4 and rawget(cast, "barTexture") == nil)

        frame:UpdateAnchors()
        check("the layout is reapplied after Blizzard's layout pass", frame.HealthBarsContainer.height == 14
            and bar.bgTexture.texture == "Interface\\BUTTONS\\WHITE8X8" and frame.name.fontPath == media.font)
        frame.nameOnly = true
        frame:UpdateAnchors()
        check("a name-only plate gets no plaque", parts.plaque.shown == false)
        frame.nameOnly = false
        frame:UpdateAnchors()
        check("the plaque returns when the plate shows its bar again", parts.plaque.shown == true)

        local container = module.Containers[frame]
        check("own debuffs sit in a container above the name plaque", container ~= nil and container.unit == "nameplate1"
            and container.groups.owndebuffs.filter == "HARMFUL|PLAYER" and container.points[1][1] == "BOTTOM"
            and container.points[1][2] == parts.plaque and container.points[1][3] == "TOP")
        local stockList = frame.AurasFrame.DebuffListFrame
        check("Blizzard's debuff list is hidden once the container exists", stockList:IsShown() == false)
        stockList:SetShown(true)
        check("and hidden again when Blizzard's aura display update shows it", stockList:IsShown() == false)
        local hooks, updates = #env.hooks, container.updates
        env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        check("a removed plate hides its container", container:IsShown() == false and module.Active.nameplate1 == nil)
        stub.plates.nameplate7, stub.plates.nameplate1 = first, nil
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
        check("a pooled frame is reused without new hooks or parts and fades in again", #env.hooks == hooks
            and module.Parts[frame] == parts and container.unit == "nameplate7" and container.updates == updates + 1
            and parts.fade.plays == 2 and own.easing == Enum.StatusBarInterpolation.Immediate)

        local forbidden = plate("nameplate2", true)
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        check("a forbidden plate is never touched", module.Parts[forbidden.UnitFrame] == nil
            and rawget(forbidden.UnitFrame.HealthBarsContainer.healthBar.barTexture, "alpha") == nil)
        local bare = plate("nameplate4")
        bare.UnitFrame.PlayerLevelDiffFrame, bare.UnitFrame.AurasFrame, bare.UnitFrame.CastBarsContainer = nil, nil, nil
        bare.UnitFrame.aggroHighlight, bare.UnitFrame.HealthBarsContainer.healthBar.LeftText = nil, nil
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
        local bareParts = module.Parts[bare.UnitFrame]
        check("a plate without level, cast, aura, aggro or percent regions is still laid out", bareParts ~= nil
            and bareParts.arrowRight.points[1][2] == bareParts.bar and #env.printed == 0
            and bareParts.plaque.points[2][2] == bare.UnitFrame.HealthBarsContainer.healthBar.bgTexture)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports skinned frames, active plates and containers",
            printedContains("Nameplates skinned=2 active=2 containers=2"))

        module = load(nil, true)
        check("a combat login leaves the client settings alone", stub.cvars.nameplateSelectedScale == "1")
        local fighting = plate("nameplate1")
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        check("a plate added in combat is laid out but gets no container yet", module.Parts[fighting.UnitFrame] ~= nil
            and module.Containers[fighting.UnitFrame] == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat writes the settings and gives active plates their containers",
            stub.cvars.nameplateSelectedScale == "1.15" and module.Containers[fighting.UnitFrame] ~= nil)

        module = load(nil, false, true)
        local plain = plate("nameplate1")
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        check("a client without the aura container keeps Blizzard's debuffs and warns once",
            module.Containers[plain.UnitFrame] == nil and plain.UnitFrame.AurasFrame.DebuffListFrame:IsShown() == true
            and printedContains("Auras container") and #env.printed == 1)

        module = load({ modules = { nameplates = false }, nameplateCVars = { nameplateSelectedScale = "1.3" } })
        local stock = plate("nameplate1")
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        check("a disabled module leaves the stock plates alone and hands the saved settings back",
            module.Parts[stock.UnitFrame] == nil and #env.hooks == 0 and stub.cvars.nameplateSelectedScale == "1.3"
            and stub.cvars.nameplateNotSelectedAlpha == "1" and RikUI.Profile.nameplateCVars == nil)
    end)
    CreateFrame = originalCreate
    C_CVar, Enum.NamePlateInfoDisplay = savedCVar, savedInfoEnum
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat, env.auraContainerMissing = false, false
    check("nameplate suite completes", ok, reason)
end
