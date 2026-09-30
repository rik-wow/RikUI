-- Supported quest baselines and separately admitted navigation builds.
-- Byte-identical patches may share navigation; changed geometry requires a
-- fresh build. Quest compatibility retains the corpus's original provenance
-- and does not imply terrain compatibility or complete new-quest coverage.
--
-- 1.60.1.69977 against 1.60.1.69913 (verified 2026-09-22):
--   * 15,697 terrain sources in the world acquisition profile (root/obj0 ADTs,
--     WMOs, WMO groups, M2s), extracted with the pinned TACTTool from build
--     config 3bd89ce2721f7c75e7525dc83741076f: all SHA-256 identical
--     (tools/terrain/verify_build.py, D:/RikUI-local/verify-69977-world).
--   * DB2 tables Map, UiMap, UiMapAssignment, AreaTable, LiquidType, TaxiNodes,
--     TaxiPath, TaxiPathNode, TransportAnimation, AreaTrigger and QuestV2 from
--     wago.tools: byte-identical CSV exports.
local planner = RikUI.QuestPlanner
local builds = {}
planner.Builds = builds

-- 70009 retains every existing QuestV2 record; the refreshed membership index
-- includes its five additional IDs without inventing objective details.
-- Its changed geometry requires a separate rebuild.
-- Exact source pins and coverage: tools/terrain/ROADS.md.
local QUEST_DATA = {
    ["1.60.1.69977"] = "1.60.1.69913",
    ["1.60.1.70009"] = "1.60.1.69913",
    ["1.60.1.70124"] = "1.60.1.69913",
}

-- Reviewed 2026-09-29 against the current Forever head and installed client:
-- 70124's 14,291 extracted navigation assets and all ten geometry/travel DB2
-- exports are byte-identical to the reviewed 70009 inputs. QuestV2 retains
-- all 6,605 records unchanged. These are verified mappings, not build targets.
-- Full evidence and coverage limits: tools/terrain/ROADS.md.
local NAVIGATION_DATA = {
    ["1.60.1.70009"] = "1.60.1.70009",
    ["1.60.1.70124"] = "1.60.1.70009",
}

-- The build of the supported quest corpus, not the terrain geometry.
function builds.DataBuild(clientBuild)
    return QUEST_DATA[clientBuild] or clientBuild
end

-- The running client's own build, when it differs from the data build.
local clientBuild
function builds.Client() return clientBuild end
function builds.Observe(build) clientBuild = QUEST_DATA[build] and build or nil end

-- Keep the quest snapshot immutable and preserve product/locale admission.
-- Only separately verified navigation mappings can select a geometry build.
function builds.NavigationIdentity(identity)
    local navigationBuild = NAVIGATION_DATA[clientBuild]
    if not navigationBuild or not identity or identity.product ~= "forever"
        or identity.build ~= "1.60.1.69913" then return identity end
    return {product=identity.product, build=navigationBuild, locale=identity.locale}
end
