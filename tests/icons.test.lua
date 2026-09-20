local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The icon set: every name the addon may ask for has an SVG source and a built TGA, every file on disk
-- is checked against the registry by check_manifest.py. Unknown names are refused in game.
return function(check)
    local env = require("wow_stub")
    local SIZE, HEADER = 32, 18
    local ok, reason = pcall(function()
        env.frames, env.printed = {}, {}
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        assert(loadfile("src/core/core.lua"))("RikUI", {})
        assert(loadfile("src/ui/media.lua"))("RikUI", {})
        local media = RikUI.Media
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
    end)
    check("icons suite completes", ok, reason)
end
