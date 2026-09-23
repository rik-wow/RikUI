-- Every runtime source in the TOC must go through the hook gateway.
return function(check)
    for line in io.lines("RikUI.toc") do
        local path = line:gsub("\r", ""):gsub("\\", "/")
        if path:match("^src/.*%.lua$") and path ~= "src/platform/hooks.lua" then
            local file = assert(io.open(path, "r"))
            local source = file:read("*a")
            file:close()
            check("hook policy: " .. path, not source:find("hooksecurefunc%s*%("))
        end
    end
    local saved = RikUI
    RikUI = {}
    assert(loadfile("src/platform/hooks.lua"))()
    local hooks = RikUI.Hooks
    local called, tbl = false, { work = function() return 1, nil, 3, nil end }
    check("unowned methods cannot be wrapped", not pcall(hooks.Owned, tbl, "work", function() end))
    hooks.Own(tbl)
    hooks.Owned(tbl, "work", function() called = true end)
    local function arity(...) return select("#", ...), ... end
    local count, first, middle, third = arity(tbl.work())
    check("owned hook preserves nil return slots", called and count == 4 and first == 1 and middle == nil and third == 3)
    check("missing global is skipped", hooks.Function("RikUIMissingHookTarget", function() end) == false)
    check("non-frame scripts are skipped", hooks.Script({}, "OnShow", function() end) == false)
    check("Blizzard namespaces cannot be arbitrary objects",
        not pcall(hooks.Namespace, "WorldMapFrame", "Show", function() end))
    RikUI = saved
end
