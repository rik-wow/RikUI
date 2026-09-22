#!/usr/bin/env python3
"""Compile an audited backbone JSON into dependency-free, paged Lua data.
No installation. Input SHA-256 is mandatory; existing nonempty output is refused.
"""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import re
import struct

FORMAT = 'rikui-path-backbone-v2'
CHUNK_CHARS = 32000
PAGE_VALUES = 2048
MAX_SOURCE_BYTES = 32768
MAX_RECORDS = 1048576
MAX_STREAM_BYTES = 67108864
HEX256 = re.compile(r'^[0-9a-f]{64}$')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, minimum=0, maximum=16777215):
    require(type(value) is int and minimum <= value <= maximum, 'integer out of range: ' + repr(value))
    return value


def number(value):
    require(type(value) in (int, float) and math.isfinite(value), 'non-finite or nonnumeric value')
    return float(value)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parse_json(raw):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate JSON object key: ' + key)
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique_object)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(',', ':')).encode('utf-8')


def keyed_ids(value, label):
    require(type(value) is dict, label + ' must be an object')
    out = {}
    for key, row in value.items():
        require(type(key) is str and key.isascii() and key.isdigit(), label + ' has an invalid ID key')
        qid = integer(int(key))
        require(str(qid) == key and qid not in out, label + ' has a noncanonical/duplicate ID')
        out[qid] = row
    return out


def vec3(row):
    require(type(row) is list and len(row) == 3, 'expected xyz vector')
    return tuple(number(v) for v in row)


def lua(value):
    require(value is not None, 'null cannot be represented without loss in Lua metadata')
    if type(value) is bool:
        return 'true' if value else 'false'
    if type(value) is int:
        require(abs(value) <= 9007199254740991, 'integer exceeds exact Lua number range')
        return str(value)
    if type(value) is float:
        require(math.isfinite(value), 'cannot emit non-finite Lua number')
        return repr(value)
    if type(value) is str:
        # Lua supports these escapes; keep other Unicode as UTF-8 source bytes.
        out = []
        for ch in value:
            n = ord(ch)
            if ch == '\\': out.append('\\\\')
            elif ch == '"': out.append('\\"')
            elif n < 32 or n == 127: out.append('\\%03d' % n)
            else: out.append(ch)
        return '"' + ''.join(out) + '"'
    if type(value) is list:
        return '{' + ','.join(lua(v) for v in value) + '}'
    require(type(value) is dict, 'unsupported Lua value')
    return '{' + ','.join('[' + lua(k) + ']=' + lua(value[k]) for k in sorted(value)) + '}'


def metadata_lines(value, path='p.metadata'):
    if type(value) is dict:
        yield path + '={}\n'
        for key in sorted(value):
            require(type(key) is str, 'metadata keys must be strings')
            yield from metadata_lines(value[key], path + '[' + lua(key) + ']')
    elif type(value) is list:
        yield path + '={}\n'
        for i, item in enumerate(value, 1):
            yield from metadata_lines(item, path + '[' + str(i) + ']')
    else:
        yield path + '=' + lua(value) + '\n'


def uints(values, width):
    maximum = 256 ** width - 1
    return b''.join(integer(v, 0, maximum).to_bytes(width, 'little') for v in values)


def doubles(values):
    return b''.join(struct.pack('<d', number(v)) for v in values)


def validate_and_pack(backbone):
    require(type(backbone) is dict and backbone.get('format') == 'rikui-backbone-benchmark-v1', 'unsupported input format')
    for field in ('graphSHA256', 'partitionAuditSHA256', 'sourceManifestSHA256'):
        require(type(backbone.get(field)) is str and HEX256.fullmatch(backbone[field]), 'invalid ' + field)
    metadata = backbone.get('metadata')
    require(type(metadata) is dict and type(metadata.get('identity')) is dict, 'missing metadata/identity')
    for field in ('product', 'build', 'locale'):
        require(type(metadata['identity'].get(field)) is str and metadata['identity'][field], 'missing identity ' + field)
    integer(metadata.get('uiMapID'), 1, 999999)
    integer(metadata.get('worldMapID'), 0, 999999)
    centers = {k: vec3(v) for k, v in keyed_ids(backbone.get('centers'), 'centers').items()}
    require(0 < len(centers) <= 65535, 'dense vertex count exceeds u16')
    vertex_ids = sorted(centers)
    vertex_index = {v: i for i, v in enumerate(vertex_ids, 1)}
    geometry_raw = keyed_ids(backbone.get('geometry'), 'geometry')
    require(0 < len(geometry_raw) <= min(MAX_RECORDS, 16777215), 'dense edge count exceeds limit')
    edge_ids = sorted(geometry_raw)
    edge_index = {e: i for i, e in enumerate(edge_ids, 1)}
    geometry, edge_cost, edge_by_pair = {}, {}, {}
    midpoints, midpoint_index, packed_geometry = [], {}, []
    for edge_id in edge_ids:
        row = geometry_raw[edge_id]
        require(type(row) is list and len(row) == 5, 'invalid geometry row')
        source, target = integer(row[0]), integer(row[1])
        require(source in centers and target in centers and source != target, 'geometry has missing/self endpoint')
        require((source, target) not in edge_by_pair, 'duplicate directed geometry pair')
        mid = vec3(row[2:])
        cost = math.dist(centers[source], mid) + math.dist(mid, centers[target])
        require(math.isfinite(cost) and cost >= 0, 'invalid geometric edge cost')
        geometry[edge_id] = (source, target, mid)
        edge_cost[edge_id] = cost
        edge_by_pair[source, target] = edge_id
        key = struct.pack('<3d', *mid)
        if key not in midpoint_index:
            midpoints.append(mid)
            midpoint_index[key] = len(midpoints)
        packed_geometry.extend((vertex_index[source], vertex_index[target], midpoint_index[key]))
    require(len(midpoints) <= 65535, 'dense midpoint count exceeds u16')
    boundary = backbone.get('boundary')
    require(type(boundary) is list and 0 < len(boundary) <= 16384, 'invalid gateway count')
    for node in boundary:
        integer(node)
        require(node in centers, 'gateway center missing')
    require(boundary == sorted(set(boundary)), 'boundary must be sorted and unique')
    gateway_index = {v: i for i, v in enumerate(boundary, 1)}
    trees = keyed_ids(backbone.get('trees'), 'trees')
    network = keyed_ids(backbone.get('network'), 'network')
    require(set(trees) == set(boundary) == set(network), 'tree/network gateway keys differ')
    arrays = {k: [] for k in ('boundary', 'adjOffsets', 'adjTargets', 'adjCosts', 'adjWitness', 'treeOffsets')}
    arrays['boundary'] = [vertex_index[v] for v in boundary]
    arrays['adjOffsets'] = [0]
    arrays['treeOffsets'] = [0]
    tree_edges = []
    local_count = seam_count = tree_rows = 0
    max_cost_error = 0.0
    exact_costs = 0
    for root in boundary:
        rows = trees[root]
        require(type(rows) is list and len(rows) <= MAX_RECORDS, 'invalid tree rows')
        parent = {}
        previous = -1
        for row in rows:
            require(type(row) is list and len(row) == 3, 'invalid tree record')
            node, prior, edge_id = [integer(v) for v in row]
            require(node > previous and node != root, 'tree targets duplicate, unsorted, or include root')
            previous = node
            require(edge_id in geometry and geometry[edge_id][:2] == (prior, node), 'tree witness endpoints differ')
            parent[node] = (prior, edge_id)
            tree_edges.append(edge_index[edge_id])
        distances = {root: 0.0}
        # Iterative memoized root anchoring; handles arbitrary chain depth safely.
        for node in parent:
            chain, active = [], set()
            current = node
            while current not in distances:
                require(current in parent, 'tree predecessor missing before root')
                require(current not in active, 'tree contains a cycle')
                active.add(current)
                chain.append(current)
                current = parent[current][0]
            for current in reversed(chain):
                prior, edge_id = parent[current]
                distances[current] = distances[prior] + edge_cost[edge_id]
        arrays['treeOffsets'].append(len(tree_edges))
        tree_rows += len(rows)
        require(type(network[root]) is list, 'invalid adjacency rows')
        seen_targets = set()
        previous_target = -1
        for row in sorted(network[root], key=lambda r: r[0] if type(r) is list and len(r) == 2 and type(r[0]) is int else -1):
            require(type(row) is list and len(row) == 2, 'invalid adjacency record')
            target, weight = integer(row[0]), number(row[1])
            require(target in gateway_index and target != root and target not in seen_targets, 'invalid/duplicate target')
            require(target > previous_target, 'network adjacency must retain sorted target order')
            previous_target = target
            seen_targets.add(target)
            require(weight >= 0, 'negative network weight')
            if target in parent:
                expected = distances[target]
                descriptor = 0
                local_count += 1
            else:
                edge_id = edge_by_pair.get((root, target))
                require(edge_id is not None, 'seam has no directed source edge')
                expected = edge_cost[edge_id]
                descriptor = edge_index[edge_id]
                seam_count += 1
            error = abs(weight - expected)
            max_cost_error = max(max_cost_error, error)
            exact_costs += weight == expected
            require(struct.pack('<d', weight) == struct.pack('<d', expected), 'network weight differs from exact float64 directed witness cost')
            arrays['adjTargets'].append(gateway_index[target])
            arrays['adjCosts'].append(weight)
            arrays['adjWitness'].append(descriptor)
        arrays['adjOffsets'].append(len(arrays['adjTargets']))
    require(tree_rows <= MAX_RECORDS and len(arrays['adjTargets']) <= 131072, 'payload record limit exceeded')
    streams = {
        'vids': (uints(vertex_ids, 3), 3, len(vertex_ids)),
        'centers': (doubles(x for v in vertex_ids for x in centers[v]), 24, len(vertex_ids)),
        'mids': (doubles(x for row in midpoints for x in row), 24, len(midpoints)),
        'edgeIds': (uints(edge_ids, 3), 3, len(edge_ids)),
        'geometry': (uints(packed_geometry, 2), 6, len(edge_ids)),
        'treeEdges': (uints(tree_edges, 3), 3, len(tree_edges)),
    }
    for name, (raw, stride, count) in streams.items():
        require(len(raw) == stride * count and len(raw) <= MAX_STREAM_BYTES and count <= MAX_RECORDS, 'invalid stream bounds: ' + name)
    proof = {'vertices': len(vertex_ids), 'midpoints': len(midpoints), 'geometryEdges': len(edge_ids),
             'gateways': len(boundary), 'directedEdges': len(arrays['adjTargets']), 'localShortcuts': local_count,
             'seams': seam_count, 'treeRecords': tree_rows, 'maxWitnessCostAbsoluteError': max_cost_error,
             'bitEqualWitnessCosts': exact_costs, 'costRelativeTolerance': 0, 'costAbsoluteTolerance': 0,
             'treeEndpointsVerified': True, 'treesRootAnchoredAcyclic': True,
             'meaning': 'Every encoded network edge has the retained directed geometric witness. No native traversal or global optimality assertion.'}
    return metadata, arrays, streams, proof



def pack_surface_geometry(backbone, nodes, manifest_sha, graph_sha):
    """Pack only retained polygon rings and directed portal endpoints.

    `nodes` must come from the existing terrain validator and partition normalizer.
    Keeping this pure seam makes exact packing independently testable without
    importing or duplicating the production source-admission policy.
    """
    require(manifest_sha == backbone['sourceManifestSHA256'], 'geometry manifest differs from backbone source')
    require(graph_sha == backbone['graphSHA256'], 'normalized geometry graph differs from backbone source')
    require(type(nodes) is dict and list(nodes) == sorted(nodes), 'geometry nodes must be normalized in ID order')
    retained_vertices = sorted(keyed_ids(backbone['centers'], 'centers'))
    retained_edges = keyed_ids(backbone['geometry'], 'geometry')
    surface_offsets, surface_points = [0], []
    center_checks = 0
    for vertex in retained_vertices:
        require(vertex in nodes, 'retained polygon missing from validated geometry')
        row = nodes[vertex]
        require(type(row) is dict and row.get('id') == vertex, 'geometry node ID differs')
        points = row.get('points')
        require(type(points) is list and 3 <= len(points) <= 6, 'invalid retained polygon ring')
        points = [vec3(point) for point in points]
        derived_center = tuple(sum(point[axis] for point in points) / len(points) for axis in range(3))
        require(struct.pack('<3d', *derived_center) == struct.pack('<3d', *vec3(backbone['centers'][str(vertex)])),
                'retained center differs from ordered polygon mean')
        center_checks += 1
        surface_points.extend(points)
        surface_offsets.append(len(surface_points))
    portals, original_edge_id = {}, 0
    for vertex, row in nodes.items():
        integer(vertex)
        require(type(row) is dict and row.get('id') == vertex and type(row.get('portals')) is list,
                'invalid normalized polygon')
        ordered = sorted(row['portals'], key=lambda portal: (portal['to'], canonical(portal)))
        require(ordered == row['portals'], 'portals are not normalized')
        for portal in row['portals']:
            original_edge_id += 1
            if original_edge_id not in retained_edges:
                continue
            edge = retained_edges[original_edge_id]
            require(edge[0] == vertex and edge[1] == portal.get('to'), 'original directed edge ordinal differs')
            left, right = vec3(portal.get('left')), vec3(portal.get('right'))
            midpoint = tuple((left[axis] + right[axis]) / 2 for axis in range(3))
            require(struct.pack('<3d', *midpoint) == struct.pack('<3d', *vec3(edge[2:])),
                    'directed portal midpoint differs')
            portals[original_edge_id] = (left, right)
    require(set(portals) == set(retained_edges), 'retained directed portal missing')
    streams = {
        'surfaceOffsets': (uints(surface_offsets, 4), 4, len(surface_offsets)),
        'surfacePoints': (doubles(axis for point in surface_points for axis in point), 24, len(surface_points)),
        'portalEnds': (doubles(axis for edge in sorted(retained_edges) for point in portals[edge] for axis in point),
                       48, len(retained_edges)),
    }
    for name, (raw, stride, count) in streams.items():
        require(len(raw) == stride * count and len(raw) <= MAX_STREAM_BYTES and count <= MAX_RECORDS,
                'surface stream exceeds bounds: ' + name)
    return {'streams': streams, 'surfacePoints': len(surface_points),
            'proof': {'geometryManifestSHA256': manifest_sha, 'normalizedGraphSHA256': graph_sha,
                      'sourcePolygons': len(nodes), 'sourceDirectedEdges': original_edge_id,
                      'retainedPolygonCentersBitEqual': center_checks, 'retainedPortalMidpointsBitEqual': len(portals),
                      'orderedSurfaceCoordinatesPreservedFloat64': True,
                      'directedPortalEndpointsPreservedFloat64': True}}


def validate_surface_geometry(backbone, manifest_path, expected_sha):
    """Use the existing production admission/normalization pipeline unchanged."""
    require(type(expected_sha) is str and HEX256.fullmatch(expected_sha), 'invalid expected geometry SHA-256')
    require(expected_sha == backbone['sourceManifestSHA256'], 'geometry SHA does not bind backbone source')
    # This script is installed beside both modules in tools/terrain. Imports are
    # intentionally deferred so isolated packing tests do not read a workspace.
    import compile_quest_terrain as compiler
    import terrain_partition as partition
    metadata, shards, receipt = compiler.validate(Path(manifest_path), expected_sha, regional=True)
    require(partition.canonical(metadata) == partition.canonical(backbone['metadata']),
            'validated geometry metadata/projection differs from backbone')
    nodes = partition.normalize([node for shard in shards for node in shard['polygons']])
    graph_sha = compiler.sha(partition.canonical(dict(metadata=metadata, polygons=list(nodes.values()))).encode())
    require(graph_sha == backbone['graphSHA256'], 'validated normalized graph SHA differs from backbone')
    return pack_surface_geometry(backbone, nodes, expected_sha, graph_sha)


MAX_LOAD_BYTES = 128 * 1024
MAX_LOAD_PARTS = 512


def build_files(backbone, input_sha, surfaces):
    require(type(input_sha) is str and HEX256.fullmatch(input_sha), 'invalid input SHA-256')
    metadata, arrays, streams, proof = validate_and_pack(backbone)
    require(type(surfaces) is dict and type(surfaces.get('streams')) is dict, 'v2 requires validated surface geometry')
    require(set(surfaces['streams']) == {'surfaceOffsets', 'surfacePoints', 'portalEnds'}, 'invalid surface stream set')
    streams.update(surfaces['streams'])
    proof['surfaceGeometry'] = surfaces['proof']
    map_id = metadata['uiMapID']
    addon = 'RikUIQuestPaths_M' + str(map_id)
    catalog = {'format': FORMAT, 'payloadID': input_sha, 'identity': metadata['identity'], 'uiMapID': map_id,
               'worldMapID': metadata['worldMapID'], 'addonName': addon, 'chunkChars': CHUNK_CHARS,
               'pageSize': PAGE_VALUES, 'metadataSHA256': digest(canonical(metadata)),
               'counts': {'vertices': proof['vertices'], 'gateways': proof['gateways'], 'edges': proof['directedEdges'],
                          'geometry': proof['geometryEdges'], 'midpoints': proof['midpoints'], 'treeEntries': proof['treeRecords'],
                          'surfacePoints': surfaces['surfacePoints']},
               'proof': proof,
               'streams': {}, 'arrays': {}, 'sourceManifestSHA256': backbone['sourceManifestSHA256'],
               'graphSHA256': backbone['graphSHA256'], 'partitionAuditSHA256': backbone['partitionAuditSHA256']}
    files, order = {}, []
    prefix = 'local p=RikUIQuestPathsPayloads[' + lua(input_sha) + ']\n'
    def add(name, text, payload=True):
        raw = text.encode('utf-8')
        require(len(raw) <= MAX_SOURCE_BYTES, 'source file exceeds limit: ' + name)
        require(name not in files, 'duplicate generated file')
        files[name] = raw
        if payload:
            order.append(name.split('/')[-1])
    init = 'RikUIQuestPathsPayloads=RikUIQuestPathsPayloads or {}\nRikUIQuestPathsPayloads[' + lua(input_sha) + ']='
    init += lua({'format': FORMAT, 'payloadID': input_sha, 'arrays': {k: {} for k in arrays},
                 'streams': {k: {} for k in streams}, 'metadata': {}, 'loadedParts': {}}) + '\n'
    add(addon + '/init.lua', init)
    for name in sorted(arrays):
        values = arrays[name]
        pages = (len(values) + PAGE_VALUES - 1) // PAGE_VALUES
        catalog['arrays'][name] = {'count': len(values), 'pageSize': PAGE_VALUES, 'pages': pages}
        for page in range(pages):
            path = 'p.arrays.' + name + '[' + str(page + 1) + ']'
            page_values = values[page*PAGE_VALUES:(page+1)*PAGE_VALUES]
            text = prefix + path + '=' + lua(page_values) + '\n'
            if len(text.encode('utf-8')) <= MAX_SOURCE_BYTES:
                add(addon + '/array_' + name + '_%04d.lua' % (page + 1), text)
            else:
                # Logical pages stay 2048 entries; physical assignment chunks
                # avoid Lua's per-function constant limit and oversized source.
                low, high = 1, len(page_values)
                first_count = 0
                while low <= high:
                    middle = (low + high) // 2
                    candidate = prefix + path + '=' + lua(page_values[:middle]) + '\n'
                    if len(candidate.encode('utf-8')) <= MAX_SOURCE_BYTES:
                        first_count = middle
                        low = middle + 1
                    else:
                        high = middle - 1
                require(first_count > 0, 'single array value exceeds source limit')
                add(addon + '/array_' + name + '_%04d_01.lua' % (page + 1),
                    prefix + path + '=' + lua(page_values[:first_count]) + '\n')
                part = 2
                tail_prefix = prefix + 'local q=' + path + '\n'
                contents = tail_prefix
                for slot in range(first_count + 1, len(page_values) + 1):
                    line = 'q[' + str(slot) + ']=' + lua(page_values[slot - 1]) + '\n'
                    if len((contents + line).encode('utf-8')) > MAX_SOURCE_BYTES:
                        add(addon + '/array_' + name + '_%04d_%02d.lua' % (page + 1, part), contents)
                        part += 1
                        contents = tail_prefix
                    contents += line
                add(addon + '/array_' + name + '_%04d_%02d.lua' % (page + 1, part), contents)
    for name in sorted(streams):
        raw, stride, count = streams[name]
        padded = raw + b'\0' * ((-len(raw)) % 4)
        encoded = base64.b85encode(padded).decode('ascii')
        require(len(encoded) % 5 == 0 and ']' not in encoded, 'invalid Base85 literal')
        require(base64.b85decode(encoded)[:len(raw)] == raw, 'Base85 roundtrip differs')
        parts = (len(encoded) + CHUNK_CHARS - 1) // CHUNK_CHARS
        catalog['streams'][name] = {'bytes': len(raw), 'stride': stride, 'count': count, 'chunkChars': CHUNK_CHARS,
                                    'parts': parts, 'rawSHA256': digest(raw), 'encodedSHA256': digest(encoded.encode('ascii'))}
        for part in range(parts):
            segment = encoded[part*CHUNK_CHARS:(part+1)*CHUNK_CHARS]
            add(addon + '/stream_' + name + '_%04d.lua' % (part + 1), prefix + 'p.streams.' + name + '[' + str(part + 1) + ']=[[' + segment + ']]\n')
    page, contents = 1, prefix
    for line in metadata_lines(metadata):
        require(len((prefix + line).encode('utf-8')) <= MAX_SOURCE_BYTES, 'individual metadata assignment too large')
        if len((contents + line).encode('utf-8')) > MAX_SOURCE_BYTES:
            add(addon + '/metadata_%04d.lua' % page, contents)
            page += 1
            contents = prefix
        contents += line
    if contents != prefix:
        add(addon + '/metadata_%04d.lua' % page, contents)
    # Each synchronous LoadAddOn parses at most one bounded source group.
    # Preserve assignment order and mark completion only after every file.
    groups, group, source_bytes = [], [], 0
    for filename in order:
        if filename == 'init.lua':
            continue
        size = len(files[addon + '/' + filename])
        if group and source_bytes + size > MAX_LOAD_BYTES - 1024:
            groups.append(group)
            group, source_bytes = [], 0
        group.append(filename)
        source_bytes += size
    if group:
        groups.append(group)
    require(0 < len(groups) <= MAX_LOAD_PARTS, 'load group count exceeds bounds')
    catalog['loadParts'] = []
    for index, filenames in enumerate(groups, 1):
        part_addon = addon + '_P%03d' % index
        for filename in filenames:
            files[part_addon + '/' + filename] = files.pop(addon + '/' + filename)
        marker = prefix + 'p.loadedParts[' + str(index) + ']=true\n'
        add(part_addon + '/complete.lua', marker, False)
        body = ('## Interface: 16001\n## Title: RikUI Quest Paths Part ' + str(index) +
                '\n## AllowLoadGameType: camelot\n## LoadOnDemand: 1\n## Dependencies: ' + addon +
                '\n' + '\n'.join(filenames + ['complete.lua']) + '\n')
        add(part_addon + '/' + part_addon + '.toc', body, False)
        group_bytes = sum(len(files[part_addon + '/' + name]) for name in filenames + ['complete.lua'])
        require(group_bytes <= MAX_LOAD_BYTES, 'load group source exceeds bounds')
        catalog['loadParts'].append({'addon': part_addon, 'bytes': group_bytes})
    add('RikUIQuestPaths/catalog.lua', 'RikUIQuestPathsCatalog=' + lua(catalog) + '\n', False)
    add('RikUIQuestPaths/RikUIQuestPaths.toc', '## Interface: 16001\n## Title: RikUI Quest Paths Catalog\n## AllowLoadGameType: camelot\ncatalog.lua\n', False)
    toc = '## Interface: 16001\n## Title: RikUI Quest Paths ' + str(map_id) + '\n## AllowLoadGameType: camelot\n## LoadOnDemand: 1\n## Dependencies: RikUIQuestPaths\n' + 'init.lua' + '\n'
    add(addon + '/' + addon + '.toc', toc, False)
    manifest = {'format': 'rikui-path-backbone-compile-receipt-v2', 'inputSHA256': input_sha, 'catalog': catalog,
                'compilerSHA256': digest(Path(__file__).read_bytes()), 'metadata': metadata, 'proof': proof, 'sourceByteTotal': sum(map(len, files.values())),
                'files': [{'path': name, 'bytes': len(raw), 'sha256': digest(raw)} for name, raw in sorted(files.items())],
                'limitations': ['Precomputed modeled center/portal-midpoint routes, not authored roads.',
                                'Lua heap/runtime/native traversal have not been measured by this compiler.',
                                'Compiler proves witness feasibility/cost consistency, not independent source authenticity or global contraction completeness.']}
    files['manifest.json'] = canonical(manifest) + b'\n'
    return files, manifest


def write_or_verify(files, output, verify=False):
    output = Path(output)
    if verify:
        require(output.is_dir(), 'verification output directory is missing')
        actual = {path.relative_to(output).as_posix() for path in output.rglob('*') if path.is_file()}
        require(actual == set(files), 'compiled output file set differs')
        for name, raw in files.items():
            require((output / name).read_bytes() == raw, 'compiled output bytes differ: ' + name)
        return
    output.mkdir(parents=True, exist_ok=True)
    require(not any(output.iterdir()), 'output changed while compilation was running')
    for name, data in sorted(files.items()):
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--expected-sha256', required=True)
    parser.add_argument('--geometry-manifest', required=True, type=Path)
    parser.add_argument('--expected-geometry-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--verify-output', action='store_true', help='Rebuild expected bytes and compare existing output without writing')
    args = parser.parse_args()
    require(HEX256.fullmatch(args.expected_sha256) is not None, 'expected SHA-256 must be lowercase hex')
    if args.output.exists() and not args.verify_output:
        require(args.output.is_dir() and not any(args.output.iterdir()), 'output must be absent or an empty directory')
    raw = args.input.read_bytes()
    require(digest(raw) == args.expected_sha256, 'input SHA-256 mismatch')
    backbone = parse_json(raw)
    surfaces = validate_surface_geometry(backbone, args.geometry_manifest, args.expected_geometry_sha256)
    files, manifest = build_files(backbone, args.expected_sha256, surfaces)
    # Validate all source and proof before creating any output files.
    write_or_verify(files, args.output, args.verify_output)
    print(json.dumps({'format': manifest['format'], 'inputSHA256': args.expected_sha256,
                      'files': len(files), 'sourceByteTotal': manifest['sourceByteTotal'], 'proof': manifest['proof']}, sort_keys=True))


if __name__ == '__main__':
    main()
