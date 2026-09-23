"""Check whether a new client build still ships the exact bytes a navigation
acquisition profile was built from.

Every file in the profile is extracted from the new build with the pinned
TACTTool (split across processes) and its SHA-256 compared with the profile.
Unchanged files mean data compiled from them is still exact for the new build;
changed or missing files are listed so only what they feed gets rebuilt.
Client input is read-only; output goes to a new external directory.
"""
import argparse, concurrent.futures, hashlib, json, os, pathlib, re, subprocess, sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import acquire as a

WORKERS = os.cpu_count() or 1


def run_chunk(args):
    tool, game, product, build, cdn, locale, output, number, rows = args
    folder = output / ('chunk-%02d' % number)
    folder.mkdir()
    listing = folder / 'files.list'
    listing.write_text(''.join('%d;%d.bin\n' % (r['fileDataID'], r['fileDataID']) for r in rows), encoding='utf-8')
    with (folder / 'extract.log').open('xb') as log:
        subprocess.run([tool, '-d', game, '-p', product, '-b', build, '-c', cdn, '-l', locale,
                        '-m', 'list', '-i', str(listing), '-o', str(folder / 'files')],
                       cwd=folder, stdout=log, stderr=subprocess.STDOUT, timeout=7200, check=False)
    found = {}
    for r in rows:
        path = folder / 'files' / ('%d.bin' % r['fileDataID'])
        found[r['fileDataID']] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    return found


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile', required=True, help='world acquisition profile (files with fileDataID and sha256)')
    p.add_argument('--game-root', required=True)
    p.add_argument('--tact-tool', required=True)
    p.add_argument('--build-config', required=True)
    p.add_argument('--cdn-config', required=True)
    p.add_argument('--version', required=True)
    p.add_argument('--output', required=True)
    args = p.parse_args()
    pin = a.load_profile()
    tool = a.checked_path(args.tact_tool)
    if tool.stat().st_size != pin['tool']['binary']['bytes'] or a.digest(tool.read_bytes()) != pin['tool']['binary']['sha256']:
        a.fail('pinned-TACTTool-hash')
    output = pathlib.Path(args.output)
    output.mkdir()
    profile = json.loads(pathlib.Path(args.profile).read_text())
    rows = profile['files']
    chunks = [rows[k::WORKERS] for k in range(WORKERS)]
    jobs = [(str(tool), args.game_root, pin['product'], args.build_config, args.cdn_config, pin['locale'], output, n, chunk)
            for n, chunk in enumerate(chunks) if chunk]
    found = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for part in pool.map(run_chunk, jobs):
            found.update(part)
    changed = [dict(fileDataID=r['fileDataID'], kind=r['kind'], old=r['sha256'], new=found.get(r['fileDataID']))
               for r in rows if found.get(r['fileDataID']) != r['sha256']]
    report = dict(format='rikui-build-verification-v1', profile=str(args.profile),
                  profileSHA256=a.digest(pathlib.Path(args.profile).read_bytes()),
                  fromIdentity=profile['identity'], toVersion=args.version, buildConfig=args.build_config,
                  cdnConfig=args.cdn_config, files=len(rows), unchanged=len(rows) - len(changed), changed=changed,
                  tool=pin['tool']['binary'], verifierSHA256=a.digest(pathlib.Path(__file__).read_bytes()))
    (output / 'verification.json').write_text(json.dumps(report, indent=1) + '\n')
    print(json.dumps(dict(files=len(rows), unchanged=report['unchanged'], changed=len(changed),
                          missing=sum(1 for c in changed if c['new'] is None))))


if __name__ == '__main__':
    main()
