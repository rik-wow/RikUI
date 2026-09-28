"""Build or verify a deterministic, runtime-only RikUI installation archive."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path, PurePosixPath
import sys
import stat
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tests"))
from check_manifest import GENERATED_INCLUDE, check_icons, check_manifest

ROOT = "RikUI/"
MANIFEST = ROOT + "package-manifest.json"
MAX_BYTES = 64 * 1024 * 1024
MEDIA_TYPES = {".tga", ".blp", ".ttf", ".otf", ".ogg", ".mp3", ".wav"}
REQUIRED = {
    "RikUI.toc", "Bindings.xml", "LICENSE", "media/LICENSES.md", "media/OFL.txt",
    "media/font.ttf", "media/statusbar.tga", "media/border.tga",
    "media/ring.tga", "media/highlight.tga",
}


def install_path(name):
    path = PurePosixPath(name)
    reserved = {"CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"}
    reserved.update(prefix + digit for prefix in ("COM", "LPT") for digit in "123456789¹²³")
    if not name or path.is_absolute() or path.as_posix() != name or ".." in path.parts:
        raise ValueError(f"Unsafe package path: {name}")
    for part in path.parts:
        if (part.endswith((".", " ")) or part.split(".")[0].upper() in reserved
                or any(ord(char) < 32 or char in '<>:"\\\\|?*' for char in part)):
            raise ValueError(f"Unsafe package path: {name}")
    return path


def source_path(root, name):
    path = install_path(name)
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


def validate_version(version):
    if not isinstance(version, str) or len(version) > 64:
        raise ValueError("Version must be a semantic version of at most 64 characters")
    match = re.fullmatch(
        r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
        r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
        r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?", version)
    if not match or (match[4] and any(
            part.isdigit() and len(part) > 1 and part.startswith("0") for part in match[4].split("."))):
        raise ValueError("Invalid semantic version")
    return version


def toc_version(toc):
    versions = [line.partition(":")[2].strip() for line in toc.splitlines()
                if line.startswith("## Version:")]
    if len(versions) != 1 or not versions[0]:
        raise ValueError("TOC must contain exactly one nonempty version")
    return versions[0]


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
    return paths, toc_version(toc)


def payload(root, version=None):
    paths, source_version = inventory(root)
    if source_version == "@project-version@" and version is None:
        raise ValueError("Unstamped checkout: pass --version (for example 0.1.0-dev) to build locally")
    selected_version = validate_version(source_version if version is None else version)
    files = {ROOT + name: path.read_bytes() for name, path in paths.items()}
    if version is not None:
        toc = files[ROOT + "RikUI.toc"].decode("utf-8")
        toc, count = re.subn(r"(?m)^(\ufeff?## Version:)[^\r\n]*",
                            lambda match: match[1] + " " + selected_version, toc)
        if count != 1:
            raise ValueError("Cannot stamp TOC version")
        files[ROOT + "RikUI.toc"] = toc.encode("utf-8")
    version = selected_version
    manifest = {"format": 1, "version": version, "files": {
        name: {"bytes": len(files[ROOT + name]), "sha256": hashlib.sha256(files[ROOT + name]).hexdigest()}
        for name in paths
    }}
    files[MANIFEST] = (json.dumps(manifest, sort_keys=True, indent=2) + "\n").encode("utf-8")
    return files


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate package manifest key: {key}")
        result[key] = value
    return result


def verify_members(archive):
    names = archive.namelist()
    folded = {name.casefold() for name in names}
    if len(names) != len(folded) or MANIFEST not in names or len(names) > 4096:
        raise ValueError("Invalid archive inventory")
    if sum(info.file_size for info in archive.infolist()) > MAX_BYTES:
        raise ValueError("Archive exceeds the size limit")
    for info in archive.infolist():
        path = install_path(info.filename)
        mode = stat.S_IFMT(info.external_attr >> 16)
        if not info.filename.startswith(ROOT) or mode not in (0, stat.S_IFREG) or info.is_dir() or info.flag_bits & 1:
            raise ValueError("Unsafe archive member")
        if any(parent.as_posix().casefold() in folded for parent in path.parents):
            raise ValueError("Archive file conflicts with a directory")
    return set(names)


def verify_inventory(archive, names):
    manifest = json.loads(archive.read(MANIFEST), object_pairs_hook=unique_object)
    if (not isinstance(manifest, dict) or type(manifest.get("format")) is not int
            or manifest["format"] != 1 or not isinstance(manifest.get("files"), dict)):
        raise ValueError("Unsupported package manifest")
    files = manifest["files"]
    if set(names) != {ROOT + name for name in files} | {MANIFEST} or not REQUIRED <= files.keys():
        raise ValueError("Archive inventory differs from required manifest")
    toc = archive.read(ROOT + "RikUI.toc").decode("utf-8-sig")
    if validate_version(manifest.get("version")) != validate_version(toc_version(toc)):
        raise ValueError("Archive version differs from TOC")
    listed = [line.strip() for line in toc.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if not listed or len(listed) != len({name.casefold() for name in listed}):
        raise ValueError("Invalid archive TOC inventory")
    for name in listed:
        path = install_path(name)
        runtime = path.suffix == ".lua" and path.parts[0] in {"src", "data", "presets"}
        if not (runtime or name == GENERATED_INCLUDE) or name not in files:
            raise ValueError(f"Missing or invalid TOC source: {name}")
    for name in files:
        path = install_path(name)
        if name not in REQUIRED and name not in listed and not (path.parts[0] == "media" and path.suffix.lower() in MEDIA_TYPES):
            raise ValueError(f"Unexpected archive payload: {name}")
    return manifest


def verify_contents(archive, manifest):
    for name, entry in manifest["files"].items():
        if (not isinstance(entry, dict) or type(entry.get("bytes")) is not int
                or entry["bytes"] < 0 or not isinstance(entry.get("sha256"), str)):
            raise ValueError(f"Invalid archive file metadata: {name}")
        data = archive.read(ROOT + name)
        if entry["bytes"] != len(data) or entry["sha256"] != hashlib.sha256(data).hexdigest():
            raise ValueError(f"Archive content mismatch: {name}")


def verify(output):
    output = Path(output)
    with zipfile.ZipFile(output) as archive:
        names = verify_members(archive)
        manifest = verify_inventory(archive, names)
        verify_contents(archive, manifest)
    return {"files": len(manifest["files"]), "bytes": output.stat().st_size,
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "version": manifest.get("version")}


def build(root, output, version=None):
    root, output = Path(root).resolve(), Path(output).absolute()
    if output.suffix.lower() != ".zip" or output.is_symlink():
        raise ValueError("Output must be a regular .zip archive")
    resolved = output.resolve()
    if resolved.is_relative_to(root) and resolved.relative_to(root).parts[0] in {"src", "data", "presets", "media", "libs"}:
        raise ValueError("Output must be outside runtime input directories")
    files = payload(root, version)
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
    parser.add_argument("--version", help="Stamp a semantic version into the archive without changing source")
    args = parser.parse_args()
    if args.verify and args.version is not None:
        parser.error("--version cannot be combined with --verify")
    try:
        result = verify(args.verify) if args.verify else build(args.root, args.output, args.version)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

