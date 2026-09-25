-- The README's Commands section and the slash-command router stay in step: every name registered
-- through core:RegisterCommand in a TOC-listed source file is documented, and the section documents
-- no command the router does not know. Bash-style `|` alternatives inside a table cell are escaped.
return function(check)
    local README, TOC = "README.md", "RikUI.toc"

    local function readAll(path)
        local file = io.open(path, "rb")
        if not file then return nil end
        local text = file:read("*a")
        file:close()
        return text
    end

    local function registeredCommands()
        local names, toc = {}, readAll(TOC)
        if not toc then return nil, "cannot read " .. TOC end
        for line in toc:gmatch("[^\r\n]+") do
            local path = line:match("^%s*(src/[^%s#]+%.lua)%s*$")
            local text = path and readAll(path)
            if text then
                for name in text:gmatch('RegisterCommand%(%s*"([a-z]+)"') do names[name] = path end
            end
        end
        return names
    end

    local function documentedCommands()
        local readme = readAll(README)
        if not readme then return nil, "cannot read " .. README end
        local section = readme:match("\n## Commands\n(.-)\n## ")
        if not section then return nil, "README has no Commands section" end
        local names = {}
        for name in section:gmatch("`/rik ([a-z]+)") do names[name] = true end
        return names
    end

    local registered, registeredReason = registeredCommands()
    local documented, documentedReason = documentedCommands()
    check("router commands can be collected", registered ~= nil, registeredReason)
    check("README Commands section can be read", documented ~= nil, documentedReason)
    if not (registered and documented) then return end

    local count = 0
    for _ in pairs(registered) do count = count + 1 end
    check("the router registers the expected number of commands", count >= 30, tostring(count))

    local undocumented, unknown = {}, {}
    for name in pairs(registered) do
        if not documented[name] then undocumented[#undocumented + 1] = name end
    end
    for name in pairs(documented) do
        if not registered[name] then unknown[#unknown + 1] = name end
    end
    table.sort(undocumented)
    table.sort(unknown)
    check("every registered command is in the README", #undocumented == 0, table.concat(undocumented, ", "))
    check("the README lists no command the router lacks", #unknown == 0, table.concat(unknown, ", "))
end
