"""Read lift spawns, transport speeds and teleport triggers from AzerothCore's
world database SQL (github.com/azerothcore/azerothcore-wotlk, data/sql/base/db_world).

Client DB2 has each lift's animation but not where it stands, and the paths of
boats and zeppelins but not their speeds. AzerothCore's server tables carry
both. Its world is Wrath of the Lich King; the classic lifts, docks and portals
it covers are unchanged there, which is why they are used. Anything Forever
added is not in it.
"""
import argparse, hashlib, json, pathlib, re

def tuples(text):
    """Yield value lists from 'VALUES (..),(..);' text, honouring quoted strings."""
    row, token, quoted, depth, i = [], '', False, 0, 0
    while i < len(text):
        c = text[i]
        if quoted:
            if c == '\\':
                token += text[i + 1]; i += 2; continue
            if c == "'":
                quoted = False
            else:
                token += c
        elif c == "'":
            quoted = True
        elif c == '(':
            depth += 1
            if depth == 1:
                row, token = [], ''
            else:
                token += c
        elif c == ')':
            depth -= 1
            if depth == 0:
                row.append(token.strip())
                yield [None if v == 'NULL' else v for v in row]
            else:
                token += c
        elif c == ',' and depth == 1:
            row.append(token.strip()); token = ''
        elif depth >= 1:
            token += c
        i += 1


def table(path):
    raw = pathlib.Path(path).read_bytes()
    text = raw.decode('utf-8', errors='replace')
    create = text[text.index('CREATE TABLE'):]
    create = create[:create.index(') ENGINE')]
    columns = re.findall(r'^\s+`(\w+)`', create, re.M)
    rows = []
    for m in re.finditer(r'INSERT INTO `\w+` VALUES\s*(.*?);\s*$', text, re.M | re.S):
        for v in tuples(m.group(1)):
            if len(v) == len(columns):
                rows.append(dict(zip(columns, v)))
    return rows, hashlib.sha256(raw).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--db', required=True, help='directory with gameobject.sql, gameobject_template.sql, areatrigger_teleport.sql')
    p.add_argument('--lifts', required=True, nargs='+', type=int, help='transport IDs (TransportAnimation) to locate')
    p.add_argument('--output', required=True)
    args = p.parse_args()
    spawns, spawn_sha = table(pathlib.Path(args.db) / 'gameobject.sql')
    templates, template_sha = table(pathlib.Path(args.db) / 'gameobject_template.sql')
    teleports, teleport_sha = table(pathlib.Path(args.db) / 'areatrigger_teleport.sql')
    wanted = set(args.lifts)
    by_template = {int(t['entry']): t for t in templates}
    lifts = [dict(entry=int(s['id']), map=int(s['map']), x=float(s['position_x']), y=float(s['position_y']),
                  z=float(s['position_z']), name=by_template.get(int(s['id']), {}).get('name'))
             for s in spawns if int(s['id']) in wanted]
    transports = [dict(entry=int(t['entry']), name=t['name'], path=int(t['Data0']), speed=float(t['Data1']))
                  for t in templates if t['type'] == '15']
    teleport_rows = [dict(trigger=int(t['ID']), name=t['Name'], map=int(t['target_map']), x=float(t['target_position_x']),
                          y=float(t['target_position_y']), z=float(t['target_position_z'])) for t in teleports]
    doc = dict(format='rikui-azerothcore-travel-v1',
               source='github.com/azerothcore/azerothcore-wotlk master, data/sql/base/db_world',
               sha256=dict(gameobject=spawn_sha, gameobject_template=template_sha, areatrigger_teleport=teleport_sha),
               lifts=sorted(lifts, key=lambda r: (r['entry'], r['x'])), transports=transports, teleports=teleport_rows)
    pathlib.Path(args.output).write_text(json.dumps(doc, indent=1, sort_keys=True) + '\n')
    print(json.dumps(dict(lifts=len(lifts), transports=len(transports), teleports=len(teleport_rows))))


if __name__ == '__main__':
    main()
