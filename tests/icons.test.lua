-- The icon set: every name the addon may ask for has an SVG source and a built TGA, every file on disk
-- is a known name, and an unknown name is refused instead of silently drawing nothing in game.
return function(check)
    local env = require("wow_stub")
    local SIZE, HEADER = 32, 18
    local ok, reason = pcall(function()
        env.frames, env.printed = {}, {}
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        assert(loadfile("core.lua"))("RikUI", {})
        assert(loadfile("media.lua"))("RikUI", {})
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
                    if extension == ".tga" and #bytes ~= HEADER + SIZE * SIZE * 4 then sizes[#sizes + 1] = name end
                end
            end
        end
        table.sort(missing)
        check("every known icon has an SVG source and a built TGA", known >= 30 and #missing == 0, table.concat(missing, ", "))
        check("every built icon is a 32x32 32-bit TGA", #sizes == 0, table.concat(sizes, ", "))

        local strangers = {}
        for line in io.popen("ls media/icons"):lines() do
            local name = line:gsub("\r", ""):match("^(.+)%.svg$")
            if name and not media.Icons[name] then strangers[#strangers + 1] = name end
        end
        check("every SVG on disk is a known icon", #strangers == 0, table.concat(strangers, ", "))
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
