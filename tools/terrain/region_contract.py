"""Pinned geographic profiles for local derived meshes; never native traversal proof."""
import west_profile as west
import map_profile as fullmap

REGION_ID = 'dun-morogh-kharanos-seam-69913'
REGION_FORMAT = 'rikui-nav-region-proof-v1'
OLD_BOUNDS = [-1066.6673177083333, -5866.667317708333, -533.333984375, -5333.333984375]
REGION_BOUNDS = [OLD_BOUNDS[0], OLD_BOUNDS[1], OLD_BOUNDS[2] + 128, OLD_BOUNDS[3]]
FILES = {
    775971: (294988, '160452dec4c2b0ae4cbe7468ce52fee91ac7ec521d2cb0f28e955def0d087137'),
    777997: (454740, 'dddd2c48191b3cc4db68647063c9e484640651a2facb74910c581d300ed8b1d9'),
    777998: (36984, '77449ed5a2e4c7f748c43b3e42d7172c24dece2a4c4547402eae1d4ce67c3fde'),
    778197: (454740, '3cf93beb9f349f5928c8621eb8e03fba26e619c86560127ecff1d35bdbd02409'),
    778198: (40000, '18a62d51a583c0e263579b95bcf16e87a16918d843c927a69f98aeca54ed6152'),
}
TILES = [([32, 42], 777997, 777998), ([33, 42], 778197, 778198)]


def validate(manifest, source, region_bounds, need):
    need(type(manifest.get('mapID')) is int and manifest['mapID'] == 0, 'unsupported-map-tile')
    if manifest.get('format') == 'rikui-nav-tile-proof-v1':
        need(manifest.get('tile') == [33, 42] and 'tiles' not in manifest and 'regionID' not in manifest,
             'unsupported-map-tile')
        expected = OLD_BOUNDS
        region = {'kind': 'single-tile', 'tiles': [[33, 42]]}
    else:
        need(manifest.get('format') == REGION_FORMAT, 'unsupported-manifest-format')
        if manifest.get('regionID')==fullmap.REGION_ID:
            need(manifest.get('tiles')==[r[0] for r in fullmap.TILES] and 'tile' not in manifest,'unsupported-map-source-tiles')
            inputs=source.get('inputs')
            need(type(inputs) is dict and set(inputs)=={'wdt','tiles'},'map-source-inputs')
            rows=inputs.get('tiles')
            need(type(rows) is list and len(rows)==70,'map-source-tile-count')
            records=[inputs['wdt']]
            for row,(tile,root,obj) in zip(rows,fullmap.TILES):
                need(row.get('tile')==tile and row['root']['fileDataID']==root and row['obj']['fileDataID']==obj,'map-source-tile-mapping')
                records.extend((row['root'],row['obj']))
            need(inputs['wdt']['fileDataID']==775971 and fullmap.record_digest(records)==fullmap.ROOT_RECORDS_SHA256,'map-source-record-pin')
            need(source['acquisitionReceipt']['sha256']==fullmap.RECEIPT_SHA256,'map-source-receipt-pin')
            need(all(abs(a-b)<.002 for a,b in zip(region_bounds,fullmap.BOUNDS)),'map-source-bounds')
            return {'kind':'sourced-region','regionID':fullmap.REGION_ID,'tiles':[r[0] for r in fullmap.TILES]}
        expanded=manifest.get('regionID')==west.REGION_ID
        selected=west.TILES if expanded else TILES
        pins=west.FILES if expanded else FILES
        need(manifest.get('regionID') in (REGION_ID,west.REGION_ID) and manifest.get('tiles') == [r[0] for r in selected]
             and 'tile' not in manifest, 'unsupported-source-region')
        inputs = source.get('inputs')
        need(type(inputs) is dict and set(inputs) == {'wdt', 'tiles'}, 'invalid-region-source-inputs')

        def file_record(record, ident):
            need(type(record) is dict and set(record) == {'path', 'fileDataID', 'bytes', 'sha256'},
                 'invalid-region-source-file')
            size, digest = pins[ident]
            need(type(record['fileDataID']) is int and record['fileDataID'] == ident
                 and type(record['bytes']) is int and record['bytes'] == size
                 and record['sha256'] == digest, 'unrecognized-region-source-file')
            path = record['path']
            need(type(path) is str and 0 < len(path) <= 4096 and '\0' not in path,
                 'invalid-region-source-path')
            # Audit paths are never opened by this validator.

        file_record(inputs['wdt'], 775971)
        tiles = inputs['tiles']
        need(type(tiles) is list and len(tiles) == len(selected), 'invalid-region-source-tiles')
        for row, (tile, root, obj) in zip(tiles, selected):
            need(type(row) is dict and set(row) == {'tile', 'root', 'obj'}
                 and row['tile'] == tile, 'invalid-region-source-tile')
            file_record(row['root'], root)
            file_record(row['obj'], obj)
        expected = west.BOUNDS if expanded else REGION_BOUNDS
        region = {'kind': 'sourced-region', 'regionID': manifest['regionID'], 'tiles': [r[0] for r in selected]}
    need(all(abs(a - b) < .002 for a, b in zip(region_bounds, expected)),
         'unsupported-source-region-bounds')
    return region
