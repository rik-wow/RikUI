"""Run world_bake.py one batch per process, several at a time.

Each job bakes into its own run directory (<root>/<jobID>) with the unchanged,
hash-pinned world_bake.py, so receipts are identical to a sequential run.
Jobs already completed in --reuse run directories are skipped. Use
road_network.py --capture-root to collect every run directory afterwards.
"""
import argparse, concurrent.futures, json, pathlib, subprocess, sys, time
from world_source import Source

HERE = pathlib.Path(__file__).resolve().parent


def finished(run_dirs):
    done = set()
    for run in run_dirs:
        progress = pathlib.Path(run) / 'progress.json'
        if progress.is_file():
            done.update(r['jobID'] for r in json.loads(progress.read_bytes())['results'])
    return done


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'expected-sha256', 'source-directory', 'tile-csv', 'topology-inventory',
                 'placement-index', 'index-sha256', 'root'):
        p.add_argument('--' + name, required=True)
    p.add_argument('--world', type=int, required=True)
    p.add_argument('--workers', type=int, default=16)
    p.add_argument('--reuse', nargs='*', default=[])
    a = p.parse_args()
    source = Source(a.profile, a.expected_sha256, a.source_directory, a.tile_csv, a.topology_inventory)
    skip = finished(a.reuse)
    jobs = [j for j in source.jobs(a.world) if j['id'] not in skip]
    root = pathlib.Path(a.root); root.mkdir(parents=True, exist_ok=True)
    base = [sys.executable, '-B', str(HERE / 'world_bake.py'), '--profile', a.profile, '--expected-sha256', a.expected_sha256,
            '--source-directory', a.source_directory, '--tile-csv', a.tile_csv, '--topology-inventory', a.topology_inventory,
            '--placement-index', a.placement_index, '--index-sha256', a.index_sha256, '--world', str(a.world)]

    def bake(job):
        out = root / job['id']
        if (out / 'progress.json').is_file():
            return job['id'], 'already'
        grid = [str(v) for v in job['batchGrid']]
        run = subprocess.run(base + ['--batch', *grid, '--output', str(out)], cwd=HERE, capture_output=True, text=True)
        return job['id'], 'ok' if run.returncode == 0 else 'failed'

    started, counts = time.monotonic(), {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
        for number, (job, status) in enumerate(pool.map(bake, jobs), 1):
            counts[status] = counts.get(status, 0) + 1
            if number % 25 == 0 or number == len(jobs):
                print(json.dumps(dict(world=a.world, done=number, total=len(jobs), counts=counts,
                                      seconds=round(time.monotonic() - started))), flush=True)
    print(json.dumps(dict(world=a.world, reused=len(skip), baked=len(jobs), counts=counts, root=str(root))))


if __name__ == '__main__':
    main()
