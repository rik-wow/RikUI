-- Fixture composition follows the production manifest; no duplicate service list.
local loader = {}

function loader.Manifest()
    local file = assert(io.open("RikUI.toc", "r"))
    local paths = {}
    for line in file:lines() do
        local path = line:match("^%s*(.-)%s*$")
        if path ~= "" and not path:match("^#") then paths[#paths + 1] = path end
    end
    file:close()
    return paths
end

function loader.Core(addonName, namespace)
    addonName, namespace = addonName or "RikUI", namespace or {}
    for _, path in ipairs(loader.Manifest()) do
        if path:match("^src/core/") or path == "src/ui/primitives.lua" then
            assert(loadfile(path))(addonName, namespace)
        end
    end
    return RikUI
end

-- Existing feature fixtures request core.lua as one logical runtime.
function loader.Loadfile(path)
    if path == "src/core/core.lua" then return loader.Core end
    return loadfile(path)
end

return loader
