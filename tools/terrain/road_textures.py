"""Road coverage rasters from exact-build tex0 texture layers.

Decodes MDID/MCLY/MCAL, blends layers the way the client does, and sums the
visible weight of textures classified as road. Output is one 256x256 uint8
raster per tile (about 2.08 yards per cell, 0 = no road, 255 = all road) in
navigation coordinates (X = game world Y, Z = game world X). Rasters only bias
route costs; they never add or remove walkable geometry.
"""
import argparse, hashlib, json, pathlib, re, struct
import numpy as np
import terrain_probe as t

TILE = t.TILE
CHUNK = t.CHUNK
ALPHA = 64
CELLS = 256  # per tile edge; 4x4 alpha texels per cell
FLAG_USE_ALPHA, FLAG_COMPRESSED = 0x100, 0x200
ROAD_NAME = re.compile(r'road|cobble|street|pave', re.I)
# Reviewed by rendering each candidate over Dun Morogh; see audit output.
ROAD_EXTRA = frozenset({
    # Dun Morogh's main road (Kharanos crossroads, Ironforge approach, Loch Modan pass).
    'tileset/ironforge/ironforgerock09browncracks_s.blp',
})
ROAD_EXCLUDE = frozenset({'tileset/duskwallow marsh/duskwallowbrickfloor_s.blp'})


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fail(reason):
    raise ValueError(reason)


def load_listfile(path, ids):
    names = {}
    with open(path, encoding='utf-8', errors='replace') as handle:
        for line in handle:
            ident, _, name = line.partition(';')
            if ident.isdigit() and int(ident) in ids:
                names[int(ident)] = name.strip()
    return names


def is_road(name):
    if not name or name in ROAD_EXCLUDE:
        return False
    return name in ROAD_EXTRA or bool(ROAD_NAME.search(name.rsplit('/', 1)[-1]))


def decompress(data, start):
    out = bytearray()
    at = start
    while len(out) < ALPHA * ALPHA:
        if at >= len(data):
            fail('MCAL-truncated')
        head = data[at]; at += 1
        count = head & 0x7f
        if head & 0x80:
            out.extend(data[at:at + 1] * count); at += 1
        else:
            out.extend(data[at:at + count]); at += count
    return np.frombuffer(bytes(out[:ALPHA * ALPHA]), dtype=np.uint8).reshape(ALPHA, ALPHA)


def alpha(mcal, layer, big, size=None):
    offset = layer['offset']
    if layer['flags'] & FLAG_COMPRESSED:
        return decompress(mcal, offset)
    # Uncompressed maps are 4096 (8-bit) or 2048 (4-bit) bytes. The WDT flag
    # differs per map, so the span to the next layer decides when it is known.
    if size is not None:
        if size >= 4096:
            big = True
        elif size >= 2048:
            big = False
    if big:
        raw = mcal[offset:offset + 4096]
        if len(raw) != 4096:
            fail('MCAL-big-size')
        return np.frombuffer(raw, dtype=np.uint8).reshape(ALPHA, ALPHA)
    raw = np.frombuffer(mcal[offset:offset + 2048], dtype=np.uint8)
    if len(raw) != 2048:
        fail('MCAL-small-size')
    values = np.empty(4096, dtype=np.uint8)
    values[0::2] = (raw & 0x0f) * 17
    values[1::2] = (raw >> 4) * 17
    return values.reshape(ALPHA, ALPHA)


def chunks(data):
    """Top-level MDID list and 256 MCNK (layers, MCAL bytes) records."""
    textures, mcnk = None, []
    for name, a, b in t.chunks(data):
        if name == 'MDID':
            textures = list(struct.unpack_from('<%dI' % ((b - a) // 4), data, a))
        elif name == 'MCNK':
            layers, mcal = [], b''
            body = data[a:b]
            for sub, sa, sb in t.chunks(body):
                if sub == 'MCLY':
                    for i in range(sa, sb, 16):
                        tex, flags, offset, _ = struct.unpack_from('<IIIi', body, i)
                        layers.append(dict(texture=tex, flags=flags, offset=offset))
                elif sub == 'MCAL':
                    mcal = body[sa:sb]
            mcnk.append((layers, mcal))
    if textures is None or len(mcnk) != 256:
        fail('tex0-layout')
    return textures, mcnk


def weights(layers, mcal, big):
    """Visible weight per layer after the client's sequential blending."""
    result = [np.ones((ALPHA, ALPHA), dtype=np.float32)]
    starts = sorted({l['offset'] for l in layers[1:] if l['flags'] & FLAG_USE_ALPHA} | {len(mcal)})
    for layer in layers[1:]:
        if layer['flags'] & FLAG_USE_ALPHA:
            end = next(s for s in starts if s > layer['offset']) if layer['offset'] < len(mcal) else layer['offset']
            a = alpha(mcal, layer, big, end - layer['offset']).astype(np.float32) / 255.0
        else:
            a = np.zeros((ALPHA, ALPHA), dtype=np.float32)
        for previous in result:
            previous *= (1.0 - a)
        result.append(a)
    return result


def tile_raster(data, road_ids, big=True):
    """256x256 uint8 road coverage; row = chunk-row order (world X decreasing)."""
    textures, mcnk = chunks(data)
    full = np.zeros((16 * ALPHA, 16 * ALPHA), dtype=np.float32)
    for index, (layers, mcal) in enumerate(mcnk):
        if not layers:
            continue
        iy, ix = divmod(index, 16)
        road = np.zeros((ALPHA, ALPHA), dtype=np.float32)
        for layer, weight in zip(layers, weights(layers, mcal, big)):
            if not 0 <= layer['texture'] < len(textures):
                fail('MCLY-texture-range')
            if textures[layer['texture']] in road_ids:
                road += weight
        full[iy * ALPHA:(iy + 1) * ALPHA, ix * ALPHA:(ix + 1) * ALPHA] = road
    cells = full.reshape(CELLS, 4, CELLS, 4).mean(axis=(1, 3))
    return np.clip(np.rint(cells * 255), 0, 255).astype(np.uint8)


def tile_texture_ids(data):
    return chunks(data)[0]


def cell_center(tile_x, tile_y, row, col):
    """Navigation (x, z) of raster cell (row, col) in tile (tile_x, tile_y)."""
    step = TILE / CELLS
    world_x = (32 - tile_y) * TILE - (row + .5) * step
    world_y = (32 - tile_x) * TILE - (col + .5) * step
    return world_y, world_x


class RoadLookup:
    """Road fraction at navigation points, backed by per-tile rasters on disk."""
    def __init__(self, directory, world):
        self.directory, self.world, self.cache = pathlib.Path(directory), world, {}

    def raster(self, tx, ty):
        key = (tx, ty)
        if key not in self.cache:
            path = self.directory / ('w%d_%d_%d.npy' % (self.world, tx, ty))
            self.cache[key] = np.load(path) if path.is_file() else None
        return self.cache[key]

    def fraction(self, x, z):
        # x = game world Y, z = game world X.
        tx, ty = int(32 - x / TILE), int(32 - z / TILE)
        values = self.raster(tx, ty)
        if values is None:
            return 0.0
        col = int(((32 - tx) * TILE - x) / (TILE / CELLS))
        row = int(((32 - ty) * TILE - z) / (TILE / CELLS))
        if not (0 <= row < CELLS and 0 <= col < CELLS):
            return 0.0
        return float(values[row, col]) / 255.0


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tex0-directory', required=True)
    p.add_argument('--manifest-sha256', required=True)
    p.add_argument('--listfile', required=True)
    p.add_argument('--listfile-sha256', required=True)
    p.add_argument('--output', required=True)
    args = p.parse_args()
    root = pathlib.Path(args.tex0_directory)
    manifest_bytes = (root / 'tex0-manifest.json').read_bytes()
    if sha(manifest_bytes) != args.manifest_sha256:
        fail('tex0-manifest-hash')
    if sha(pathlib.Path(args.listfile).read_bytes()) != args.listfile_sha256:
        fail('listfile-hash')
    manifest = json.loads(manifest_bytes)
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=False)
    usage, ids = {}, set()
    for row in manifest['files']:
        data = (root / row['path']).read_bytes()
        if sha(data) != row['sha256']:
            fail('tex0-hash:' + row['path'])
        for ident in tile_texture_ids(data):
            ids.add(ident); usage[ident] = usage.get(ident, 0) + 1
    names = load_listfile(args.listfile, ids)
    road_ids = {i for i in ids if is_road(names.get(i))}
    covered = 0
    raster_files=[]
    for row in manifest['files']:
        data=(root / row['path']).read_bytes()
        if sha(data)!=row['sha256']:fail('tex0-changed:'+row['path'])
        raster = tile_raster(data, road_ids)
        target=output / ('w%d_%d_%d.npy' % (row['worldMapID'], *row['tile']))
        np.save(target, raster)
        raster_files.append(dict(path=target.name,bytes=target.stat().st_size,sha256=sha(target.read_bytes())))
        covered += int((raster >= 128).sum())
    audit = dict(format='rikui-road-texture-audit-v1', tex0ManifestSHA256=args.manifest_sha256,
                 listfileSHA256=args.listfile_sha256, parserSHA256=sha(pathlib.Path(__file__).read_bytes()),
                 pattern=ROAD_NAME.pattern, extra=sorted(ROAD_EXTRA), exclude=sorted(ROAD_EXCLUDE),
                 textures=sorted(([i, names.get(i), usage[i], i in road_ids] for i in ids), key=lambda r: -r[2]),
                 roadTextures=len(road_ids), tiles=len(manifest['files']), roadCellsAtHalf=covered,
                 files=raster_files,cellYards=TILE / CELLS, nativeVerified=False)
    (output / 'road-audit.json').write_text(json.dumps(audit, indent=1), encoding='utf-8')
    print(json.dumps(dict(output=str(output), tiles=len(manifest['files']), roadTextures=len(road_ids), roadCellsAtHalf=covered,
                          auditSHA256=sha((output / 'road-audit.json').read_bytes()))))


if __name__ == '__main__':
    main()
