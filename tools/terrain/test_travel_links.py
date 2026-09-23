"""Travel links: flight faction filtering, transport docks and rides, the tram."""
import unittest
import travel_links as tl


def node(ident, name, world, x, y, flags):
    return dict(ID=str(ident), Name_lang=name, ContinentID=str(world), Pos_0=str(x), Pos_1=str(y), Pos_2='10', Flags=str(flags))


def pnode(path, index, world, x, y, delay=0, flags=0):
    return dict(PathID=str(path), NodeIndex=str(index), ContinentID=str(world), Loc_0=str(x), Loc_1=str(y), Loc_2='0',
                Delay=str(delay), Flags=str(flags))


NODES = [node(1, 'Ironforge, Dun Morogh', 0, 0, 0, 1025), node(2, 'Stormwind, Elwynn', 0, 0, 320, 1025),
         node(3, 'Undercity, Tirisfal', 0, 320, 0, 1026), node(4, 'Transport, Menethil Ships', 0, 9, 9, 1024),
         node(5, 'Quest Path 1: test', 0, 1, 1, 1027)]
PATHS = [dict(ID='10', FromTaxiNode='1', ToTaxiNode='2', Cost='1'), dict(ID='11', FromTaxiNode='1', ToTaxiNode='3', Cost='1'),
         dict(ID='20', FromTaxiNode='4', ToTaxiNode='0', Cost='0')]
PATH_NODES = [pnode(10, 0, 0, 0, 0), pnode(10, 1, 0, 0, 320),
              pnode(11, 0, 0, 0, 0), pnode(11, 1, 0, 320, 0),
              pnode(20, 0, 0, 0, 0, delay=60), pnode(20, 1, 0, 0, 300), pnode(20, 2, 1, 5000, 5000, flags=1),
              pnode(20, 3, 1, 5000, 5300, delay=60), pnode(20, 4, 1, 5000, 5600)]
TRIGGERS = [dict(ID='2173', ContinentID='0', Pos_0='-8346', Pos_1='514', Pos_2='96'),
            dict(ID='2175', ContinentID='0', Pos_0='-4840', Pos_1='-1330', Pos_2='508')]


class Tests(unittest.TestCase):
    def setUp(self):
        self.stops, self.links = tl.compile_links(NODES, PATHS, PATH_NODES, TRIGGERS)
        self.by_id = {s['id']: s for s in self.stops}

    def test_only_player_flight_points_are_stops(self):
        flights = sorted(s['id'] for s in self.stops if s['kind'] == 'flight')
        self.assertEqual(flights, ['flight:1', 'flight:2', 'flight:3'])
        self.assertEqual(self.by_id['flight:3']['factions'], ['horde'])

    def test_flight_needs_a_shared_faction(self):
        ids = [l['id'] for l in self.links if l['mode'] == 'flight']
        self.assertEqual(ids, ['flight:10'])  # Ironforge to Undercity has no shared faction
        flight = next(l for l in self.links if l['id'] == 'flight:10')
        self.assertAlmostEqual(flight['seconds'], round(320 / tl.FLIGHT_SPEED + tl.FLIGHT_OVERHEAD, 1))

    def test_points_use_the_bake_frame(self):
        self.assertEqual(self.by_id['flight:2']['point'], [320.0, 10.0, 0.0])  # x = game Y, z = game X

    def test_transport_stops_are_waiting_nodes_and_skip_the_map_jump(self):
        docks = [s for s in self.stops if s['kind'] == 'dock']
        self.assertEqual([(d['id'], d['world']) for d in docks], [('dock:20:0', 0), ('dock:20:1', 1)])
        out = next(l for l in self.links if l['id'] == 'ride:20:0')
        # 300 yd on each map; the jump between maps adds nothing
        self.assertAlmostEqual(out['seconds'], round(600 / tl.TRANSPORT_SPEED + tl.BOARD_SECONDS, 1))
        cycle = (300 + 300 + 300) / tl.TRANSPORT_SPEED + 120  # the map jump adds no distance
        self.assertAlmostEqual(out['wait'], round(cycle / 2, 1))

    def test_docks_are_named_after_the_nearest_flight_point(self):
        dock = self.by_id['dock:20:0']
        self.assertEqual((dock['name'], dock['vehicle']), ('Ironforge dock', 'boat'))
        self.assertEqual(self.by_id['dock:20:1']['name'], 'Dock')  # no flight point on that map

    def test_tram_links_both_entrances(self):
        tram = sorted((l['from'], l['to']) for l in self.links if l['id'].startswith('tram:'))
        self.assertEqual(tram, [('tram:2173', 'tram:2175'), ('tram:2175', 'tram:2173')])

    def test_missing_tram_trigger_drops_the_tram(self):
        stops, links = tl.compile_links(NODES, PATHS, PATH_NODES, TRIGGERS[:1])
        self.assertFalse([s for s in stops if s['kind'] == 'tram'])
        self.assertFalse([l for l in links if l['id'].startswith('tram:')])


if __name__ == '__main__':
    unittest.main()
