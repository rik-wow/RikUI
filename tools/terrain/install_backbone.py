"""Install a verified local prepared-path pack; preserve previous owned files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

FORMAT = 'rikui-path-backbone-compile-receipt-v2'
OWNER = 'rikui-prepared-path-install-v1'
RECEIPT = '.rikui-prepared-paths.json'
ADDON = re.compile(r'RikUIQuestPaths(?:_M[1-9][0-9]*(?:_P[0-9]{3})?)?')
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


def expected_files(manifest):
    require(manifest.get('format') == FORMAT, 'unknown compiled format')
    rows = manifest.get('files')
    require(isinstance(rows, list) and 1 <= len(rows) <= 4096, 'invalid compiled file list')
    result = {}
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get('path'), str), 'invalid file record')
        parts = row['path'].split('/')
        require(len(parts) == 2 and ADDON.fullmatch(parts[0]) and LEAF.fullmatch(parts[1]), 'invalid generated path')
        require(row['path'] not in result, 'duplicate generated path')
        require(type(row.get('bytes')) is int and 0 < row['bytes'] <= 32768, 'invalid source size')
        require(isinstance(row.get('sha256'), str) and re.fullmatch('[a-f0-9]{64}', row['sha256']), 'invalid source hash')
        result[row['path']] = {key: row[key] for key in ('bytes', 'sha256')}
    catalog = manifest.get('catalog', {})
    base = catalog.get('addonName')
    require(isinstance(base, str) and re.fullmatch(r'RikUIQuestPaths_M[1-9][0-9]*', base), 'invalid base addon')
    names = {'RikUIQuestPaths', base}
    parts = catalog.get('loadParts')
    require(isinstance(parts, list) and 1 <= len(parts) <= 512, 'bounded load parts required')
    for index, part in enumerate(parts, 1):
        require(part.get('addon') == base + '_P%03d' % index, 'invalid load part order')
        names.add(part['addon'])
    require({name.split('/')[0] for name in result} == names, 'catalog and addon set differ')
    for name in names:
        require(name + '/' + name + '.toc' in result, 'missing addon TOC')
    return result, names


def source_pack(source, expected_sha):
    source = Path(source).resolve()
    raw = (source / 'manifest.json').read_bytes()
    require(digest(raw) == expected_sha, 'compiled receipt hash mismatch')
    manifest = json.loads(raw)
    expected, names = expected_files(manifest)
    require(inventory(source, names) == expected, 'source pack bytes differ')
    require({path.name for path in source.iterdir()} == names | {'manifest.json'}, 'unexpected source pack files')
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
    receipt = json.loads((addons / RECEIPT).read_text())
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
        require(receipt_path.is_file(), 'existing path addons have no ownership receipt')
        prior = json.loads(receipt_path.read_text())
        require(prior.get('owner') == OWNER and isinstance(prior.get('files'), dict), 'invalid prior ownership')
        require({name.split('/')[0] for name in prior['files']} == existing, 'prior owned addon set differs')
        require(inventory(addons, existing) == prior['files'], 'prior owned files were modified')
        if prior.get('manifestSHA256') == expected_sha:
            return verify_installed(source, expected_sha, addons)
    elif receipt_path.exists():
        raise ValueError('orphan ownership receipt')
    # Staging and backups share the target volume for atomic directory renames.
    # They remain available for inspection/recovery; no recursive deletion.
    stage = Path(tempfile.mkdtemp(prefix='.rikui-paths-stage-', dir=addons.parent)).resolve()
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
