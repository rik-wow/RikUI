"""Swim surfaces from ADT MH2O liquid instances.

Water and ocean are passable: a player swims across them. Each liquid
instance becomes a surface at its liquid height over the subcells that hold
liquid, and the terrain below stays in the mesh. Magma, slime and unknown
liquids exclude only their own subcells, and only up to just above the
surface, so banks beside a lava stream and bridges over it stay walkable.
"""
import json, pathlib, struct
import terrain_probe as t

HEADER_BYTES = 3072          # 256 chunk headers of 12 bytes
INSTANCE_BYTES = 24
MAX_INSTANCES = 8
SUBCELLS = 8                 # liquid grid cells per chunk side
# LiquidType IDs by kind, pinned from the client's LiquidType table (SoundBank).
KINDS = json.loads((pathlib.Path(__file__).resolve().parent / 'liquid-kinds-69913.json').read_text())['kinds']
SWIMMABLE = {int(i) for i, kind in KINDS.items() if kind in ('water', 'ocean')}
HEIGHT_FORMATS = {0, 1, 3}   # liquid vertex formats that start with float heights
HEIGHT_SLACK = 1.0           # yards a stored vertex height may sit outside the instance's min/max
ABOVE_SURFACE = 0.5          # yards above an unswimmable surface that are still excluded


def _exists(data, offset, width, height):
    """Row-major existence bits for the instance's subcells; no bitmap means all exist."""
    count = width * height
    if not offset:
        return [True] * count
    if offset + (count + 7) // 8 > len(data):
        t.fail('world-MH2O-bitmap-range')
    return [bool(data[offset + i // 8] >> (i % 8) & 1) for i in range(count)]


def _heights(data, instance):
    """Per-vertex surface heights, or None for a flat surface at the minimum level."""
    fmt, offset = instance['format'], instance['vertexOffset']
    count = (instance['width'] + 1) * (instance['height'] + 1)
    if not offset or (fmt < 42 and fmt not in HEIGHT_FORMATS):
        return None
    if offset + count * 4 > len(data):
        return None if fmt >= 42 else t.fail('world-MH2O-vertex-range')
    values = struct.unpack_from('<%df' % count, data, offset)
    low, high = instance['min'] - HEIGHT_SLACK, instance['max'] + HEIGHT_SLACK
    if all(low <= v <= high for v in values):
        return list(values)
    return None if fmt >= 42 else t.fail('world-MH2O-vertex-height')


def _instances(data, index):
    offset, count, attrs = struct.unpack_from('<III', data, index * 12)
    if count == 0:
        if offset or attrs:
            t.fail('world-MH2O-empty-header')
        return []
    if count > MAX_INSTANCES or offset < HEADER_BYTES or offset + count * INSTANCE_BYTES > len(data):
        t.fail('world-MH2O-instance-range')
    rows = []
    for k in range(count):
        kind, fmt, low, high, x0, y0, w, h, bitmap, vertices = struct.unpack_from('<HHffBBBBII', data, offset + k * INSTANCE_BYTES)
        if w == 0 or h == 0 or x0 + w > SUBCELLS or y0 + h > SUBCELLS:
            t.fail('world-MH2O-instance-extent')
        rows.append(dict(type=kind, format=fmt, min=low, max=high, x=x0, y=y0, width=w, height=h,
                         bitmapOffset=bitmap, vertexOffset=vertices))
    return rows


def _upward(vertices, a, b, c):
    """Order a triangle the way terrain_probe.mesh does (positive Y normal)."""
    ax, az = vertices[a * 3], vertices[a * 3 + 2]
    e1 = (vertices[b * 3] - ax, vertices[b * 3 + 2] - az)
    e2 = (vertices[c * 3] - ax, vertices[c * 3 + 2] - az)
    return (a, b, c) if e1[1] * e2[0] - e1[0] * e2[1] > 0 else (a, c, b)


def _surface(data, record, instance, vertices, triangles, areas):
    x, y, _ = record['position']
    x0, z0 = y - (instance['x'] + instance['width']) * t.UNIT, x - (instance['y'] + instance['height']) * t.UNIT
    areas.append(dict(bounds=[[x0, instance['min'], z0], [y - instance['x'] * t.UNIT, instance['max'], x - instance['y'] * t.UNIT]],
                      type=instance['type']))
    heights = _heights(data, instance)
    width, height = instance['width'], instance['height']
    base = len(vertices) // 3
    for row in range(height + 1):
        for col in range(width + 1):
            level = heights[row * (width + 1) + col] if heights else instance['min']
            vertices.extend((y - (instance['x'] + col) * t.UNIT, level, x - (instance['y'] + row) * t.UNIT))
    exists = _exists(data, instance['bitmapOffset'], width, height)
    for row in range(height):
        for col in range(width):
            if not exists[row * width + col]:
                continue
            a = base + row * (width + 1) + col
            b, c, d = a + 1, a + width + 1, a + width + 2
            triangles.extend(_upward(vertices, a, b, c))
            triangles.extend(_upward(vertices, b, d, c))


def _blocked(data, record, instance, tile):
    """Below-surface exclusion boxes for an unswimmable instance, one per run of subcells."""
    x, y, _ = record['position']
    width, height = instance['width'], instance['height']
    exists = _exists(data, instance['bitmapOffset'], width, height)
    top = instance['max'] + ABOVE_SURFACE
    boxes = []
    for row in range(height):
        col = 0
        while col < width:
            if not exists[row * width + col]:
                col += 1
                continue
            end = col
            while end + 1 < width and exists[row * width + end + 1]:
                end += 1
            c0, c1, r = instance['x'] + col, instance['x'] + end + 1, instance['y'] + row
            boxes.append(dict(tile=list(tile), chunk=[record['x'], record['y']], reason='unswimmable-liquid',
                              liquidType=instance['type'], belowSurface=True,
                              bounds=[[y - c1 * t.UNIT, -100000, x - (r + 1) * t.UNIT], [y - c0 * t.UNIT, top, x - r * t.UNIT]],
                              padding=.5))
            col = end + 1
    return boxes


def liquid(raw, records, tile, keep=None):
    """Returns (vertices, triangles, exclusions, areas) for one root ADT's MH2O.

    areas: one {bounds, type} box per swim surface, so later stages can tell
    swimming from walking.

    keep: optional set of (x, y) chunk indices to emit; others are skipped.
    """
    parts = {tag: raw[a:b] for tag, a, b in t.chunks(raw) if tag == 'MH2O'}
    if any('MCLQ' in r['subchunks'] for r in records):
        t.fail('world-MCLQ-unsupported')
    vertices, triangles, excluded, areas = [], [], [], []
    if not parts:
        return vertices, triangles, excluded, areas
    data = parts['MH2O']
    if len(data) < HEADER_BYTES:
        t.fail('world-MH2O-header')
    cells = {(r['x'], r['y']): r for r in records}
    for index in range(256):
        record = cells[(index % 16, index // 16)]
        rows = _instances(data, index)
        if keep is not None and (record['x'], record['y']) not in keep:
            continue
        for row in rows:
            if row['type'] in SWIMMABLE:
                _surface(data, record, row, vertices, triangles, areas)
            else:
                excluded.extend(_blocked(data, record, row, tile))
    return vertices, triangles, excluded, areas
