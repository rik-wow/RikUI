#!/usr/bin/env python3
"""Export a committed, self-contained builder snapshot for rik-wow/quest-data."""
import argparse
import json
from pathlib import Path
import subprocess

TOOLS = ("export_forever.py", "export_forever.lua", "quest_corpus.py", "quest_data_refresh.py",
         "quest_data_release.py", "update_quest_data.py")
TESTS = ("test_quest_corpus.py", "test_quest_data_ci.py", "quest-corpus-installed.lua", "generated_stub.lua")


def git(*args):
    return subprocess.check_output(["git", *args])


def export(destination, revision):
    if destination.exists() and any(destination.iterdir()):
        raise ValueError("export destination must be empty")
    commit = git("rev-parse", "--verify", revision + "^{commit}").decode().strip()
    paths = ["tools/" + name for name in TOOLS] + ["tests/" + name for name in TESTS]
    runtime = git("ls-tree", "-r", "--name-only", commit, "--", "src/modules/questplanner").decode().splitlines()
    paths += [path for path in runtime if path.endswith(".lua")]
    mapping = {path: path for path in paths}
    mapping["automation/quest-data/refresh.yml"] = ".github/workflows/refresh.yml"
    mapping["automation/quest-data/README.md"] = "README.md"
    for source, target in mapping.items():
        path = destination / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(git("show", commit + ":" + source))
    (destination / ".gitignore").write_text("dist/\n__pycache__/\n*.pyc\n", encoding="utf-8")
    (destination / "BUILDER_SOURCE.json").write_text(
        json.dumps({"repository": "AlrikOlson/wowforever-classicui", "commit": commit,
                    "files": mapping}, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print("Exported " + str(len(mapping)) + " builder files from " + commit)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--revision", default="HEAD")
    args = parser.parse_args()
    export(args.output.resolve(), args.revision)
