"""Install compiled road networks and quest patches; retire legacy mesh packs.

install  stages every road addon beside AddOns, swaps them in by directory
         rename and writes an ownership receipt. The previous road addons are
         kept in the stage folder's 'previous' directory.
verify   checks installed bytes and the ownership receipt.
retire   moves legacy detailed-mesh and compact-path addons (and their
         ownership receipts) out of AddOns into a new backup directory.
Nothing is deleted.
"""
import argparse, hashlib, json, os, re, shutil, tempfile
from pathlib import Path

OWNER = 'rikui-road-network-install-v1'
RECEIPT = '.rikui-road-network.json'
MANIFEST = 'road-network-receipt.json'
ADDON = re.compile(r'RikUIQuestRoads(?:_W[0-9]+(?:_P[0-9]{3})?)?')
LEAF = re.compile(r'[A-Za-z0-9_-]+\.(?:lua|toc)')
LEGACY = re.compile(r'RikUIQuest(?:Terrain|Paths|Seams|TerrainMap)(?:_[A-Za-z0-9_]+)?')
LEGACY_RECEIPTS = ('.rikui-world-navigation.json', '.rikui-prepared-paths.json')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def plain(path, root):
    require(not path.is_symlink() and not os.path.isjunction(path), 'linked path: ' + str(path))
    resolved = path.resolve()
    require(resolved == root or resolved.is_relative_to(root), 'path escapes root')
    return resolved


def addons_root(path):
    path = Path(path)
    require(not path.is_symlink() and not os.path.isjunction(path), 'linked AddOns target')
    path = path.resolve()
    require(path.is_dir() and path.name.lower() == 'addons', 'existing AddOns target required')
    return path


def inventory(root, names):
    result = {}
    for name in sorted(names):
        folder = plain(root / name, root)
        require(folder.is_dir(), 'missing addon: ' + name)
        for path in folder.iterdir():
            plain(path, root)
            require(path.is_file() and LEAF.fullmatch(path.name), 'unexpected addon content: ' + str(path))
            raw = path.read_bytes()
            result[name + '/' + path.name] = {'bytes': len(raw), 'sha256': digest(raw)}
    return result


def source_pack(source, expected_sha):
    source = Path(source).resolve()
    raw = plain(source / MANIFEST, source).read_bytes()
    require(digest(raw) == expected_sha, 'road receipt hash mismatch')
    manifest = json.loads(raw)
    require(manifest.get('format') == 'rikui-road-network-receipt-v1', 'unknown road receipt')
    expected = {}
    for row in manifest['files']:
        parts = row['path'].split('/')
        require(len(parts) == 2 and ADDON.fullmatch(parts[0]) and LEAF.fullmatch(parts[1]), 'invalid road path')
        expected[row['path']] = {'bytes': row['bytes'], 'sha256': row['sha256']}
    names = {name.split('/')[0] for name in expected}
    require('RikUIQuestRoads' in names, 'road index addon missing')
    require(inventory(source, names) == expected, 'source road bytes differ')
    return source, expected, names


def verify(source, expected_sha, addons):
    _, expected, names = source_pack(source, expected_sha)
    addons = addons_root(addons)
    actual = {p.name for p in addons.iterdir() if ADDON.fullmatch(p.name)}
    require(actual == names, 'installed road addon set differs')
    require(inventory(addons, names) == expected, 'installed road bytes differ')
    receipt = json.loads(plain(addons / RECEIPT, addons).read_text())
    require(receipt.get('owner') == OWNER and receipt.get('manifestSHA256') == expected_sha
            and receipt.get('files') == expected, 'road ownership receipt differs')
    return {'addons': len(names), 'verifiedFiles': len(expected), 'manifestSHA256': expected_sha}


def install(source, expected_sha, addons):
    source, expected, names = source_pack(source, expected_sha)
    addons = addons_root(addons)
    require(not source.is_relative_to(addons), 'source inside AddOns')
    existing = {p.name for p in addons.iterdir() if ADDON.fullmatch(p.name)}
    receipt_path = addons / RECEIPT
    if existing:
        require(receipt_path.is_file(), 'existing road addons have no ownership receipt')
        prior = json.loads(plain(receipt_path, addons).read_text())
        require(prior.get('owner') == OWNER and inventory(addons, existing) == prior.get('files'), 'owned road files were modified')
    else:
        require(not receipt_path.exists(), 'orphan road ownership receipt')
    stage = Path(tempfile.mkdtemp(prefix='.rikui-road-stage-', dir=addons.parent)).resolve()
    backup = stage / 'previous'
    backup.mkdir()
    for name in sorted(names):
        shutil.copytree(source / name, stage / name)
    require(inventory(stage, names) == expected, 'staged road bytes differ')
    (stage / 'new-receipt.json').write_text(json.dumps({'owner': OWNER, 'manifestSHA256': expected_sha, 'files': expected},
                                                       sort_keys=True, indent=1) + '\n')
    placed, moved = [], []
    try:
        for name in sorted(existing):
            plain(addons / name, addons).replace(backup / name); moved.append(name)
        if receipt_path.exists():
            receipt_path.replace(backup / RECEIPT)
        for name in sorted(names):
            (stage / name).replace(addons / name); placed.append(name)
        (stage / 'new-receipt.json').replace(receipt_path)
        result = verify(source, expected_sha, addons)
    except BaseException:
        for name in reversed(placed):
            (addons / name).replace(stage / name)
        for name in reversed(moved):
            (backup / name).replace(addons / name)
        if (backup / RECEIPT).exists():
            (backup / RECEIPT).replace(receipt_path)
        raise
    result['backup'] = str(backup)
    return result


def retire(addons, backup):
    addons = addons_root(addons)
    backup = Path(backup).resolve()
    require(not backup.exists(), 'retire backup must be a new directory')
    require(not backup.is_relative_to(addons), 'backup inside AddOns')
    legacy = sorted(p.name for p in addons.iterdir() if p.is_dir() and LEGACY.fullmatch(p.name))
    receipts = [name for name in LEGACY_RECEIPTS if (addons / name).is_file()]
    backup.mkdir(parents=True)
    moved = []
    for name in legacy:
        plain(addons / name, addons)
        shutil.move(str(addons / name), str(backup / name)); moved.append(name)
    for name in receipts:
        shutil.move(str(addons / name), str(backup / name))
    (backup / 'retired.json').write_text(json.dumps({'addons': moved, 'receipts': receipts, 'from': str(addons)}, indent=1) + '\n')
    return {'retired': len(moved), 'receipts': receipts, 'backup': str(backup)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['install', 'verify', 'retire'])
    p.add_argument('--source', type=Path)
    p.add_argument('--expected-manifest-sha256')
    p.add_argument('--addons', type=Path, required=True)
    p.add_argument('--backup', type=Path)
    a = p.parse_args()
    if a.command == 'retire':
        require(a.backup is not None, 'retire needs --backup')
        result = retire(a.addons, a.backup)
    else:
        require(a.source and a.expected_manifest_sha256, 'install/verify need --source and --expected-manifest-sha256')
        result = (install if a.command == 'install' else verify)(a.source, a.expected_manifest_sha256, a.addons)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
