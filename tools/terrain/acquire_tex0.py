"""Acquire exact-build tex0 ADTs (terrain texture layers) for road classification.

Client input is read-only. Only the TACTTool pinned in acquisition-profile.json
runs, into a new external directory. Every file gets a SHA-256 receipt.
Texture layers never add walkable geometry; they only bias route costs.
"""
import argparse, csv, json, pathlib, re, subprocess
import acquire as a
import client_build

MAX_TILES = 4096
MAX_TILE_BYTES = 8 * 1024 * 1024


def tiles(csv_path, worlds):
    rows = []
    with open(csv_path, newline='', encoding='utf-8') as handle:
        for row in csv.DictReader(handle):
            world = int(row['worldMapID'])
            if worlds and world not in worlds:
                continue
            ident = int(row['tex0ADT'])
            if not 0 < ident <= 2147483647:
                a.fail('invalid-tex0-id')
            rows.append(dict(worldMapID=world, tile=[int(row['x']), int(row['y'])], fileDataID=ident,
                             path='tex0/w%d_%d_%d_tex0.adt' % (world, int(row['x']), int(row['y']))))
    if not 0 < len(rows) <= MAX_TILES:
        a.fail('tex0-tile-count')
    if len({r['fileDataID'] for r in rows}) != len(rows):
        a.fail('duplicate-tex0-id')
    return rows


def extract(arguments, output, rows):
    folder = output / 'tex0'
    folder.mkdir()
    listing = output / 'tex0-dependencies.list'
    listing.write_text(''.join('%d;%s\n' % (r['fileDataID'], pathlib.PurePosixPath(r['path']).name) for r in rows), encoding='utf-8')
    with (output / 'tex0-extract.log').open('xb') as log:
        result = subprocess.run(arguments + ['-m', 'list', '-i', str(listing), '-o', str(folder)],
                                cwd=output, stdout=log, stderr=subprocess.STDOUT, timeout=3600, check=False)
    if result.returncode:
        a.fail('TACTTool-failed:tex0')
    logs = (output / 'tex0-extract.log').read_text(encoding='utf-8', errors='replace')
    for row in rows:
        name = pathlib.PurePosixPath(row['path']).name
        keys = re.findall(r'Extracting ([a-f0-9]{32}) to ' + re.escape(name) + r'(?:\r?\n|$)', logs)
        path = folder / name
        if len(keys) != 1 or not path.is_file():
            a.fail('missing-tex0:' + name)
        data = path.read_bytes()
        if not 0 < len(data) <= MAX_TILE_BYTES or data[:4] != b'REVM':
            a.fail('tex0-framing:' + name)
        row.update(bytes=len(data), sha256=a.digest(data), encodingKey=keys[0])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tile-csv', required=True)
    p.add_argument('--world', type=int, action='append', default=[])
    p.add_argument('--game-root', required=True)
    p.add_argument('--tact-tool', required=True)
    p.add_argument('--output', required=True)
    args = p.parse_args()
    profile = a.load_profile()
    tool, game = a.checked_path(args.tact_tool), a.checked_path(args.game_root)
    pin = profile['tool']['binary']
    if tool.stat().st_size != pin['bytes'] or a.digest(tool.read_bytes()) != pin['sha256']:
        a.fail('pinned-TACTTool-hash')
    if not (game / 'Data').is_dir():
        a.fail('game-root-must-contain-Data')
    output = a.empty_output(args.output, (game, tool.parent, pathlib.Path(__file__).parent))
    rows = tiles(args.tile_csv, set(args.world))
    arguments = [str(tool), '-d', str(game), '-p', profile['product'], '-b', client_build.IDENTITY['buildConfig'],
                 '-c', client_build.IDENTITY['cdnConfig'], '-l', profile['locale']]
    extract(arguments, output, rows)
    manifest = dict(format='rikui-tex0-acquisition-v1', product=profile['product'], build=client_build.BUILD,
                    locale=profile['locale'], buildConfig=client_build.IDENTITY['buildConfig'], cdnConfig=client_build.IDENTITY['cdnConfig'],
                    tool=pin, tileCSVSHA256=a.digest(pathlib.Path(args.tile_csv).read_bytes()),
                    parserSHA256=a.digest(pathlib.Path(__file__).read_bytes()), files=rows,
                    gameFilesModified=False, nativeVerified=False)
    with (output / 'tex0-manifest.json').open('x', encoding='utf-8', newline='\n') as handle:
        json.dump(manifest, handle, indent=1)
    print(json.dumps(dict(output=str(output), files=len(rows), bytes=sum(r['bytes'] for r in rows),
                          manifestSHA256=a.digest((output / 'tex0-manifest.json').read_bytes()))))


if __name__ == '__main__':
    main()
