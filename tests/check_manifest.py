"""Check runtime and icon inventories, then compile Lua sources without a shell."""
from pathlib import Path, PurePosixPath
import argparse
import re
import subprocess
import sys

GENERATED_INCLUDE = "generated/index.xml"


def check_manifest(root):
    failures = []
    toc = root / "RikUI.toc"
    if not toc.is_file():
        return ["RikUI.toc is missing"]
    expected = {
        path.relative_to(root).as_posix()
        for directory in ("src", "data", "presets")
        for path in (root / directory).rglob("*")
        if path.is_file() and path.suffix.casefold() == ".lua"
    }
    listed, seen = set(), {}
    for number, raw in enumerate(toc.read_text(encoding="utf-8-sig").splitlines(), 1):
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        location = f"RikUI.toc:{number}"
        path = PurePosixPath(entry)
        invalid = (
            "\\" in entry or ":" in entry or path.is_absolute()
            or ".." in path.parts or path.as_posix() != entry
            or (path.suffix != ".lua" and entry != GENERATED_INCLUDE)
        )
        if invalid:
            failures.append(f"{location}: invalid runtime path: {entry}")
            continue
        folded = entry.casefold()
        if folded in seen:
            failures.append(f"{location}: duplicate of line {seen[folded]}: {entry}")
        else:
            seen[folded] = number
        listed.add(entry)
        target = root.joinpath(*path.parts)
        try:
            target.resolve().relative_to(root)
        except ValueError:
            failures.append(f"{location}: path escapes addon root: {entry}")
            continue
        if not target.is_file():
            failures.append(f"{location}: missing file: {entry}")
        elif entry not in expected and entry != GENERATED_INCLUDE:
            # The one XML entry is the committed include for installer-written data.
            failures.append(f"{location}: path is outside runtime inventory or has wrong case: {entry}")
    # BigWigs strips a trailing CR at EOF; reject this before a release is tagged.
    for entry in sorted(expected):
        if (root / entry).read_bytes().endswith(b"\r"):
            failures.append(f"Runtime file ends in a bare carriage return; finish with LF or CRLF: {entry}")
    for entry in sorted(expected - listed):
        failures.append(f"Runtime file omitted from TOC: {entry}")
    for path in sorted(root.iterdir()):
        if path.is_file() and path.suffix.casefold() == ".lua":
            failures.append(f"Runtime Lua remains at addon root: {path.name}")
    if not expected:
        failures.append("Runtime inventory is empty")
    return failures


def check_icons(root):
    source = root / "src/ui/media.lua"
    if not source.is_file():
        return ["Icon registry source is missing"]
    text = source.read_text(encoding="utf-8-sig")
    match = re.search(r"\blocal\s+NAMES\s*=\s*\{([^}]*)\}", text, re.S)
    if not match:
        return ["Icon registry NAMES table is missing"]
    body = match.group(1)
    names = re.findall(r'"([a-z][a-z0-9-]*)"', body)
    remainder = re.sub(r'"[a-z][a-z0-9-]*"|[\s,]+', "", body)
    if remainder or not names:
        return ["Icon registry must be a nonempty literal list of lowercase names"]
    failures = []
    if len(names) != len(set(names)):
        failures.append("Icon registry contains duplicate names")
    directory = root / "media/icons"
    if not directory.is_dir():
        return failures + ["Icon asset directory is missing"]
    expected = {name + extension for name in names for extension in (".svg", ".tga")}
    actual = {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file() and path.suffix.casefold() in {".svg", ".tga"}
    }
    for name in sorted(expected - actual):
        failures.append(f"Declared icon asset is missing: {name}")
    for name in sorted(actual - expected):
        failures.append(f"Undeclared or noncanonical icon asset: {name}")
    return failures


def check_syntax(root):
    paths = sorted(
        path.relative_to(root).as_posix()
        for directory in ("src", "data", "presets", "RikProbe", "tests")
        for path in (root / directory).rglob("*")
        if path.is_file() and path.suffix.casefold() == ".lua"
    )
    try:
        result = subprocess.run(
            ["luajit", "-e", 'for path in io.lines() do assert(loadfile(path)) end'],
            cwd=root, input="\n".join(paths) + "\n", text=True, capture_output=True,
            timeout=30, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return [f"Could not run LuaJIT syntax check: {error}"]
    if result.returncode:
        return [f"Lua syntax check failed:\n{result.stdout}{result.stderr}"]
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    root = parser.parse_args().root.resolve()
    failures = check_manifest(root) + check_icons(root)
    if not failures:
        failures = check_syntax(root)
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print("OK: TOC and icon inventories match; all Lua sources compile")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
