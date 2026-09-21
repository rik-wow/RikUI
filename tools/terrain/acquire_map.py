"""Acquire exact-build Dun Morogh source tiles; acquisition is not installed coverage."""
import argparse
import copy
import json
import acquire as a
import acquire_west as west
import compile_quest_terrain as compiler
import terrain_probe as terrain

PROFILE_SHA256 = "fc51a45b8de42ca240b59a8fc3faadc5329e881ec4bc93e15e83f3d514a84958"
MAP_ID = 1426
BOUNDS = [-3122.9165039062, -7160.4165039062, 1802.0832519531, -3877.0832519531]
TILES = tuple((x, y) for x in range(28, 38) for y in range(39, 46))


class MapAcquisition(west.Acquisition):
    max_files, max_bytes = 8192, 256 * 1024 * 1024


def relevant(placement):
    if placement["kind"] != "wmo":
        return True
    bounds = placement["bounds"]
    low_x, high_x = 32*terrain.TILE-bounds[3], 32*terrain.TILE-bounds[0]
    low_z, high_z = 32*terrain.TILE-bounds[5], 32*terrain.TILE-bounds[2]
    return (low_x <= BOUNDS[2]+2 and high_x >= BOUNDS[0]-2
            and low_z <= BOUNDS[3]+2 and high_z >= BOUNDS[1]-2)


def receipts(job, mapping, counts):
    profile = copy.deepcopy(job.profile)
    profile["files"] = sorted(job.files.values(), key=lambda row: (row["layer"], row["fileDataID"]))
    profile["observedTiles"] = mapping
    profile["mappingEvidence"]["WDTTiles"] = mapping
    profile["navigationRegion"] = dict(regionID="dun-morogh-map-69913", uiMapID=MAP_ID,
        tiles=[list(tile) for tile in TILES], navXZBounds=BOUNDS, projectionSource=compiler.PROJECTION_SOURCE)
    profile["limitations"] = [
        "All 70 source tiles intersecting the exact-build map rectangle.",
        "Acquisition alone does not establish collision decoding or native traversal.",
        "Unsupported model layouts remain explicit; this command installs no terrain."]
    profile["acquisitionBounds"] = dict(maxFiles=job.max_files, maxBytes=job.max_bytes,
        allPlacements=counts[0], selectedPlacements=counts[1])
    if a.digest(a.canonical(profile)) != PROFILE_SHA256:
        a.fail("map-acquisition-profile-pin")
    path = job.output/"acquisition-profile-map.json"
    with path.open("x", encoding="utf-8") as handle:
        json.dump(profile, handle, indent=2)
        handle.write("\n")
    a.PROFILE, a.PROFILE_HASH = path, a.digest(a.canonical(profile))
    a.receipts(profile, job.output, "pinned-TACTTool-read-only-CASC-and-verified-reuse", job.source, job.tool)
    print(json.dumps(dict(output=str(job.output), files=len(job.files),
        bytes=sum(row["bytes"] for row in job.files.values()), profileSHA256=a.PROFILE_HASH)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("existing", "game-root", "tact-tool", "output"):
        parser.add_argument("--"+name, required=True)
    job = MapAcquisition(parser.parse_args())
    mapping = west.terrain_sources(job, TILES)
    counts = west.collision_sources(job, mapping, relevant)
    receipts(job, mapping, counts)


if __name__ == "__main__":
    main()
