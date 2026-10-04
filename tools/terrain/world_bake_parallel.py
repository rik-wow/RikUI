"""Bounded parallel world baking with byte-verified reuse and retained failures."""
import argparse
import concurrent.futures
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
from world_source import Source, canonical, sha, need
from world_bake import checked_receipt, hashes, atomic as bake_atomic

HERE = pathlib.Path(__file__).resolve().parent
SUCCESS = 'derived-pending-seam-validation'


def atomic(path, value):
    # GUI progress readers can briefly deny Windows delete sharing. This
    # scheduler receipt never changes the producing tools or their outputs.
    for attempt in range(40):
        try:
            bake_atomic(path, value)
            return
        except PermissionError:
            if attempt == 39:
                raise
            time.sleep(.05)


def verified_run(run, source, jobs, index_sha):
    """A progress row alone cannot establish successful current-generation output."""
    root = pathlib.Path(run)
    plan = json.loads((root / 'plan.json').read_bytes())
    need(plan['sourceProfileSHA256'] == source.profile_sha and
         plan['indexSHA256'] == index_sha and plan['tools'] == hashes(), 'reuse inputs changed')
    progress = json.loads((root / 'progress.json').read_bytes())
    need(progress['planSHA256'] == sha(canonical(plan)), 'reuse progress changed')
    need(progress['completed'] == len(progress['results']), 'reuse count changed')
    done, seen = set(), set()
    for row in progress['results']:
        name = row['jobID']
        need(name in jobs and name in plan['jobs'] and name not in seen, 'reuse job identity')
        seen.add(name)
        directory = root / name
        need(sha((directory / 'receipt.json').read_bytes()) == row['receiptSHA256'], 'reuse receipt changed')
        expected = dict(jobSHA256=sha(canonical(jobs[name])), sourceProfileSHA256=source.profile_sha,
                        indexSHA256=index_sha, tools=hashes())
        receipt = checked_receipt(directory, expected)
        if receipt['status'] == SUCCESS:
            done.add(name)
    return done


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'expected-sha256', 'source-directory', 'tile-csv', 'topology-inventory',
                 'placement-index', 'index-sha256', 'root'):
        p.add_argument('--' + name, required=True)
    p.add_argument('--world', type=int)
    p.add_argument('--workers', type=int, default=2)
    p.add_argument('--reuse', nargs='*', default=[])
    a = p.parse_args()
    need(1 <= a.workers <= 4, 'workers must be between 1 and 4')
    source = Source(a.profile, a.expected_sha256, a.source_directory, a.tile_csv, a.topology_inventory)
    jobs = {j['id']: j for j in source.jobs(a.world)}
    root = pathlib.Path(a.root).resolve()
    need(not root.is_symlink() and not root.is_relative_to(HERE), 'private output required')
    root.mkdir(parents=True, exist_ok=True)
    need(shutil.disk_usage(root).free >= 8 * 1024**3, 'bake needs at least 8 GiB free disk')
    done = set()
    for run in a.reuse:
        done.update(verified_run(run, source, jobs, a.index_sha256))
    base = [sys.executable, '-B', str(HERE / 'world_bake.py'), '--profile', a.profile,
            '--expected-sha256', a.expected_sha256, '--source-directory', a.source_directory,
            '--tile-csv', a.tile_csv, '--topology-inventory', a.topology_inventory,
            '--placement-index', a.placement_index, '--index-sha256', a.index_sha256]
    cancel = root / 'cancel'

    def bake(job):
        if cancel.exists():
            return job['id'], 'cancelled'
        need(shutil.disk_usage(root).free >= 4*1024**3, 'less than 4 GiB remains; resume after freeing space')
        out = root / job['id']
        if out.exists():
            try:
                if job['id'] in verified_run(out, source, jobs, a.index_sha256):
                    return job['id'], 'reused'
            except (ValueError, KeyError, OSError):
                pass
            retained = root / ('retained-' + job['id'] + '-' + str(time.time_ns()))
            need(out.parent == root and retained.parent == root, 'retention path escape')
            out.rename(retained)
        with (root / (job['id'] + '.log')).open('wb') as log:
            process = subprocess.Popen(base + ['--world', str(job['worldMapID']), '--batch',
                *map(str, job['batchGrid']), '--output', str(out)], cwd=HERE, stdout=log,
                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            try:
                while process.poll() is None:
                    if cancel.exists():
                        process.kill()
                        process.wait()
                        return job['id'], 'cancelled'
                    time.sleep(.2)
            except BaseException:
                process.kill()
                process.wait()
                raise
        if process.returncode:
            return job['id'], 'failed'
        need(job['id'] in verified_run(out, source, jobs, a.index_sha256), 'completed output not verified')
        return job['id'], 'ok'

    started, counts, completed = time.monotonic(), {}, []
    remaining = [job for key, job in jobs.items() if key not in done]
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
        # Submit only one job per worker ahead; cancellation does not queue the whole world.
        pending, iterator = {}, iter(remaining)
        for _ in range(a.workers):
            job = next(iterator, None)
            if job: pending[pool.submit(bake, job)] = job
        while pending:
            ready, _ = concurrent.futures.wait(pending, return_when=concurrent.futures.FIRST_COMPLETED)
            for future in ready:
                del pending[future]
                job, status = future.result()
                counts[status] = counts.get(status, 0) + 1
                completed.append(dict(jobID=job,status=status))
                progress = dict(total=len(jobs),reused=len(done),completed=len(completed),counts=counts,
                                seconds=round(time.monotonic()-started,1),results=completed)
                atomic(root / 'generation-progress.json', progress)
                print(json.dumps({k:v for k,v in progress.items() if k != 'results'}),flush=True)
                if not cancel.exists():
                    job = next(iterator, None)
                    if job: pending[pool.submit(bake, job)] = job
    if cancel.exists(): raise SystemExit(130)
    if counts.get('failed'): raise SystemExit(1)


if __name__ == '__main__':
    main()