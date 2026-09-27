#!/usr/bin/env python3
"""Download and verify a private quest-data release, then install with existing ownership checks."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

import quest_corpus as corpus
from export_forever import digest


def unpack(archive, destination):
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        names = [entry.filename for entry in entries]
        if len(names) > 2000 or len(set(names)) != len(names):
            raise ValueError("invalid release archive inventory")
        if sum(entry.file_size for entry in entries) > 1024 ** 3:
            raise ValueError("release archive exceeds 1 GiB")
        for entry in entries:
            parts = entry.filename.split("/")
            if (entry.is_dir() or any(part in ("", ".", "..") for part in parts)
                    or any("\\" in part or ":" in part for part in parts)
                    or (entry.external_attr >> 16) & 0o170000 == 0o120000):
                raise ValueError("unsafe archive path: " + entry.filename)
            path = destination.joinpath(*parts)
            path.parent.mkdir(parents=True, exist_ok=True)
            with source.open(entry) as incoming, path.open("wb") as target:
                shutil.copyfileobj(incoming, target)


def install_release(rikui, tag=None, repo="rik-wow/quest-data"):
    if repo != "rik-wow/quest-data" or tag and not re.fullmatch(r"quest-data-[0-9a-f]{24}", tag):
        raise ValueError("unsupported repository or release tag")
    with tempfile.TemporaryDirectory(prefix="rikui-quest-update-") as temporary:
        root = Path(temporary)
        command = ["gh", "release", "download"]
        if tag:
            command.append(tag)
        command += ["--repo", repo, "--pattern", "quest-data.zip", "--pattern", "SHA256SUMS", "--dir", str(root)]
        subprocess.run(command, check=True)
        expected = (root / "SHA256SUMS").read_text().strip()
        if expected != digest(root / "quest-data.zip") + "  quest-data.zip":
            raise ValueError("release archive checksum mismatch")
        folder = root / "corpus"
        unpack(root / "quest-data.zip", folder)
        manifest = corpus.verify(folder)
        corpus.install(folder, rikui)
        result = corpus.verify_installed(folder, rikui)
        print("Installed " + manifest["corpusRevision"] + "; fully restart WoW. " + str(result))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rikui", type=Path, required=True)
    parser.add_argument("--tag", help="Install an older version for rollback; defaults to latest")
    args = parser.parse_args()
    install_release(args.rikui, args.tag)
