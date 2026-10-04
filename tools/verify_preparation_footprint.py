"""Run packaged local preparation in a fresh private folder and measure occupied bytes.

The evidence names the exact runtime and current inputs. It is never a
developer-only replacement for the published installer.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import local_assembly as local


def occupied(root):
    total = 0
    for path in root.rglob("*"):
        try:
            if path.is_file():
                total += path.stat().st_size
        except FileNotFoundError:
            # Atomic progress/staging swaps may retire a name during observation.
            continue
    return total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("runtime", "root", "executable", "base"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--cache", help="Resume an existing retained preparation cache; keep new observation evidence separate")
    parser.add_argument("--launch", action="store_true", help="Start the owned long-running verification without a transport timeout")
    args = parser.parse_args()
    if args.launch:
        if Path(args.root).exists():
            raise ValueError("Verification root already exists")
        launcher = Path(args.root + "-launcher.log").absolute()
        with launcher.open("xb") as log:
            process = subprocess.Popen([sys.executable, "-B", str(Path(__file__).resolve()),
                *[value for value in sys.argv[1:] if value != "--launch"]],
                stdout=log, stderr=subprocess.STDOUT,
                creationflags=(subprocess.CREATE_NO_WINDOW|subprocess.NORMAL_PRIORITY_CLASS) if os.name=="nt" else 0)
        print(json.dumps(dict(pid=process.pid, log=str(launcher), evidence=str(Path(args.root)/"evidence.json"))))
        return
    root, runtime = Path(args.root).absolute(), Path(args.runtime).absolute()
    root.mkdir(parents=True, exist_ok=False)
    cache = Path(args.cache).absolute() if args.cache else root/"cache"
    if args.cache and (not cache.is_dir() or cache.is_symlink() or (hasattr(cache,"is_junction") and cache.is_junction())):
        raise ValueError("Resume cache must be an existing regular directory")
    measured = lambda: occupied(root) + (occupied(cache) if not cache.is_relative_to(root) else 0)
    env = dict(os.environ, RIKUI_NODE=str(runtime/"node/node.exe"),
               PATH=str(runtime/"node")+os.pathsep+str(runtime/"python")+os.pathsep+
                    str(Path(os.environ["SystemRoot"])/"System32")+os.pathsep+os.environ["SystemRoot"],
               PYTHONDONTWRITEBYTECODE="1")
    status = root / "status.json"
    command = [str(runtime/"python/python.exe"), "-B", str(runtime/"tools/local_assembly.py"),
        "--runtime", str(runtime), "--cache", str(cache), "--status", str(status),
        "--result", str(root/"result.json"), "--executable", args.executable,
        "--base-bundle", args.base, "--workers", str(args.workers)]
    started, samples, maximum = time.monotonic(), [], 0
    initial_memory=local.available_memory();minimum_memory=initial_memory
    with (root/"worker.log").open("xb") as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT,
            creationflags=(subprocess.CREATE_NO_WINDOW|subprocess.NORMAL_PRIORITY_CLASS) if os.name=="nt" else 0)
        while process.poll() is None:
            used = measured()
            maximum = max(maximum, used)
            try:
                progress = json.loads(status.read_bytes())
            except (OSError, ValueError):
                progress = {}
            memory=local.available_memory()
            if memory is not None:minimum_memory=memory if minimum_memory is None else min(minimum_memory,memory)
            row = dict(seconds=round(time.monotonic()-started, 1), occupiedBytes=used,availablePhysicalBytes=memory,
                       phase=progress.get("phase"), completed=progress.get("completed"),
                       total=progress.get("total"))
            samples.append(row)
            (root/"measurement.json").write_text(json.dumps(dict(peakObservedBytes=maximum,
                samples=samples), indent=2)+"\n", encoding="utf-8")
            print(json.dumps(row), flush=True)
            time.sleep(10)
    evidence = dict(format="rikui-resumed-preparation-footprint-v1" if args.cache else "rikui-cold-preparation-footprint-v1",
                    cache=str(cache), resumed=bool(args.cache), exitCode=process.returncode,workers=args.workers,
                    cpuCount=os.cpu_count(),initialAvailablePhysicalBytes=initial_memory,
                    minimumObservedAvailablePhysicalBytes=minimum_memory,
                    seconds=round(time.monotonic()-started, 1), peakObservedBytes=maximum,
                    finalBytes=measured(), samples=samples,
                    runtimeManifestSHA256=hashlib.sha256((runtime/"runtime.json").read_bytes()).hexdigest(),
                    limit="Logical-byte observations at ten-second waits plus scan cost; filesystem allocation and between-sample peaks need additional margin.")
    (root/"evidence.json").write_text(json.dumps(evidence, indent=2)+"\n", encoding="utf-8")
    raise SystemExit(process.returncode)


if __name__ == "__main__":
    main()
