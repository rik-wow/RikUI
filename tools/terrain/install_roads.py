"""Install compiled road networks and quest patches; retire legacy mesh packs.

A compiled network has two parts. generated/roads/ (index, world catalogs and
stream pages, listed by roads.xml) goes inside the RikUI addon folder, where the
committed generated/index.xml loads it with the addon. The RikUIQuestRoads_W<n>_P<nnn>
LoadOnDemand patch packs sit beside RikUI in AddOns.

install  stages both parts, swaps them in by directory rename and writes an
         ownership receipt in AddOns. Everything replaced (including the old
         RikUIQuestRoads index, world and part addons of the previous layout)
         is kept in the stage folder's 'previous' directory.
verify   checks installed bytes and the ownership receipt.
retire   moves legacy detailed-mesh and compact-path addons (and their
         ownership receipts) out of AddOns into a new backup directory.
Nothing is deleted.
"""
import argparse, hashlib, json, os, re, shutil, tempfile
from pathlib import Path

OWNER = 'rikui-road-network-install-v2'
OWNERS = ('rikui-road-network-install-v1', OWNER)
RECEIPT = '.rikui-road-network.json'
MANIFEST = 'road-network-receipt.json'
REVIEW = 'review/'
EMBEDDED = 'generated/roads/'
EMBEDDED_LEAF = re.compile(r'[A-Za-z0-9_-]+\.(?:lua|xml)')
ADDON = re.compile(r'RikUIQuestRoads(?:_W[0-9]+(?:_P[0-9]{3}|_N[0-9]{2})?)?')  # every road layout ever installed
PACK = re.compile(r'RikUIQuestRoads_W[0-9]+_P[0-9]{3}')
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


def rikui_root(path):
    """The RikUI addon folder; a symlink or junction to a checkout is followed."""
    path = Path(path).resolve()
    require((path / 'RikUI.toc').is_file() and (path / 'generated' / 'index.xml').is_file(),
            'RikUI folder with generated/index.xml required')
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


def embedded_inventory(folder, root):
    """Files of one generated/roads directory, keyed like the compiler manifest."""
    result = {}
    if not folder.exists():
        return result
    plain(folder, root)
    for path in folder.iterdir():
        plain(path, root)
        require(path.is_file() and EMBEDDED_LEAF.fullmatch(path.name), 'unexpected embedded content: ' + str(path))
        raw = path.read_bytes()
        result[EMBEDDED + path.name] = {'bytes': len(raw), 'sha256': digest(raw)}
    return result


def source_pack(source, expected_sha):
    source = Path(source).resolve()
    raw = plain(source / MANIFEST, source).read_bytes()
    require(digest(raw) == expected_sha, 'road receipt hash mismatch')
    manifest = json.loads(raw)
    require(manifest.get('format') == 'rikui-road-network-receipt-v1', 'unknown road receipt')
    expected = {}
    for row in manifest['files']:
        if row['path'].startswith(REVIEW):
            continue  # compiler review data (lift candidates); never installed
        parts = row['path'].split('/')
        if row['path'].startswith(EMBEDDED):
            require(len(parts) == 3 and EMBEDDED_LEAF.fullmatch(parts[2]), 'invalid embedded road path')
        else:
            require(len(parts) == 2 and PACK.fullmatch(parts[0]) and LEAF.fullmatch(parts[1]), 'invalid road path')
        expected[row['path']] = {'bytes': row['bytes'], 'sha256': row['sha256']}
    names = {name.split('/')[0] for name in expected if not name.startswith(EMBEDDED)}
    require(EMBEDDED + 'index.lua' in expected and EMBEDDED + 'roads.xml' in expected, 'embedded road index missing')
    actual = inventory(source, names)
    actual.update(embedded_inventory(source / 'generated' / 'roads', source))
    require(actual == expected, 'source road bytes differ')
    return source, expected, names


def installed_inventory(addons, rikui, names):
    actual = inventory(addons, names)
    actual.update(embedded_inventory(rikui / 'generated' / 'roads', rikui))
    return actual


def verify(source, expected_sha, addons, rikui):
    _, expected, names = source_pack(source, expected_sha)
    addons, rikui = addons_root(addons), rikui_root(rikui)
    actual = {p.name for p in addons.iterdir() if ADDON.fullmatch(p.name)}
    require(actual == names, 'installed road addon set differs')
    require(installed_inventory(addons, rikui, names) == expected, 'installed road bytes differ')
    receipt = json.loads(plain(addons / RECEIPT, addons).read_text())
    require(receipt.get('owner') == OWNER and receipt.get('manifestSHA256') == expected_sha
            and receipt.get('files') == expected, 'road ownership receipt differs')
    return {'addons': len(names), 'verifiedFiles': len(expected), 'manifestSHA256': expected_sha}


def install(source, expected_sha, addons, rikui):
    source, expected, names = source_pack(source, expected_sha)
    addons, rikui = addons_root(addons), rikui_root(rikui)
    require(not source.is_relative_to(addons) and not source.is_relative_to(rikui), 'source inside the install target')
    existing = {p.name for p in addons.iterdir() if ADDON.fullmatch(p.name)}
    embedded = rikui / 'generated' / 'roads'
    receipt_path = addons / RECEIPT
    if existing or embedded.exists():
        require(receipt_path.is_file(), 'existing road data has no ownership receipt')
        prior = json.loads(plain(receipt_path, addons).read_text())
        require(prior.get('owner') in OWNERS and installed_inventory(addons, rikui, existing) == prior.get('files'),
                'owned road files were modified')
    else:
        require(not receipt_path.exists(), 'orphan road ownership receipt')
    # Renames must stay on one volume: packs stage beside AddOns, the embedded
    # files inside the RikUI folder's generated/ (it may be a junction to another drive).
    stage = Path(tempfile.mkdtemp(prefix='.rikui-road-stage-', dir=addons.parent)).resolve()
    backup = stage / 'previous'
    backup.mkdir()
    embedded_stage = Path(tempfile.mkdtemp(prefix='.rikui-road-stage-', dir=rikui / 'generated')).resolve()
    embedded_backup = embedded_stage / 'previous'
    embedded_backup.mkdir()
    for name in sorted(names):
        shutil.copytree(source / name, stage / name)
    shutil.copytree(source / 'generated' / 'roads', embedded_stage / 'roads')
    staged = inventory(stage, names)
    staged.update(embedded_inventory(embedded_stage / 'roads', embedded_stage))
    require(staged == expected, 'staged road bytes differ')
    (stage / 'new-receipt.json').write_text(json.dumps({'owner': OWNER, 'manifestSHA256': expected_sha, 'files': expected},
                                                       sort_keys=True, indent=1) + '\n')
    placed, moved, embedded_moved, embedded_placed = [], [], False, False
    try:
        for name in sorted(existing):
            plain(addons / name, addons).replace(backup / name); moved.append(name)
        if embedded.exists():
            embedded.replace(embedded_backup / 'roads'); embedded_moved = True
        if receipt_path.exists():
            receipt_path.replace(backup / RECEIPT)
        for name in sorted(names):
            (stage / name).replace(addons / name); placed.append(name)
        (embedded_stage / 'roads').replace(embedded); embedded_placed = True
        (stage / 'new-receipt.json').replace(receipt_path)
        result = verify(source, expected_sha, addons, rikui)
    except BaseException:
        if embedded_placed:
            embedded.replace(embedded_stage / 'roads')
        for name in reversed(placed):
            (addons / name).replace(stage / name)
        if embedded_moved:
            (embedded_backup / 'roads').replace(embedded)
        for name in reversed(moved):
            (backup / name).replace(addons / name)
        if (backup / RECEIPT).exists():
            (backup / RECEIPT).replace(receipt_path)
        raise
    if not embedded_moved:
        shutil.rmtree(embedded_stage)  # nothing previous to keep
    result['backup'] = str(backup)
    result['embeddedBackup'] = str(embedded_backup) if embedded_moved else None
    result['previousAddons'] = len(moved)
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
    p.add_argument('--rikui', type=Path, help='the RikUI addon folder (default: <addons>/RikUI)')
    p.add_argument('--backup', type=Path)
    a = p.parse_args()
    if a.command == 'retire':
        require(a.backup is not None, 'retire needs --backup')
        result = retire(a.addons, a.backup)
    else:
        require(a.source and a.expected_manifest_sha256, 'install/verify need --source and --expected-manifest-sha256')
        rikui = a.rikui or Path(a.addons) / 'RikUI'
        result = (install if a.command == 'install' else verify)(a.source, a.expected_manifest_sha256, a.addons, rikui)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
