"""Atomically install pinned physical world packs alongside legacy navigation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

FORMAT = 'rikui-world-addon-export-v1'
OWNER = 'rikui-world-navigation-install-v1'
RECEIPT = '.rikui-world-navigation.json'
MANIFEST = 'world-export-receipt.json'
NAMESPACE = r'W[0-9]+_(?:G[a-f0-9]{16}|X[np][0-9]+_Z[np][0-9]+)'
ADDON = re.compile(r'(?:RikUIQuestTerrainMap_M[1-9][0-9]*|RikUIQuestTerrain_' + NAMESPACE + r'(?:_R[0-9]{3})?|RikUIQuestPaths_' + NAMESPACE + r'(?:_P[0-9]{3})?|RikUIQuestSeams_S[a-f0-9]{16})')
LEAF = re.compile(r'[A-Za-z0-9_-]+\.(?:lua|toc)')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def plain_path(path, root):
    require(not path.is_symlink() and not os.path.isjunction(path), 'linked path: ' + str(path))
    resolved = path.resolve()
    require(resolved.is_relative_to(root), 'path escapes target root')
    return resolved


def inventory(root, names):
    result = {}
    for name in sorted(names):
        folder = plain_path(root / name, root)
        require(folder.is_dir(), 'missing addon: ' + name)
        for path in folder.iterdir():
            plain_path(path, root)
            require(path.is_file() and LEAF.fullmatch(path.name), 'unexpected addon content')
            raw = path.read_bytes()
            result[name + '/' + path.name] = {'bytes': len(raw), 'sha256': digest(raw)}
    return result


def records(manifest):
    require(manifest.get('format') == FORMAT, 'unknown compiled format')
    require(manifest.get('identity') == {'product': 'forever', 'build': '1.60.1.69913', 'locale': 'enUS'}, 'world identity mismatch')
    rows = manifest.get('files')
    require(isinstance(rows, list) and 1 <= len(rows) <= 131072, 'invalid compiled file list')
    result, total = {}, 0
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get('path'), str), 'invalid file record')
        name = row['path']
        parts = name.split('/')
        addon = len(parts) == 2 and ADDON.fullmatch(parts[0]) and LEAF.fullmatch(parts[1])
        audit = name == 'world-pack-seams.json' or re.fullmatch(r'audit/' + NAMESPACE + r'\.json', name)
        require(addon or audit, 'invalid generated path')
        require(name not in result, 'duplicate generated path')
        cap = 1048576 if addon else 67108864
        require(type(row.get('bytes')) is int and 0 < row['bytes'] <= cap, 'invalid source size')
        require(isinstance(row.get('sha256'), str) and re.fullmatch('[a-f0-9]{64}', row['sha256']), 'invalid source hash')
        result[name] = {key: row[key] for key in ('bytes', 'sha256')}
        total += row['bytes']
    require(total <= 4294967296, 'world source size bound')
    for field in ('inputSHA256', 'sourceProfileSHA256', 'placementIndexSHA256', 'seamSHA256'):
        require(isinstance(manifest.get(field), str) and re.fullmatch('[a-f0-9]{64}', manifest[field]), 'missing source pin')
    return result


def expected_files(manifest):
    all_files = records(manifest)
    result = {name: row for name, row in all_files.items() if ADDON.fullmatch(name.split('/')[0])}
    names = {name.split('/')[0] for name in result}
    packs, maps = manifest.get('packs'), manifest.get('maps')
    require(isinstance(packs, list) and 1 <= len(packs) <= 2290, 'invalid physical pack set')
    require(isinstance(maps, list) and 1 <= len(maps) <= 256 and len(set(maps)) == len(maps), 'invalid map index set')
    require(all(type(n) is int and 0 < n < 100000 for n in maps), 'invalid map index')
    expected, seen = {'RikUIQuestTerrainMap_M' + str(n) for n in maps}, set()
    for pack in packs:
        require(isinstance(pack, dict), 'invalid pack descriptor')
        ns = pack.get('namespace')
        require(isinstance(ns, str) and re.fullmatch(NAMESPACE, ns) and ns not in seen, 'invalid physical namespace')
        require(type(pack.get('worldMapID')) is int and ns.startswith('W' + str(pack['worldMapID']) + '_'), 'pack world mismatch')
        require(type(pack.get('regions')) is int and 1 <= pack['regions'] <= 256, 'invalid region count')
        require(type(pack.get('compact')) is bool, 'invalid compact declaration')
        seen.add(ns)
        base = 'RikUIQuestTerrain_' + ns
        expected.add(base)
        expected.update(base + '_R%03d' % i for i in range(1, pack['regions'] + 1))
        require('audit/' + ns + '.json' in all_files, 'missing physical source audit')
        if pack['compact']:
            base = 'RikUIQuestPaths_' + ns
            parts = sorted(n for n in names if n.startswith(base + '_P'))
            require(1 <= len(parts) <= 512 and parts == [base + '_P%03d' % i for i in range(1, len(parts) + 1)], 'invalid compact part set')
            expected.add(base)
            expected.update(parts)
    seams = {n for n in names if n.startswith('RikUIQuestSeams_S')}
    require(type(manifest.get('seams')) is int and manifest['seams'] >= 0 and bool(seams) == bool(manifest['seams']), 'seam declaration mismatch')
    expected.update(seams)
    require(names == expected, 'catalog and addon set differ')
    for name in names:
        require(name + '/' + name + '.toc' in result, 'missing addon TOC')
    return result, names


def source_pack(source, expected_sha):
    candidate = Path(source)
    require(not candidate.is_symlink() and not os.path.isjunction(candidate), 'linked source pack')
    source = candidate.resolve()
    manifest_path = plain_path(source / MANIFEST, source)
    raw = manifest_path.read_bytes()
    require(len(raw) <= 67108864 and digest(raw) == expected_sha, 'compiled receipt hash mismatch')
    manifest = json.loads(raw)
    expected, names = expected_files(manifest)
    all_files = records(manifest)
    require(inventory(source, names) == expected, 'source pack bytes differ')
    for name, record in all_files.items():
        path = source / name
        for parent in path.parents:
            if parent == source:
                break
            plain_path(parent, source)
        plain_path(path, source)
        raw = path.read_bytes()
        require(len(raw) == record['bytes'] and digest(raw) == record['sha256'], 'source audit bytes differ')
    require({p.name for p in source.iterdir()} == names | {'audit', 'world-pack-seams.json', MANIFEST}, 'unexpected source pack files')
    require({p.name for p in (source / 'audit').iterdir()} == {n.split('/')[1] for n in all_files if n.startswith('audit/')}, 'unexpected source audit files')
    return source, manifest, expected, names

def target_root(addons):
    path = Path(addons)
    require(not path.is_symlink() and not os.path.isjunction(path), 'linked AddOns target')
    path = path.resolve()
    require(path.is_dir() and path.name.lower() == 'addons', 'existing AddOns target required')
    return path


def verify_installed(source, expected_sha, addons):
    _, _, expected, names = source_pack(source, expected_sha)
    addons = target_root(addons)
    actual_names = {path.name for path in addons.iterdir() if ADDON.fullmatch(path.name)}
    require(actual_names == names, 'installed addon set differs')
    require(inventory(addons, names) == expected, 'installed bytes differ')
    receipt = json.loads(plain_path(addons / RECEIPT, addons).read_text())
    require(receipt.get('owner') == OWNER and receipt.get('manifestSHA256') == expected_sha
            and receipt.get('files') == expected, 'installed ownership receipt differs')
    return {'verifiedFiles': len(expected), 'addons': len(names), 'manifestSHA256': expected_sha}


def install(source, expected_sha, addons):
    source, manifest, expected, names = source_pack(source, expected_sha)
    addons = target_root(addons)
    require(not source.is_relative_to(addons) and not addons.is_relative_to(source), 'source and target overlap')
    existing = {path.name for path in addons.iterdir() if ADDON.fullmatch(path.name)}
    receipt_path = addons / RECEIPT
    if existing:
        require(receipt_path.is_file(), 'existing world addons have no ownership receipt')
        prior = json.loads(plain_path(receipt_path, addons).read_text())
        require(prior.get('owner') == OWNER and isinstance(prior.get('files'), dict), 'invalid prior ownership')
        require({name.split('/')[0] for name in prior['files']} == existing, 'prior owned addon set differs')
        require(inventory(addons, existing) == prior['files'], 'prior owned files were modified')
        if prior.get('manifestSHA256') == expected_sha:
            return verify_installed(source, expected_sha, addons)
    elif receipt_path.exists():
        raise ValueError('orphan ownership receipt')
    # Staging and backups share the target volume for atomic directory renames.
    # They remain available for inspection/recovery; no recursive deletion.
    stage = Path(tempfile.mkdtemp(prefix='.rikui-world-stage-', dir=addons.parent)).resolve()
    require(stage.parent == addons.parent, 'invalid staging parent')
    backup = stage / 'previous'
    backup.mkdir()
    for name in sorted(names):
        shutil.copytree(source / name, stage / name)
    require(inventory(stage, names) == expected, 'staged bytes differ')
    placed, moved = [], []
    receipt_moved, receipt_written = False, False
    receipt = {'owner': OWNER, 'manifestSHA256': expected_sha,
               'inputSHA256': manifest['inputSHA256'], 'files': expected}
    pending_receipt = stage / 'new-receipt.json'
    pending_receipt.write_text(json.dumps(receipt, sort_keys=True, indent=2) + '\n')
    try:
        for name in sorted(existing):
            plain_path(addons / name, addons).replace(backup / name)
            moved.append(name)
        if receipt_path.exists():
            plain_path(receipt_path, addons).replace(backup / RECEIPT)
            receipt_moved = True
        for name in sorted(names):
            plain_path(stage / name, stage).replace(addons / name)
            placed.append(name)
        pending_receipt.replace(receipt_path)
        receipt_written = True
        result = verify_installed(source, expected_sha, addons)
    except BaseException:
        for name in reversed(placed):
            plain_path(addons / name, addons).replace(stage / name)
        if receipt_written:
            plain_path(receipt_path, addons).replace(stage / 'failed-receipt.json')
        for name in reversed(moved):
            plain_path(backup / name, backup).replace(addons / name)
        if receipt_moved:
            (backup / RECEIPT).replace(receipt_path)
        raise
    result['backup'] = str(backup)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['install', 'verify'])
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--expected-manifest-sha256', required=True)
    parser.add_argument('--addons', type=Path, required=True)
    args = parser.parse_args()
    operation = install if args.command == 'install' else verify_installed
    print(json.dumps(operation(args.source, args.expected_manifest_sha256, args.addons), sort_keys=True))


if __name__ == '__main__':
    main()
