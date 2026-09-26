"""Run the host replays against an installed RikUI data set (no shell quoting needed).

Covers the embedded layout end to end: corpus pages under generated/corpus,
road index/catalogs/pages under generated/roads, and the LoadOnDemand patch
packs beside RikUI. Host checks only; native acceptance is separate.

Usage: python tests/replay_installed.py [--addons DIR] [--client-build BUILD] [--lua51 EXE]
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys

DEFAULT_ADDONS = "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns"
DEFAULT_LUA51 = "D:/RikUI-local/QuestieDB/tools/lua-binary/lua.exe"
DEFAULT_BUILD = "1.60.1.70009"
PACKET = "D:/RikUI-local/observations/forever-69913-enUS-9c563e01-native.rikq"
DUN_MOROGH = ["1426", "0.541", "0.448", "0.566", "0.442", "0.531", "0.448", "0.566", "0.442"]


def run(label, command, env, expect):
    print(f"== {label}: {' '.join(command)}", flush=True)
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=1800)
    tail = (result.stdout + result.stderr).strip().splitlines()[-4:]
    print("\n".join(tail), flush=True)
    ok = result.returncode == 0 and any(expect in line for line in result.stdout.splitlines())
    print(f"== {label}: {'OK' if ok else 'FAILED'}", flush=True)
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--addons", default=os.environ.get("RIKUI_ADDONS", DEFAULT_ADDONS))
    parser.add_argument("--client-build", default=os.environ.get("RIKUI_CLIENT_BUILD", DEFAULT_BUILD))
    parser.add_argument("--lua51", default=DEFAULT_LUA51, help="stock Lua 5.1 binary; LuaJIT is used when it is missing")
    parser.add_argument("--packet", default=PACKET)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    lua51 = args.lua51 if Path(args.lua51).is_file() else "luajit"
    env = dict(os.environ, RIKUI_CLIENT_BUILD=args.client_build)
    results = [
        run("corpus pages (stock Lua)", [lua51, "tests/quest-corpus-installed.lua", args.addons], env, "INSTALLED CORPUS"),
        run("network A* vs Dijkstra", ["luajit", "tests/quest-roads-real.lua", args.addons, "0", "10", args.client_build], env, "ROADS_REAL_OK"),
        run("Dun Morogh routes through packs", ["luajit", "tests/quest-roads-navigate-real.lua", args.addons, *DUN_MOROGH], env, "ROADS_NAVIGATE_OK"),
    ]
    if Path(args.packet).is_file():
        results.append(run("adaptive quest 315 (stock Lua)", [lua51, "tests/quest-adaptive-roads.lua", args.addons, args.packet, "315"], env, "ROADS_ADAPTIVE_OK"))
    else:
        print(f"== adaptive replay skipped: packet missing {args.packet}")
    print(f"REPLAYS {'OK' if all(results) else 'FAILED'}: {sum(results)}/{len(results)}")
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
