"""Find elevator shafts in baked polygons.

Elevator spawn positions are server data, but TransportAnimation gives each
lift's exact vertical travel. A shaft shows up in the bake as walkable landings
stacked directly above each other, that travel apart. This lists such stacks
as candidates for review; it does not decide which ones are lifts.

Input is the road compiler's compact cache (road-network-cache/input-*/wN_*.pkl).
"""
import argparse, collections, csv, json, math, pathlib, pickle

STACK_XZ = 6.0        # yd; landings above each other within this horizontal distance
TRAVEL_SLACK = 2.5    # yd; landing height difference may differ from the travel by this much
MIN_TRAVEL = 20.0     # yd; shorter lifts (doors, small platforms) are not worth a link
CLUSTER = 40.0        # yd; candidate pairs this close belong to the same shaft


def travels(animation_csv):
    """{transport id: vertical travel} for lifts that only move vertically."""
    rows = collections.defaultdict(list)
    for r in csv.DictReader(pathlib.Path(animation_csv).read_text(encoding='utf-8-sig').splitlines()):
        rows[int(r['TransportID'])].append((float(r['Pos_0']), float(r['Pos_1']), float(r['Pos_2']), int(r['TimeIndex'])))
    out = {}
    for ident, keys in rows.items():
        zs = [k[2] for k in keys]
        sideways = max(math.hypot(k[0], k[1]) for k in keys)
        travel = max(zs) - min(zs)
        if sideways < 1.0 and travel >= MIN_TRAVEL:
            out[ident] = dict(travel=round(travel, 1), period=max(k[3] for k in keys) / 1000.0)
    return out


def centers(cache_dir, world):
    pts = []
    for path in sorted(pathlib.Path(cache_dir).glob('w%d_*.pkl' % world)):
        cached = pickle.loads(path.read_bytes())
        pts.extend((r[1][0], r[1][1], r[1][2]) for r in cached['rows'])
    return pts


def stacks(points, travel):
    grid = collections.defaultdict(list)
    for p in points:
        grid[(math.floor(p[0] / STACK_XZ), math.floor(p[2] / STACK_XZ))].append(p)
    pairs = []
    for (gx, gz), cell in grid.items():
        near = [q for dx in (-1, 0, 1) for dz in (-1, 0, 1) for q in grid.get((gx + dx, gz + dz), ())]
        for low in cell:
            for high in near:
                dy = high[1] - low[1]
                if abs(dy - travel) <= TRAVEL_SLACK and math.hypot(high[0] - low[0], high[2] - low[2]) <= STACK_XZ:
                    pairs.append((low, high))
    return pairs


def cluster(pairs):
    shafts = []
    for low, high in pairs:
        for shaft in shafts:
            if math.hypot(shaft['x'] - low[0], shaft['z'] - low[2]) <= CLUSTER:
                shaft['pairs'] += 1
                break
        else:
            shafts.append(dict(x=low[0], z=low[2], low=low[1], high=high[1], pairs=1))
    return sorted(shafts, key=lambda s: -s['pairs'])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--animation', required=True)
    p.add_argument('--cache', required=True)
    p.add_argument('--world', type=int, required=True)
    args = p.parse_args()
    points = centers(args.cache, args.world)
    by_travel = collections.defaultdict(list)
    for ident, row in travels(args.animation).items():
        by_travel[row['travel']].append(ident)
    for travel, idents in sorted(by_travel.items()):
        shafts = cluster(stacks(points, travel))[:8]
        print(json.dumps(dict(travel=travel, transports=sorted(idents),
                              shafts=[dict(gameX=round(s['z'], 1), gameY=round(s['x'], 1), low=round(s['low'], 1),
                                           high=round(s['high'], 1), pairs=s['pairs']) for s in shafts])))


if __name__ == '__main__':
    main()
