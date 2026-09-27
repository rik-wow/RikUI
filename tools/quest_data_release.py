#!/usr/bin/env python3
"""Publish validated data in a private GitHub repository; never executes artifact code."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from export_forever import digest


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def output(*args):
    return run(*args, capture_output=True, text=True).stdout.strip()


def validate(dist):
    receipt = json.loads((dist / "latest.json").read_text())
    if not re.fullmatch(r"quest-data-[0-9a-f]{24}", receipt.get("tag", "")):
        raise ValueError("invalid release tag")
    actual = digest(dist / "quest-data.zip")
    if actual != receipt.get("archiveSHA256") or (dist / "SHA256SUMS").read_text().strip() != actual + "  quest-data.zip":
        raise ValueError("release checksum mismatch")
    return receipt


def release_exists(repo, tag):
    # Listing distinguishes a missing release from an authentication/network failure.
    pages = json.loads(output("gh", "api", "--paginate", "--slurp", "repos/" + repo + "/releases"))
    return next((row for page in pages for row in page if row["tag_name"] == tag), None)


def publish(repo, dist):
    if repo != "rik-wow/quest-data":
        raise ValueError("publisher is restricted to rik-wow/quest-data")
    if output("gh", "api", "repos/" + repo, "--jq", ".private") != "true":
        raise ValueError("generated data publication requires a private repository")
    receipt = validate(dist)
    tag = receipt["tag"]
    existing = release_exists(repo, tag)
    if existing and not existing["draft"]:
        with tempfile.TemporaryDirectory() as folder:
            run("gh", "release", "download", tag, "--repo", repo, "--pattern", "SHA256SUMS", "--dir", folder)
            if (Path(folder) / "SHA256SUMS").read_bytes() != (dist / "SHA256SUMS").read_bytes():
                raise ValueError("immutable published release has different bytes")
    else:
        if not existing:
            run("gh", "release", "create", tag, "--repo", repo, "--draft",
                "--target", output("git", "rev-parse", "HEAD"), "--title", tag,
                "--notes-file", dist / "release-notes.md")
        run("gh", "release", "upload", tag, "--repo", repo, "--clobber",
            dist / "quest-data.zip", dist / "SHA256SUMS", dist / "latest.json")
        run("gh", "release", "edit", tag, "--repo", repo, "--draft=false", "--latest")
    checkpoint(dist, tag)


def checkpoint(dist, tag):
    # Checkpoint only after publication succeeds. A failed push can be retried.
    state = Path("state/latest.json")
    state.parent.mkdir(exist_ok=True)
    state.write_bytes((dist / "latest.json").read_bytes())
    run("git", "add", "--", state)
    changed = subprocess.run(["git", "diff", "--cached", "--quiet", "--", str(state)]).returncode
    if changed not in (0, 1):
        raise RuntimeError("Cannot inspect checkpoint diff")
    if changed:
        run("git", "-c", "user.name=github-actions[bot]",
            "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com",
            "commit", "-m", "chore(data): publish " + tag)
        run("git", "push", "origin", "HEAD:main")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="rik-wow/quest-data")
    parser.add_argument("--dist", type=Path, default=Path("dist"))
    args = parser.parse_args()
    publish(args.repo, args.dist)
