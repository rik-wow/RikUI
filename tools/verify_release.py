"""Verify a BigWigs ZIP against this checkout before publishing it."""
import argparse
import hashlib
from pathlib import Path
import stat
import zipfile

from package_addon import (
    MAX_BYTES, PROJECT, ROOT, install_path, inventory, toc_version, validate_version,
)


def normalized(data, name):
    if name == "LICENSE" or Path(name).suffix in {".lua", ".toc", ".xml", ".md", ".txt"}:
        return data.replace(b"\r\n", b"\n")
    return data


def verify_release(root, output, version):
    validate_version(version.removeprefix("v"))
    paths, source_version = inventory(Path(root).resolve())
    expected = {ROOT + name for name in paths} | {ROOT + "CHANGELOG.md"}
    with zipfile.ZipFile(output) as archive:
        members = archive.infolist()
        names = [member.filename for member in members]
        if len(names) != len({name.casefold() for name in names}):
            raise ValueError("Duplicate release member")
        if sum(member.file_size for member in members) > MAX_BYTES:
            raise ValueError("Release exceeds size limit")
        files = set()
        for member in members:
            name = member.filename
            install_path(name.rstrip("/") if member.is_dir() else name)
            if not name.startswith(ROOT) or member.flag_bits & 1:
                raise ValueError("Unsafe release member")
            mode = stat.S_IFMT(member.external_attr >> 16)
            if mode not in (0, stat.S_IFDIR if member.is_dir() else stat.S_IFREG):
                raise ValueError("Non-regular release member")
            if member.is_dir():
                if not any(path.startswith(name) for path in expected):
                    raise ValueError("Unexpected release directory")
            else:
                files.add(name)
        if files != expected:
            raise ValueError(f"Release inventory mismatch: missing={sorted(expected - files)}, extra={sorted(files - expected)}")
        verify_payload(archive, paths, source_version, version)
    return {"files": len(expected), "version": version,
            "sha256": hashlib.sha256(Path(output).read_bytes()).hexdigest()}


def verify_payload(archive, paths, source_version, version):
    for name, path in paths.items():
        source = path.read_bytes()
        actual = archive.read(ROOT + name)
        if name == "RikUI.toc":
            if toc_version(actual.decode("utf-8-sig")) != version:
                raise ValueError("Release TOC version does not match tag")
            source = source.replace(
                ("## Version: " + source_version).encode(),
                ("## Version: " + version).encode(), 1)
        if normalized(actual, name) != normalized(source, name):
            raise ValueError(f"Release content mismatch: {name}")
    if not archive.read(ROOT + "CHANGELOG.md").strip():
        raise ValueError("Empty release changelog")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--root", type=Path, default=PROJECT)
    args = parser.parse_args()
    try:
        print(verify_release(args.root, args.archive, args.version))
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
