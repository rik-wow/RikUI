"""Extract a client build's Blizzard UI source (interface/addons Lua, XML, TOC).

Uses the pinned TACTTool against the local client (read-only) and the community
listfile for file IDs. Files the build does not ship are skipped. The output is
a plain tree for reading and diffing between builds.
"""
import argparse, concurrent.futures, csv, os, pathlib, re, subprocess

SUFFIXES = ('.lua', '.xml', '.toc')
WORKERS = os.cpu_count() or 1


def entries(listfile):
    rows = []
    with open(listfile, encoding='utf-8', errors='replace') as handle:
        for line in handle:
            fid, _, name = line.strip().partition(';')
            low = name.lower()
            if low.startswith('interface/addons/blizzard_') and low.endswith(SUFFIXES) and fid.isdigit():
                rows.append((int(fid), name))
    return rows


def run(job):
    tool, game, product, build, cdn, locale, out, number, rows = job
    work = out / ('.work-%02d' % number)
    work.mkdir(parents=True)
    listing = work / 'files.list'
    listing.write_text(''.join('%d;%s\n' % (fid, name.replace('/', '__')) for fid, name in rows), encoding='utf-8')
    with (work / 'extract.log').open('wb') as log:
        subprocess.run([tool, '-d', game, '-p', product, '-b', build, '-c', cdn, '-l', locale,
                        '-m', 'list', '-i', str(listing), '-o', str(work / 'files')],
                       cwd=work, stdout=log, stderr=subprocess.STDOUT, timeout=7200, check=False)
    count = 0
    for fid, name in rows:
        flat = work / 'files' / name.replace('/', '__')
        if flat.is_file():
            target = out / name
            target.parent.mkdir(parents=True, exist_ok=True)
            flat.replace(target)
            count += 1
    return count


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--listfile', required=True)
    p.add_argument('--game-root', required=True)
    p.add_argument('--tact-tool', required=True)
    p.add_argument('--product', default='wow_classic_beta')
    p.add_argument('--build-config', required=True)
    p.add_argument('--cdn-config', required=True)
    p.add_argument('--locale', default='enUS')
    p.add_argument('--output', required=True)
    args = p.parse_args()
    out = pathlib.Path(args.output)
    out.mkdir(parents=True)
    rows = entries(args.listfile)
    jobs = [(args.tact_tool, args.game_root, args.product, args.build_config, args.cdn_config, args.locale, out, n,
             rows[n::WORKERS]) for n in range(WORKERS)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        total = sum(pool.map(run, jobs))
    print('%d of %d listed UI files extracted to %s' % (total, len(rows), out))


if __name__ == '__main__':
    main()
