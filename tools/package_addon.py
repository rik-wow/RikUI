"""Build or verify a deterministic, runtime-only RikUI installation archive."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tests"))
from check_manifest import check_icons, check_manifest

ROOT = "RikUI/"
MANIFEST = ROOT + "package-manifest.json"
MAX_BYTES = 64 * 1024 * 1024
MEDIA_TYPES = {".tga", ".blp", ".ttf", ".otf", ".ogg", ".mp3", ".wav"}
REQUIRED = {
    "RikUI.toc", "Bindings.xml", "LICENSE", "media/LICENSES.md", "media/OFL.txt",
    "media/font.ttf", "media/statusbar.tga", "media/border.tga",
    "media/checked.tga", "media/highlight.tga",
}


def source_path(root, name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or ":" in name or "\\" in name or path.as_posix() != name:
        raise ValueError(f"Unsafe package path: {name}")
    target = root.joinpath(*path.parts)
    if not target.resolve().is_relative_to(root):
        raise ValueError(f"Package input escapes root: {name}")
    current = root
    for part in path.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"Symlink package input: {name}")
    if not target.is_file():
        raise ValueError(f"Missing package input: {name}")
    return target


def inventory(root):
    toc = source_path(root, "RikUI.toc").read_text(encoding="utf-8-sig")
    names = set(REQUIRED)
    names.update(line.strip() for line in toc.splitlines() if line.strip() and not line.lstrip().startswith("#"))
    names.update(path.relative_to(root).as_posix() for path in (root / "media").rglob("*")
                 if path.is_file() and path.suffix.lower() in MEDIA_TYPES)
    paths = {name: source_path(root, name) for name in sorted(names)}
    problems = check_manifest(root) + check_icons(root)
    if problems:
        raise ValueError("\n".join(problems))
    if sum(path.stat().st_size for path in paths.values()) > MAX_BYTES:
        raise ValueError("Package inputs exceed the size limit")
    version = next((line.partition(":")[2].strip() for line in toc.splitlines()
                    if line.startswith("## Version:")), None)
    if not version:
        raise ValueError("TOC version is missing")
    return paths, version


def payload(root):
    paths, version = inventory(root)
    files = {ROOT + name: path.read_bytes() for name, path in paths.items()}
    manifest = {"format": 1, "version": version, "files": {
        name: {"bytes": len(files[ROOT + name]), "sha256": hashlib.sha256(files[ROOT + name]).hexdigest()}
        for name in paths
    }}
    files[MANIFEST] = (json.dumps(manifest, sort_keys=True, indent=2) + "\n").encode("utf-8")
    return files


def verify(output):
    output = Path(output)
    with zipfile.ZipFile(output) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or MANIFEST not in names or len(names) > 4096:
            raise ValueError("Invalid archive inventory")
        if sum(info.file_size for info in archive.infolist()) > MAX_BYTES:
            raise ValueError("Archive exceeds the size limit")
        for name in names:
            path = PurePosixPath(name)
            if not name.startswith(ROOT) or ".." in path.parts or "\\" in name or ":" in name:
                raise ValueError("Unsafe archive member")
        manifest = json.loads(archive.read(MANIFEST))
        if not isinstance(manifest, dict) or manifest.get("format") != 1 or not isinstance(manifest.get("files"), dict):
            raise ValueError("Unsupported package manifest")
        expected = {ROOT + name for name in manifest["files"]}
        if set(names) != expected | {MANIFEST}:
            raise ValueError("Archive inventory differs from manifest")
        for name, entry in manifest["files"].items():
            data = archive.read(ROOT + name)
            if not isinstance(entry, dict) or entry.get("bytes") != len(data) or entry.get("sha256") != hashlib.sha256(data).hexdigest():
                raise ValueError(f"Archive content mismatch: {name}")
    return {"files": len(expected), "bytes": output.stat().st_size,
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "version": manifest.get("version")}


def build(root, output):
    root, output = Path(root).resolve(), Path(output).absolute()
    if output.suffix.lower() != ".zip" or output.is_symlink():
        raise ValueError("Output must be a regular .zip archive")
    resolved = output.resolve()
    if resolved.is_relative_to(root) and resolved.relative_to(root).parts[0] in {"src", "data", "presets", "media", "libs"}:
        raise ValueError("Output must be outside runtime input directories")
    files = payload(root)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".zip", delete=False) as stream:
            temporary = Path(stream.name)
            with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_STORED) as archive:
                for name, data in sorted(files.items()):
                    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, data)
            stream.flush()
            os.fsync(stream.fileno())
        result = verify(temporary)
        os.replace(temporary, output)
        return result
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=PROJECT)
    parser.add_argument("--output", type=Path, default=PROJECT / "dist" / "RikUI.zip")
    parser.add_argument("--verify", type=Path, help="Verify an existing archive instead of building")
    args = parser.parse_args()
    try:
        result = verify(args.verify) if args.verify else build(args.root, args.output)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

