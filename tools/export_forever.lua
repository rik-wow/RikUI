-- Export the complete pinned Forever view through QuestieDB's supported Source API.
-- Run with STOCK Lua 5.1 from the QuestieDB root:
--   lua export_forever.lua output.json expected-40-character-commit
-- LuaJIT cannot parse the full NPC payload; preflight intentionally rejects it.
-- Every provider table is a JSON object, including positional tables. Numeric keys
-- are decimal strings, nil fields are omitted, and empty tables remain {}.
local outputPath = assert(arg[1], 'output JSON path required')
local expectedCommit = assert(arg[2], 'expected QuestieDB commit required')
-- The caller resolves and verifies this acquisition revision; never silently fall back.
local stagingPath = outputPath .. '.tmp'
assert(expectedCommit:match('^[0-9a-f]+$') and #expectedCommit == 40, 'invalid commit')
local config = dofile('src/config.lua')
local lib = dofile('generator/lib.lua')
local loader = dofile('generator/loader.lua')
local client = dofile('emulator/client.lua')
local emulator = dofile('emulator/metadata.lua')
local l10n = dofile('generator/l10n.lua')
local flavor = assert(config.flavorByName.Forever)
local revision = lib.gitCommit()
assert(revision == expectedCommit, 'QuestieDB HEAD does not match expected revision: ' .. revision)
l10n.assertInputs(config.paths.l10n, { flavor })
local types = { 'Quest', 'Npc', 'Item', 'Object' }
local plural = { Quest='quests', Npc='npcs', Item='items', Object='objects' }
local classes = {
  {'WARRIOR',1}, {'PALADIN',2}, {'HUNTER',3}, {'ROGUE',4}, {'PRIEST',5},
  {'SHAMAN',7}, {'MAGE',8}, {'WARLOCK',9}, {'DRUID',11},
}
local rawIds, rawCounts = {}, {}
-- Source mode substitutes {} if its deferred loadstring cannot compile. Validate
-- each identical input with the generator's fail-closed loader before loading it.
for _, entity in ipairs(config.entityTypes) do
  local data = loader.loadEntityData(config.dataPath(flavor, entity), entity)
  local ids = {}; local count = 0
  for id in pairs(data) do ids[id] = true; count = count + 1 end
  rawIds[entity.name], rawCounts[entity.name] = ids, count
  data = nil; collectgarbage('collect')
end
local ARRAY = {}
local function array(value) return setmetatable(value, ARRAY) end
local function quote(value)
  return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    return string.format('\\u%04x', string.byte(c))
  end) .. '"'
end
local function sortedKeys(value)
  local keys = {}; for key in pairs(value) do keys[#keys+1] = key end
  table.sort(keys, function(a,b)
    if type(a)==type(b) and type(a)=='number' then return a<b end
    return tostring(a)<tostring(b)
  end)
  return keys
end
local function json(value, seen)
  local kind = type(value)
  if value == nil then return 'null' end
  if kind == 'string' then return quote(value) end
  if kind == 'boolean' then return value and 'true' or 'false' end
  if kind == 'number' then
    assert(value == value and value ~= math.huge and value ~= -math.huge, 'nonfinite number')
    return string.format('%.17g', value)
  end
  assert(kind == 'table', 'unsupported JSON value: ' .. kind)
  seen = seen or {}; assert(not seen[value], 'cycle in export'); seen[value] = true
  local parts = {}
  if getmetatable(value) == ARRAY then
    for i=1,#value do parts[i] = json(value[i], seen) end
    seen[value] = nil; return '[' .. table.concat(parts, ',') .. ']'
  end
  local used = {}
  for _, key in ipairs(sortedKeys(value)) do
    assert(type(key)=='string' or type(key)=='number', 'unsupported table key')
    local name = tostring(key); assert(not used[name], 'key collision: '..name); used[name] = true
    parts[#parts+1] = quote(name) .. ':' .. json(value[key], seen)
  end
  seen[value] = nil; return '{' .. table.concat(parts, ',') .. '}'
end
local function decodeSupport(value)
  if type(value) == 'string' and value:match('^%s*return%s*{') then
    local chunk = assert(loadstring(value, 'QuestieDB support payload'))
    setfenv(chunk, {})
    return decodeSupport(chunk())
  end
  if type(value) ~= 'table' then return value end
  local result = {}; for key, child in pairs(value) do result[key] = decodeSupport(child) end
  return result
end
local function loadPersona(faction, classFile, classId)
  client.reset(); collectgarbage('collect')
  client.install({ expansion='Forever', faction=faction, classFile=classFile,
    classId=classId, locale='enUS', level=60, season=nil })
  local db, files = emulator.loadAddon('QuestieDB.toc', 'QuestieDB')
  assert(db.readMode == 'source' and db.flavor.name == 'Forever', 'wrong read mode/flavor')
  for _, name in ipairs(types) do
    local ids = db[name].GetAllIds(true)
    for id in pairs(rawIds[name]) do assert(ids[id], name .. ' lost raw id ' .. id) end
  end
  return db, files
end
local function row(db, name, id)
  local fields = {}; local meta = db.Meta[name]
  for index=1,meta.fieldCount do fields[meta.names[index]] = db[name].Get(id,index) end
  return fields
end
local db, selectedFiles = loadPersona('Alliance', 'WARRIOR', 1)
local out = assert(io.open(stagingPath, 'wb'))
local function write(...) assert(out:write(...)) end
local provider = {
  repository='https://github.com/Questie/QuestieDB', revision=revision,
  historicalQuestieRevision='454b9d072965ee8f1a881429260fcf1fac8d60f7',
  flavor='Forever', gameType='camelot', interface='16001', reader='Source Get',
  runtimeLocale='enUS', dynamicAxes=array({'faction','classFile'}),
  baseline={faction='Alliance',classFile='WARRIOR',classId=1},
  characterPolicy='All 18 faction/class combinations; current owned Forever callbacks read only faction and class. Race, level, realm, season and spell state are not correction axes in this adapter; new correction axes require an adapter update.',
  tableEncoding='objects with stringified Lua keys; nil omitted; empty table preserved',
  sourceFiles=array(selectedFiles), supportFiles=array(config.supportFiles(flavor)),
  contractVersion=db.contractVersion, rawCounts=rawCounts, raceMasks=db.Enum.raceMaskById,
}
write('{"schemaVersion":1,"provider":',json(provider),',"schema":{')
for i,name in ipairs(types) do
  if i>1 then write(',') end
  local m = db.Meta[name]
  write(quote(name),':',json({keys=m.keys,names=m.names,types=m.types,
    structures=m.structures,compilerTypes=m.compilerTypes,l10nFields=m.l10nFields,
    fieldCount=m.fieldCount}))
end
local support = db.Support.GetAll()
local decodedSupport = decodeSupport(support)
local baselineSupport = json(support)
local baselineDecodedSupport = json(decodedSupport)
write('},"support":',baselineSupport,',"decodedSupport":',baselineDecodedSupport,',"base":{')
local baseline, knownIds, counts = {}, {}, {}
for i,name in ipairs(types) do
  if i>1 then write(',') end
  write(quote(plural[name]),':{')
  baseline[name], knownIds[name] = {}, {}
  local ids = db[name].GetAllIds(); counts[name] = #ids
  for j,id in ipairs(ids) do
    if j>1 then write(',') end
    local encoded = json(row(db,name,id)); baseline[name][id] = encoded; knownIds[name][id] = true
    write(quote(tostring(id)),':',encoded)
  end
  write('}')
  io.stderr:write(name,': ',#ids,' entities\n')
end
local baselineObjectiveFirst = json(db.ObjectiveFirst or {})
write('},"objectiveFirst":',baselineObjectiveFirst,',"iconTypes":',json(db.Enum.iconTypes or {}),',"variants":[')
local variantCounts = {}; local personaNumber = 0
-- Baseline also receives an explicit empty overlay so selectors are enumerable.
for _,faction in ipairs({'Alliance','Horde'}) do
  for _,class in ipairs(classes) do
    personaNumber = personaNumber+1
    if personaNumber>1 then write(',') end
    if personaNumber>1 then db = nil; db = loadPersona(faction,class[1],class[2]) end
    local selector={faction=faction,classFile=class[1],classId=class[2]}
    local countsForPersona = {}
    write('{"selector":',json(selector))
    for _,name in ipairs(types) do
      write(',',quote(plural[name]),':{')
      local changed, present = 0, {}
      for _,id in ipairs(db[name].GetAllIds()) do
        present[id] = true; knownIds[name][id] = true
        local encoded = json(row(db,name,id))
        if encoded ~= baseline[name][id] then
          if changed>0 then write(',') end
          write(quote(tostring(id)),':',encoded); changed = changed+1
        end
      end
      write('}')
      local removed = array({})
      for _,id in ipairs(sortedKeys(baseline[name])) do
        if not present[id] then removed[#removed+1] = id end
      end
      write(',',quote(plural[name]..'Removed'),':',json(removed))
      countsForPersona[name]=changed
    end
    local objectiveFirstNow = json(db.ObjectiveFirst or {})
    if objectiveFirstNow ~= baselineObjectiveFirst then
      write(',"objectiveFirst":',objectiveFirstNow)
    end
    local supportNow = json(db.Support.GetAll())
    if supportNow ~= baselineSupport then
      write(',"support":',supportNow,',"decodedSupport":',json(decodeSupport(db.Support.GetAll())))
    end
    write('}')
    variantCounts[faction..'/'..class[1]]=countsForPersona
    io.stderr:write('persona ',personaNumber,'/18 ',faction,'/',class[1],' complete\n')
  end
end
write('],"localization":{"locales":',json(array(config.locales)),',"types":{')
local localizationStats = {}
for index,name in ipairs(types) do
  if index>1 then write(',') end
  write(quote(name),':{')
  local values, stats = l10n.extract(config.paths.l10n, flavor, name, knownIds[name])
  assert(#stats.missingFiles == 0, 'missing localization files')
  localizationStats[name]=stats
  for n,id in ipairs(sortedKeys(values)) do
    if n>1 then write(',') end
    local byLocale={}
    for fieldIndex,slots in pairs(values[id]) do
      for localeIndex,value in pairs(slots) do
        local locale=config.locales[localeIndex]
        byLocale[locale]=byLocale[locale] or {}
        byLocale[locale][l10n.types[name].fields[fieldIndex].name]=value
      end
    end
    write(quote(tostring(id)),':',json(byLocale))
  end
  write('}')
  values=nil; collectgarbage('collect')
  io.stderr:write('localization ',name,': ',stats.entries,' entries, ',stats.locales,' locales\n')
end
write('}},"counts":',json(counts),',"variantCounts":',json(variantCounts),
  ',"localizationStats":',json(localizationStats),'}\n')
assert(out:close())
-- Never expose a partial export. On Windows rename refuses replacement, so the
-- Python wrapper publishes via os.replace; direct Lua re-runs accept identical
-- bytes and otherwise preserve the existing target on failure.
local function sameFile(a, b)
  local left = io.open(a, 'rb'); if not left then return false end
  local right = assert(io.open(b, 'rb'))
  local same = true
  while true do
    local x, y = left:read(1048576), right:read(1048576)
    if x ~= y then same = false; break end
    if x == nil then break end
  end
  left:close(); right:close(); return same
end
if sameFile(outputPath, stagingPath) then
  assert(os.remove(stagingPath))
else
  assert(os.rename(stagingPath, outputPath),
    'Cannot atomically publish; preserve existing target and use the Python wrapper')
end
io.stderr:write('Export complete: ',outputPath,'\n')


