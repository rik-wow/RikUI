-- Client builds verified to ship the same data as the build RikUI's navigation
-- and quest data were compiled from. A patch that leaves every source byte
-- unchanged does not invalidate that data; this table says so explicitly, with
-- the evidence, instead of relabelling the data itself.
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

local SAME_DATA = { ["1.60.1.69977"] = "1.60.1.69913" }

-- The build whose compiled data applies to this client build.
function builds.DataBuild(clientBuild)
    return SAME_DATA[clientBuild] or clientBuild
end

-- The running client's own build, when it differs from the data build.
local clientBuild
function builds.Client() return clientBuild end
function builds.Observe(build) clientBuild = SAME_DATA[build] and build or nil end
