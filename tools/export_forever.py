#!/usr/bin/env python3
"""Export resolved Forever provider data with stock Lua 5.1 and an input manifest.

Install the isolated build dependency with: python -m pip install lupa==2.8
Example:
  python export_forever.py --source-root /path/to/QuestieDB --output provider.json
The adjacent export_forever.lua owns extraction. --lua-exporter can override its
location. No QuestieDB source or generated TOC is modified. --reuse validates both
input and output hashes before accepting an existing export.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
from typing import Any

SUPPORTED_REVISION = "365537a340473291f5af3b7a53a5eca94e2a5f1a"
LUPA_VERSION = "2.8"
EXPECTED_COUNTS = {"Quest": 4257, "Npc": 10122, "Item": 14899, "Object": 6666}


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def verify_checkout(root: Path, revision: str = SUPPORTED_REVISION) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", revision) or git(root, "rev-parse", "HEAD") != revision:
        raise ValueError("QuestieDB revision differs from the resolved source revision")
    if git(root, "status", "--porcelain=v1", "--untracked-files=no"):
        raise ValueError("QuestieDB has tracked modifications; a clean pinned checkout is required")


def source_manifest(root: Path) -> list[dict[str, Any]]:
    """Hash the complete Forever input family and the runtime/exporter machinery."""
    paths = git(root, "ls-files", "-z").split("\0")
    rows = []
    for relative in sorted(filter(None, paths)):
        role = None
        if relative.startswith("data/Forever/"):
            role = "raw-and-coordinate-provenance"
        elif relative.startswith("src/corrections/Forever/"):
            role = "owned-corrections"
        elif relative.startswith("support/Forever/"):
            role = "owned-support"
        elif relative.startswith("l10n/Forever/"):
            role = "owned-localization"
        elif relative.startswith(("generator/", "emulator/")) and relative.endswith(".lua"):
            role = "provider-loader"
        elif relative.startswith("src/") and relative.endswith(".lua"):
            # Other flavor correction/data providers are never consumed. Shared
            # schema, registry, codecs, and dispatch code are implementation inputs.
            if relative.startswith("src/corrections/"):
                suffix = relative.removeprefix("src/corrections/")
                if "/" in suffix and not suffix.startswith(("enum/", "scopes/")):
                    continue
            if relative.startswith("src/flavors/") and relative != "src/flavors/Forever.lua":
                continue
            role = "provider-runtime"
        elif relative in {"data/_end.lua", "QuestieDB.toc", "PROVENANCE.md", "docs/forever-data.md",
                          "docs/forever-map-override-audit.md"}:
            role = "provider-contract-and-provenance"
        if role:
            path = root / relative
            rows.append({"path": relative, "bytes": path.stat().st_size,
                         "sha256": digest(path), "role": role})
    assert sum(row["role"] == "owned-localization" for row in rows) == 36
    assert all(any(row["path"] == f"data/Forever/forever{name}DB.lua" for row in rows)
               for name in ("Quest", "Npc", "Item", "Object"))
    return rows


def stable_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def replace_bytes(path: Path, data: bytes) -> None:
    if path.exists() and path.read_bytes() == data:
        return
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    candidate = Path(temporary)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(candidate, path)
    finally:
        candidate.unlink(missing_ok=True)


def export_provider(source_root: Path, output: Path, lua_exporter: Path,
                    manifest_path: Path | None = None, reuse: bool = False, revision: str = SUPPORTED_REVISION) -> dict[str, Any]:
    root, output, lua_exporter = source_root.resolve(), output.resolve(), lua_exporter.resolve()
    manifest_path = (manifest_path or output.with_suffix(".manifest.json")).resolve()
    if output == manifest_path:
        raise ValueError("Export and manifest paths must differ")
    if output == lua_exporter or manifest_path == lua_exporter:
        raise ValueError("Output cannot replace the exporter")
    # Protect the pinned provider from accidental output selection.
    if output.is_relative_to(root) or manifest_path.is_relative_to(root):
        raise ValueError("Export and manifest must be outside the provider checkout")
    verify_checkout(root, revision)
    inputs = source_manifest(root)
    header = {"schemaVersion": 1, "repository": "https://github.com/Questie/QuestieDB",
              "revision": revision, "flavor": "Forever",
              "luaImplementation": "stock Lua 5.1 via lupa.lua51", "lupaVersion": LUPA_VERSION,
              "luaExporterSha256": digest(lua_exporter), "wrapperSha256": digest(Path(__file__)), "inputs": inputs}
    if reuse and output.is_file() and manifest_path.is_file():
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
        if (all(previous.get(key) == value for key, value in header.items())
                and previous.get("exportSha256") == digest(output)):
            return previous
    if importlib.metadata.version("lupa") != LUPA_VERSION:
        raise RuntimeError(f"Reproducible export requires lupa=={LUPA_VERSION}")
    from lupa.lua51 import LuaRuntime
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=output.name + ".", suffix=".candidate", dir=output.parent)
    os.close(descriptor)
    candidate = Path(temporary)
    candidate.unlink()
    initial_cwd = Path.cwd()
    try:
        lua = LuaRuntime()
        lua.globals().arg = lua.table_from({0: str(lua_exporter), 1: str(candidate), 2: revision})
        os.chdir(root)
        try:
            lua.execute("dofile(arg[0])")
        finally:
            os.chdir(initial_cwd)
        with candidate.open(encoding="utf-8") as stream:
            data = json.load(stream)
        if (set(data["counts"]) != set(EXPECTED_COUNTS) or any(not isinstance(n, int) or n <= 0 for n in data["counts"].values())
                or len(data["variants"]) != 18):
            raise ValueError("Incomplete Forever entity/persona inventory")
        if data["provider"]["revision"] != revision:
            raise ValueError("Unexpected export revision")
        exported_paths = set(data["provider"]["sourceFiles"])
        inventoried = {item["path"] for item in inputs}
        if exported_paths - inventoried:
            raise ValueError("Uninventoried source inputs: " + ", ".join(sorted(exported_paths - inventoried)))
        verify_checkout(root, revision)
        if source_manifest(root) != inputs:
            raise ValueError("Provider inputs changed during extraction")
        manifest = {**header, "exportSha256": digest(candidate), "exportBytes": candidate.stat().st_size,
                    "counts": data["counts"], "rawCounts": data["provider"]["rawCounts"],
                    "personaCount": len(data["variants"]), "localizationStats": data["localizationStats"]}
        if output.exists() and digest(output) == manifest["exportSha256"]:
            candidate.unlink()
        else:
            os.replace(candidate, output)
        replace_bytes(manifest_path, stable_json(manifest))
        return manifest
    finally:
        os.chdir(initial_cwd)
        candidate.unlink(missing_ok=True)
        Path(str(candidate) + ".tmp").unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--lua-exporter", type=Path, default=Path(__file__).with_suffix(".lua"))
    parser.add_argument("--reuse", action="store_true")
    parser.add_argument("--revision", default=SUPPORTED_REVISION, help="Resolved provider HEAD for this acquisition")
    options = parser.parse_args()
    result = export_provider(options.source_root, options.output, options.lua_exporter,
                             options.manifest, options.reuse, options.revision)
    print(json.dumps({"exportSha256": result["exportSha256"], "counts": result["counts"],
                      "inputFiles": len(result["inputs"]), "personaCount": result["personaCount"]}, sort_keys=True))


if __name__ == "__main__":
    main()


