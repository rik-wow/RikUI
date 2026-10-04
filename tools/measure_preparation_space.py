"""Measure lossless compact storage for all retained current terrain batches.

Writes only a small private measurement receipt; existing input files are untouched.
This is a storage measurement, not a claim of fresh generation or installation.
"""
import argparse
import concurrent.futures
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent / "terrain"))
from world_storage import encode, decode
import forever_inputs as current
from local_assembly import verify_acquisition


def measure(path):
    raw = current.regular(path).read_bytes()
    stored = encode(raw, 256 * 1024 * 1024)
    if decode(stored, 256 * 1024 * 1024) != raw:
        raise ValueError("Compression changed geometry")
    return dict(path=str(path), bytes=len(raw), compressedBytes=len(stored),
                sha256=current.sha(raw), compressedSHA256=current.sha(stored))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("acquisition", "bakes", "executable", "output"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    start = time.monotonic()
    resolution = current.discover(args.executable)
    verify_acquisition(args.acquisition, resolution)
    root = Path(args.bakes)
    paths = sorted(root.glob("w*/w*/geometry.json"))
    if not paths or len(paths) > 2290:
        raise ValueError("Current geometry inventory unavailable")
    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for row in pool.map(measure, paths):
            rows.append(row)
            if len(rows) % 100 == 0:
                print(json.dumps(dict(completed=len(rows), total=len(paths),
                    seconds=round(time.monotonic()-start, 1))), flush=True)
    result = dict(format="rikui-preparation-storage-measurement-v1", resolution=resolution,
                  files=rows, geometryBytes=sum(r["bytes"] for r in rows),
                  compressedGeometryBytes=sum(r["compressedBytes"] for r in rows),
                  seconds=round(time.monotonic()-start, 1),
                  limitation="Storage round trips over current retained inputs; not a cold installer run.")
    target = Path(args.output)
    with target.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, sort_keys=True, indent=2)
    print(json.dumps({k:v for k,v in result.items() if k not in ("resolution","files")}), flush=True)


if __name__ == "__main__":
    main()
