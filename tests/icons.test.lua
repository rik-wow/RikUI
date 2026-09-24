local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The icon set: every name the addon may ask for has an SVG source and a built TGA, every file on disk
-- is checked against the registry by check_manifest.py. Unknown names are refused in game.
return function(check)
    local env = require("wow_stub")
    local SIZE, HEADER = 32, 18
    local savedStandardFont = STANDARD_TEXT_FONT
    local ok, reason = pcall(function()
        env.frames, env.printed = {}, {}
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        assert(loadfile("src/core/core.lua"))("RikUI", {})
        assert(loadfile("src/ui/media.lua"))("RikUI", {})
        local media = RikUI.Media
        RikUI.Profile = { textScale = 1.2 }
        check("role text scales independently", media.Size and media.Size("label") == 16)
        RikUI.Profile.textScale = 99
        check("role text clamps excessive scale", media.Size and media.Size("small") == 14)
        RikUI.Profile.textScale = 0 / 0
        check("role text ignores non-finite scale", media.Size and media.Size("label") == 13)
        RikUI.Profile.textScale = 1.2
        local scaled = CreateFrame("Frame"):CreateFontString()
        function scaled:SetFont(_, size) self.measured = size; return true end
        media.Font(scaled, "small")
        check("Font uses scaled role at its actual sink", scaled.measured == 13)
        RikUI.Profile = nil
        local bundledChoice = media.font
        STANDARD_TEXT_FONT = "Fonts\\ARIALN.TTF"
        RikUI.Profile = { font = "game" }
        if media.Configure then media.Configure() end
        check("game font choice uses the locale-native font", media.font == STANDARD_TEXT_FONT)
        RikUI.Profile.font = "unknown"
        if media.Configure then media.Configure() end
        check("unknown font choice returns to bundled path", media.font == bundledChoice)
        RikUI.Profile.font = "game"
        STANDARD_TEXT_FONT = nil
        if media.Configure then media.Configure() end
        check("game font choice has a known fallback", media.font == "Fonts\\FRIZQT__.TTF")
        RikUI.Profile = nil
        if media.Configure then media.Configure() end
        local known, missing, sizes = 0, {}, {}
        for name in pairs(media.Icons) do
            known = known + 1
            for _, extension in ipairs({ ".svg", ".tga" }) do
                local file = io.open("media/icons/" .. name .. extension, "rb")
                if not file then missing[#missing + 1] = name .. extension
                else
                    local bytes = file:read("*a")
                    file:close()
                    if extension == ".tga" then
                        local width = (bytes:byte(13) or 0) + 256 * (bytes:byte(14) or 0)
                        local height = (bytes:byte(15) or 0) + 256 * (bytes:byte(16) or 0)
                        local valid = #bytes == HEADER + SIZE * SIZE * 4 and bytes:byte(1) == 0
                            and bytes:byte(2) == 0 and bytes:byte(3) == 2
                            and width == SIZE and height == SIZE and bytes:byte(17) == 32
                        if not valid then sizes[#sizes + 1] = name end
                    end
                end
            end
        end
        table.sort(missing)
        check("every known icon has an SVG source and a built TGA", known >= 30 and #missing == 0, table.concat(missing, ", "))
        check("every built icon is a 32x32 32-bit TGA", #sizes == 0, table.concat(sizes, ", "))

        check("an icon's path points into the addon's media folder",
            media.IconPath("close") == "Interface\\AddOns\\RikUI\\media\\icons\\close.tga")
        local refused = pcall(media.IconPath, "clsoe")
        check("an unknown icon name is refused", refused == false)
        local texture = CreateFrame("Frame", nil, UIParent):CreateTexture(nil, "ARTWORK")
        media.SetIcon(texture, "lock")
        check("SetIcon records the name on the texture", texture.rikIcon == "lock")
        local fontFile = assert(io.open("media/font.ttf", "rb"))
        local signature = fontFile:read(4)
        fontFile:close()
        check("bundled font is a TrueType asset", signature == string.char(0, 1, 0, 0))
        local label = CreateFrame("Frame"):CreateFontString()
        local calls, bundled = {}, media.font
        function label:SetFont(path, size, flags)
            calls[#calls + 1] = { path, size, flags }
            return true
        end
        media.Font(label, "small")
        check("loadable bundled font keeps its path and stays quiet", calls[1][1] == bundled
            and calls[1][2] == media.sizes.small and media.font == bundled and #env.printed == 0)
        STANDARD_TEXT_FONT = "Fonts\\ARIALN.TTF"
        function label:SetFont(path, size, flags)
            calls[#calls + 1] = { path, size, flags }
            return path ~= bundled
        end
        media.Font(label, "label")
        check("failed bundled font retries the same region with the native font", calls[2][1] == bundled
            and calls[3][1] == STANDARD_TEXT_FONT and calls[3][2] == media.sizes.label
            and calls[3][3] == "OUTLINE" and media.font == STANDARD_TEXT_FONT)
        media.Font(label, "heading")
        check("later font users share the working fallback with one message", #calls == 4
            and calls[4][1] == STANDARD_TEXT_FONT and #env.printed == 1)
        assert(loadfile("src/ui/media.lua"))("RikUI", {})
        media, calls, env.printed = RikUI.Media, {}, {}
        STANDARD_TEXT_FONT = nil
        media.Font(label, "small")
        check("missing native font global uses the built-in fallback", calls[2][1] == "Fonts\\FRIZQT__.TTF"
            and media.font == "Fonts\\FRIZQT__.TTF")
        assert(loadfile("src/ui/media.lua"))("RikUI", {})
        media, env.printed = RikUI.Media, {}
        function label:SetFont() return false end
        media.Font(label, "small"); media.Font(label, "small")
        check("failed fallback is reported without advertising a working font", media.font == bundled
            and #env.printed == 1 and env.printed[1]:find("fallback could not load", 1, true))
    end)
    STANDARD_TEXT_FONT = savedStandardFont
    check("icons suite completes", ok, reason)
end
