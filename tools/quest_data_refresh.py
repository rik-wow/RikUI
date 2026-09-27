#!/usr/bin/env python3
"""Resolve current inputs, build and validate a private quest-data release."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

import export_forever
import quest_corpus as corpus

SOURCES = {"provider": ("Questie/QuestieDB", "HEAD"),
           "events": ("Questie/Questie", "HEAD"),
           "ui": ("Gethe/wow-ui-source", "refs/heads/forever")}
MAX_DOWNLOAD = 64 * 1024 * 1024


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def output(*args):
    return run(*args, capture_output=True, text=True).stdout.strip()


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "rik-wow-quest-data/1"})
    with urllib.request.urlopen(request, timeout=90) as response:
        value = response.read(MAX_DOWNLOAD + 1)
    if len(value) > MAX_DOWNLOAD:
        raise ValueError("source download exceeds 64 MiB")
    return value


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def resolve_head(repo, ref):
    lines = output("git", "ls-remote", "https://github.com/" + repo + ".git", ref).splitlines()
    if len(lines) != 1 or not re.fullmatch(r"[0-9a-f]{40}", lines[0].split()[0]):
        raise ValueError("Cannot resolve unique upstream head: " + repo)
    return lines[0].split()[0]


def client_version(raw):
    value = raw.decode("utf-8-sig").strip()
    match = re.search(r"(?<!\d)(1\.\d+\.\d+\.\d+)(?!\d)", value)
    if not match:
        raise ValueError("Forever version.txt does not identify a full client version")
    return match[1]


def builder_hash(root):
    digest = hashlib.sha256()
    for folder in ("tools", "src/modules/questplanner", "tests", ".github/workflows"):
        for path in sorted((root / folder).rglob("*")):
            if path.is_file() and path.suffix in {".py", ".lua", ".yml", ".yaml"} and "__pycache__" not in path.parts:
                digest.update(path.relative_to(root).as_posix().encode())
                digest.update(path.read_bytes())
    return digest.hexdigest()


def probe(work, previous, force=False):
    work.mkdir(parents=True, exist_ok=True)
    inputs = {name: {"repository": repo, "revision": resolve_head(repo, ref)}
              for name, (repo, ref) in SOURCES.items()}
    ui = inputs["ui"]
    version = client_version(download("https://raw.githubusercontent.com/" + ui["repository"]
                                      + "/" + ui["revision"] + "/version.txt"))
    csv = download("https://wago.tools/db2/QuestV2/csv?build=" + version)
    index = work / "QuestV2.csv"
    index.write_bytes(csv)
    corpus.load_client_index(index, corpus.sha(csv))
    inputs["client"] = {"build": version, "sha256": corpus.sha(csv)}
    inputs["builderSHA256"] = builder_hash(Path.cwd())
    fingerprint = corpus.sha(corpus.canonical(inputs).encode())
    prior = json.loads(previous.read_text()) if previous.is_file() else {}
    result = {"schemaVersion": 1, "inputs": inputs, "fingerprint": fingerprint,
              "tag": "quest-data-" + fingerprint[:24]}
    write_json(work / "resolution.json", result)
    changed = force or prior.get("fingerprint") != fingerprint
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write("changed=" + str(changed).lower() + "\n")
    print(json.dumps({"changed": changed, **result}, sort_keys=True))
    return changed


def checkout(work, name, source):
    target = work / name
    if target.exists():
        raise ValueError("Source checkout already exists; use a fresh work directory: " + str(target))
    run("git", "init", "--quiet", target)
    run("git", "-C", target, "fetch", "--quiet", "--depth=1",
        "https://github.com/" + source["repository"] + ".git", source["revision"])
    run("git", "-C", target, "checkout", "--quiet", "--detach", "FETCH_HEAD")
    if output("git", "-C", target, "rev-parse", "HEAD") != source["revision"]:
        raise ValueError("upstream checkout differs from resolved revision")
    return target


def check_regression(manifest, coverage, previous):
    if not previous.is_file():
        return
    prior = json.loads(previous.read_text())
    now = {"quests": manifest["counts"]["quests"],
           "mappedObjectives": coverage["questCoverage"]["objectivesWithAreas"],
           "spawns": coverage["waypointCoverage"]["exactSpawns"]}
    for key, count in now.items():
        old = prior.get("coverage", {}).get(key, 0)
        if old and count < old * .95:
            raise ValueError("Coverage fell by more than 5%: " + key + "; preserve last release and review")


def package(folder, destination):
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(folder).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes())


def build(work, dist, previous):
    resolution = json.loads((work / "resolution.json").read_text())
    inputs = resolution["inputs"]
    provider = checkout(work, "provider", inputs["provider"])
    events = checkout(work, "events", inputs["events"])
    export = work / "provider.json"
    export_forever.export_provider(provider, export, Path(__file__).with_name("export_forever.lua"),
                                   revision=inputs["provider"]["revision"], lua_command=shutil.which("lua5.1"))
    folder = work / "corpus"
    manifest = corpus.build(export, folder, client_index=work / "QuestV2.csv",
                            provider_manifest=export.with_suffix(".manifest.json"),
                            event_source_root=events, client_build=inputs["client"]["build"],
                            client_index_sha=inputs["client"]["sha256"],
                            event_revision=inputs["events"]["revision"])
    corpus.verify(folder)
    run("luajit", "tests/quest-corpus-installed.lua", folder)
    coverage = json.loads((folder / "coverage.json").read_text())
    check_regression(manifest, coverage, previous)
    write_release(folder, dist, resolution, manifest, coverage)


def write_release(folder, dist, resolution, manifest, coverage):
    inputs = resolution["inputs"]
    dist.mkdir(parents=True, exist_ok=True)
    package(folder, dist / "quest-data.zip")
    digest = export_forever.digest(dist / "quest-data.zip")
    (dist / "SHA256SUMS").write_text(digest + "  quest-data.zip\n", encoding="utf-8")
    resolution.update({"archiveSHA256": digest, "corpusRevision": manifest["corpusRevision"],
                       "coverage": {"quests": manifest["counts"]["quests"],
                                    "questIDs": manifest["counts"]["compiledQuests"],
                                    "mappedObjectives": coverage["questCoverage"]["objectivesWithAreas"],
                                    "objectives": coverage["questCoverage"]["objectives"],
                                    "spawns": coverage["waypointCoverage"]["exactSpawns"]}})
    write_json(dist / "latest.json", resolution)
    (dist / "release-notes.md").write_text(
        "# Quest data refresh\n\n"
        + "Resolved client: " + inputs["client"]["build"] + "\n\n"
        + "Source and artifact hashes: see latest.json and SHA256SUMS.\n\n"
        + "Full source export, compiler checks and runtime replay passed. "
        + "Missing objectives, phase and floor coverage remain explicit.\n\n"
        + "Private use only; upstream redistribution terms remain unresolved.\n",
        encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("probe", "build"))
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--dist", type=Path, default=Path("dist"))
    parser.add_argument("--previous", type=Path, default=Path("state/latest.json"))
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    if args.command == "probe":
        probe(args.work.resolve(), args.previous, args.force)
    else:
        build(args.work.resolve(), args.dist, args.previous)


if __name__ == "__main__":
    main()
