"""Compile travel links (flight paths, boats, zeppelins, the Deeprun Tram) from
client DB2 exports into stops and timed links for the road network.

Stops are places a player walks to: a flight master, a dock, a tram entrance.
Links join stops: a flight between two flight points, a transport ride between
two docks, the tram between Ironforge and Stormwind. Coordinates use the bake
frame (x = game Y, z = game X, y = height) so stops attach to network nodes.

Times are estimates. Client data has the paths but not the speeds, so flights
and transports use the constants below, and the wait for a transport is half
its modelled cycle. Faction and discovery decide at runtime whether a player
may use a link; nothing here claims a link is available.
"""
import argparse, collections, csv, hashlib, json, math, pathlib

FORMAT = 'rikui-travel-links-v1'
FLIGHT_SPEED = 32.0      # yd/s, estimate
FLIGHT_OVERHEAD = 8.0    # s to talk to the flight master, mount and dismount
TRANSPORT_SPEED = 30.0   # yd/s, estimate for boats and zeppelins
BOARD_SECONDS = 10.0     # s to walk up the gangplank and off again
TELEPORT_FLAG = 0x1      # TaxiPathNode flag: the transport changes map here
ZEPPELIN_HEIGHT = 20.0   # yd; zeppelin towers berth high, boats at sea level
NAME_REACH = 1500.0      # yd; a dock takes the name of the nearest flight point this close
ALLIANCE, HORDE = 0x1, 0x2
UNLISTED = ('Quest Path', 'zzOLD', 'Generic', 'Transport,', 'Programmer Isle', 'Naxxramas')
TRAM_TRIGGERS = {2173: 'Stormwind, Deeprun Tram', 2175: 'Ironforge, Deeprun Tram'}
TRAM_SECONDS = 72.0      # ride: half the 143 s car cycle (TransportAnimation 176080)
TRAM_WAIT = 24.0         # six cars on the loop; estimate
TRAM_STATION_WALK = 30.0  # s to walk the station on map 369, which is not baked


def read(path):
    raw = pathlib.Path(path).read_bytes()
    return list(csv.DictReader(raw.decode('utf-8-sig').splitlines())), hashlib.sha256(raw).hexdigest()


def bake(x, y, z):
    """Game (X, Y, Z) to bake frame (x = game Y, y = height, z = game X)."""
    return [round(y, 3), round(z, 3), round(x, 3)]


def faction(flags):
    return [side for side, bit in (('alliance', ALLIANCE), ('horde', HORDE)) if flags & bit]


def flight_stops(taxi_nodes):
    stops = {}
    for row in taxi_nodes:
        sides = faction(int(row['Flags']))
        if not sides or row['Name_lang'].startswith(UNLISTED):
            continue
        ident = int(row['ID'])
        stops[ident] = dict(id='flight:%d' % ident, kind='flight', name=row['Name_lang'], world=int(row['ContinentID']),
                            point=bake(float(row['Pos_0']), float(row['Pos_1']), float(row['Pos_2'])), factions=sides,
                            taxiNode=ident)
    return stops


def path_rows(path_nodes):
    paths = collections.defaultdict(list)
    for row in path_nodes:
        paths[int(row['PathID'])].append(row)
    for rows in paths.values():
        rows.sort(key=lambda r: int(r['NodeIndex']))
    return paths


def length(rows):
    """Flown or sailed distance, skipping jumps where the path changes map."""
    total = 0.0
    for a, b in zip(rows, rows[1:]):
        if a['ContinentID'] != b['ContinentID'] or int(b['Flags']) & TELEPORT_FLAG:
            continue
        total += math.dist([float(a['Loc_%d' % k]) for k in range(3)], [float(b['Loc_%d' % k]) for k in range(3)])
    return total


def flight_links(taxi_paths, paths, stops):
    links = []
    for row in taxi_paths:
        a, b, ident = int(row['FromTaxiNode']), int(row['ToTaxiNode']), int(row['ID'])
        rows = paths.get(ident)
        if a not in stops or b not in stops or not rows or stops[a]['world'] != stops[b]['world']:
            continue
        sides = [s for s in stops[a]['factions'] if s in stops[b]['factions']]
        if not sides:
            continue
        links.append(dict(id='flight:%d' % ident, mode='flight', **{'from': stops[a]['id'], 'to': stops[b]['id']},
                          seconds=round(length(rows) / FLIGHT_SPEED + FLIGHT_OVERHEAD, 1), wait=0.0,
                          flightFrom=stops[a]['id'], flightTo=stops[b]['id'], factions=sides))
    return links


def transport_paths(taxi_paths, paths, flight):
    """Paths with waiting stops that do not run between two listed flight points."""
    listed = {int(r['ID']): (int(r['FromTaxiNode']), int(r['ToTaxiNode'])) for r in taxi_paths}
    found = []
    for ident, rows in sorted(paths.items()):
        ends = listed.get(ident, (0, 0))
        if ends[0] in flight and ends[1] in flight:
            continue
        stops = [i for i, r in enumerate(rows) if int(r['Delay']) > 0]
        if len(stops) >= 2:
            found.append((ident, rows, stops))
    return found


def place_name(flight_name):
    """'Booty Bay, Stranglethorn' -> 'Booty Bay'."""
    return flight_name.split(',')[0].strip()


def name_docks(docks, flights):
    for dock in docks:
        near = [(math.dist(dock['point'][::2], f['point'][::2]), f['name']) for f in flights if f['world'] == dock['world']]
        near = [row for row in near if row[0] <= NAME_REACH]
        vehicle = 'zeppelin' if dock['point'][1] > ZEPPELIN_HEIGHT else 'boat'
        place = 'zeppelin tower' if vehicle == 'zeppelin' else 'dock'
        dock['name'] = '%s %s' % (place_name(min(near)[1]), place) if near else place.capitalize()
        dock['vehicle'] = vehicle


def transport_legs(ident, rows, stops):
    """Stops and the ride between consecutive stops around the loop."""
    cycle = length(rows) / TRANSPORT_SPEED + sum(int(rows[i]['Delay']) for i in stops)
    docks = [dict(id='dock:%d:%d' % (ident, n), kind='dock', name='Transport %d stop %d' % (ident, n),
                  world=int(rows[i]['ContinentID']),
                  point=bake(*(float(rows[i]['Loc_%d' % k]) for k in range(3))), transport='transport:%d' % ident)
             for n, i in enumerate(stops)]
    links = []
    for n, i in enumerate(stops):
        j = stops[(n + 1) % len(stops)]
        leg = rows[i:j + 1] if j > i else rows[i:] + rows[:j + 1]
        ride = length(leg) / TRANSPORT_SPEED
        for a, b in ((n, (n + 1) % len(stops)),):
            vehicle = 'zeppelin' if docks[a]['point'][1] > ZEPPELIN_HEIGHT else 'boat'
            links.append(dict(id='ride:%d:%d' % (ident, n), mode='transport', **{'from': docks[a]['id'], 'to': docks[b]['id']},
                              seconds=round(ride + BOARD_SECONDS, 1), wait=round(cycle / 2, 1),
                              transport='transport:%d' % ident, vehicle=vehicle, period=round(cycle, 1)))
    return docks, links


def tram(triggers):
    by_id = {int(r['ID']): r for r in triggers}
    stops = []
    for ident, name in sorted(TRAM_TRIGGERS.items()):
        row = by_id.get(ident)
        if row is None or row['ContinentID'] != '0':
            return [], []
        stops.append(dict(id='tram:%d' % ident, kind='tram', name=name, world=0,
                          point=bake(float(row['Pos_0']), float(row['Pos_1']), float(row['Pos_2']))))
    seconds = round(TRAM_SECONDS + TRAM_STATION_WALK, 1)
    links = [dict(id='tram:%s' % direction, mode='transport', **{'from': a['id'], 'to': b['id']}, seconds=seconds,
                  wait=TRAM_WAIT, transport='transport:deeprun-tram', vehicle='tram', period=round(TRAM_WAIT * 2, 1))
             for direction, a, b in (('south', stops[1], stops[0]), ('north', stops[0], stops[1]))]
    return stops, links


LIFT_MIN_TRAVEL = 20.0   # yd; shorter vertical animations are doors and small platforms


def lifts(animation):
    """Vertical-only transports (elevators): {transport id: travel yards}."""
    keys = collections.defaultdict(list)
    for r in animation:
        keys[int(r['TransportID'])].append((float(r['Pos_0']), float(r['Pos_1']), float(r['Pos_2'])))
    out = {}
    for ident, rows in keys.items():
        zs = [k[2] for k in rows]
        if max(math.hypot(k[0], k[1]) for k in rows) < 1.0 and max(zs) - min(zs) >= LIFT_MIN_TRAVEL:
            out[ident] = round(max(zs) - min(zs), 1)
    return out


def compile_links(taxi_nodes, taxi_paths, path_nodes, triggers):
    flight = flight_stops(taxi_nodes)
    paths = path_rows(path_nodes)
    stops = list(flight.values())
    links = flight_links(taxi_paths, paths, flight)
    for ident, rows, where in transport_paths(taxi_paths, paths, flight):
        docks, rides = transport_legs(ident, rows, where)
        name_docks(docks, flight.values())
        stops.extend(docks); links.extend(rides)
    tram_stops, tram_links = tram(triggers)
    stops.extend(tram_stops); links.extend(tram_links)
    stops.sort(key=lambda s: s['id']); links.sort(key=lambda l: l['id'])
    return stops, links


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tables', required=True, help='directory with <Table>-<build>.csv exports')
    p.add_argument('--build', default='1.60.1.69913')
    p.add_argument('--output', required=True)
    args = p.parse_args()
    tables, sources = {}, {}
    for name in ('TaxiNodes', 'TaxiPath', 'TaxiPathNode', 'AreaTrigger', 'TransportAnimation'):
        path = pathlib.Path(args.tables) / ('%s-%s.csv' % (name, args.build))
        tables[name], sources[path.name] = read(path)
    stops, links = compile_links(tables['TaxiNodes'], tables['TaxiPath'], tables['TaxiPathNode'], tables['AreaTrigger'])
    lift_travel = lifts(tables['TransportAnimation'])
    doc = dict(format=FORMAT, build=args.build, sources=sources, stops=stops, links=links,
               lifts=[dict(transport=t, travel=v) for t, v in sorted(lift_travel.items())],
               estimates=dict(flightSpeed=FLIGHT_SPEED, flightOverhead=FLIGHT_OVERHEAD, transportSpeed=TRANSPORT_SPEED,
                              boardSeconds=BOARD_SECONDS, tramSeconds=TRAM_SECONDS, tramWait=TRAM_WAIT),
               nativeVerified=False)
    out = pathlib.Path(args.output)
    out.write_text(json.dumps(doc, indent=1, sort_keys=True) + '\n')
    kinds = collections.Counter(s['kind'] for s in stops)
    modes = collections.Counter(l['mode'] for l in links)
    print(json.dumps(dict(output=str(out), stops=dict(kinds), links=dict(modes))))


if __name__ == '__main__':
    main()
