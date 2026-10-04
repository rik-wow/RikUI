"""Bounded current Forever discovery. No historical build or installation defaults.

This module resolves metadata only. A resolution is not a compatibility,
acquisition, corpus, navigation, or installation acceptance receipt.
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import urllib.parse
import urllib.request

MAX_METADATA_BYTES = 4 * 1024 * 1024
VERSION = re.compile(r"1\.[0-9]+\.[0-9]+\.[0-9]+")
REVISION = re.compile(r"[0-9a-f]{40}")
CONFIG = re.compile(r"[0-9a-f]{32}")
SOURCES = {
    "ui": ("Gethe/wow-ui-source", "forever"),
    "provider": ("Questie/QuestieDB", None),
    "events": ("Questie/Questie", None),
    "schemas": ("wowdev/WoWDBDefs", None),
}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      allow_nan=False, ensure_ascii=True).encode("utf-8")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def regular(path):
    """Reject links/reparse points in the selected path and every ancestor."""
    path = Path(os.path.abspath(path))
    for part in reversed((path, *path.parents)):
        info = part.lstat()
        if (stat.S_ISLNK(info.st_mode)
                or getattr(info, "st_file_attributes", 0) & 0x400):
            raise ValueError("Linked installation/input path: " + str(part))
    if not path.is_file():
        raise ValueError("Expected a regular input file: " + str(path))
    return path


def read_metadata(path):
    path = regular(path)
    if not 0 < path.stat().st_size <= MAX_METADATA_BYTES:
        raise ValueError("Metadata exceeds supported byte bound")
    with path.open("rb") as stream:
        raw = stream.read(MAX_METADATA_BYTES + 1)
    if len(raw) > MAX_METADATA_BYTES:
        raise ValueError("Metadata grew beyond supported byte bound")
    return raw


def download(url):
    """HTTPS publisher metadata only; downloads remain bounded on redirects."""
    def allowed(value):
        parsed = urllib.parse.urlsplit(value)
        return (parsed.scheme == "https"
                and parsed.hostname in {"api.github.com", "raw.githubusercontent.com", "github.com"}
                and not parsed.username and not parsed.password)

    class Redirects(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, fp, code, msg, headers, target):
            if not allowed(target):
                raise ValueError("Unexpected publisher metadata redirect")
            return super().redirect_request(request, fp, code, msg, headers, target)

    if not allowed(url):
        raise ValueError("Unexpected publisher metadata URL")
    request = urllib.request.Request(url, headers={
        "User-Agent": "RikUI-current-inputs/1",
        "Accept": "application/vnd.github+json",
    })
    with urllib.request.build_opener(Redirects()).open(request, timeout=30) as response:
        raw = response.read(MAX_METADATA_BYTES + 1)
    if not raw or len(raw) > MAX_METADATA_BYTES:
        raise ValueError("Publisher metadata exceeds supported byte bound")
    return raw



IMMUTABLE_METADATA = {}


def immutable_metadata(url, fetch):
    # Only content-addressed metadata is reusable without another request.
    if fetch is not download:
        return fetch(url)
    if url not in IMMUTABLE_METADATA:
        IMMUTABLE_METADATA[url] = fetch(url)
    return IMMUTABLE_METADATA[url]


def advertised_refs(raw):
    """Bounded, nonexecuting Git smart-HTTP v0 reference advertisement parser."""
    if not 0 < len(raw) <= MAX_METADATA_BYTES:
        raise ValueError("Reference advertisement byte bound")
    packets, offset = [], 0
    while offset < len(raw):
        if offset + 4 > len(raw):
            raise ValueError("Truncated reference packet")
        try:
            size = int(raw[offset:offset+4], 16)
        except ValueError:
            raise ValueError("Invalid reference packet length") from None
        offset += 4
        if size == 0:
            continue
        if not 4 <= size <= 65520 or offset + size - 4 > len(raw):
            raise ValueError("Reference packet bound")
        packets.append(raw[offset:offset+size-4].decode("utf-8"))
        offset += size - 4
        if len(packets) > 32768:
            raise ValueError("Reference count bound")
    if not packets or packets[0] != "# service=git-upload-pack\n":
        raise ValueError("Unsupported publisher reference protocol")
    refs, default = {}, None
    for packet in packets[1:]:
        value, _, capabilities = packet.rstrip("\n").partition("\0")
        revision, separator, name = value.partition(" ")
        if not separator or not REVISION.fullmatch(revision) or name in refs:
            raise ValueError("Invalid or duplicate publisher reference")
        refs[name] = revision
        for capability in capabilities.split():
            if capability.startswith("symref=HEAD:"):
                if default is not None:
                    raise ValueError("Duplicate default reference")
                default = capability[len("symref=HEAD:"):]
    if not default or not default.startswith("refs/heads/") or refs.get(default) != refs.get("HEAD"):
        raise ValueError("Publisher default reference is not a unique advertised branch")
    return refs, default[len("refs/heads/"):]


def resolve_source(repository, branch, fetch=download):
    """Discover current advertised heads without requiring Git or an API token."""
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid publisher repository")
    refs, default = advertised_refs(fetch("https://github.com/" + repository +
                                         ".git/info/refs?service=git-upload-pack"))
    branch = branch or default
    if not isinstance(branch, str) or not branch or len(branch) > 256:
        raise ValueError("Invalid publisher branch")
    revision = refs.get("refs/heads/" + branch)
    if not revision:
        raise ValueError("Publisher branch is not advertised")
    commit = json.loads(immutable_metadata("https://api.github.com/repos/" + repository +
                                          "/commits/" + revision, fetch))
    if commit.get("sha") != revision:
        raise ValueError("Publisher commit and advertised head disagree")
    return {"repository": repository, "branch": branch, "revision": revision,
            "message": commit["commit"]["message"]}


def resolve_upstreams(fetch=download):
    sources = {name: resolve_source(repo, branch, fetch)
               for name, (repo, branch) in SOURCES.items()}
    ui = sources["ui"]
    raw = immutable_metadata("https://raw.githubusercontent.com/" + ui["repository"] + "/"
                + ui["revision"] + "/version.txt", fetch)
    build = raw.decode("utf-8-sig").strip()
    if not VERSION.fullmatch(build):
        raise ValueError("Forever version.txt lacks an exact full version")
    match = re.fullmatch(r"(1\.[0-9]+\.[0-9]+) \(([0-9]+)\)",
                         ui["message"].splitlines()[0])
    if not match or build != match[1] + "." + match[2]:
        raise ValueError("Forever commit message and version.txt disagree")
    ui["versionSHA256"] = sha(raw)
    return {"build": build, "sources": sources}


def build_rows(raw):
    lines = raw.decode("utf-8-sig").splitlines()
    if len(lines) < 2 or len(lines) > 256:
        raise ValueError("Unsupported .build.info row count")
    headings = [value.split("!", 1)[0] for value in lines[0].split("|")]
    required = {"Active", "Build Key", "CDN Key", "Version", "Product"}
    if len(headings) != len(set(headings)) or not required <= set(headings):
        raise ValueError("Unsupported .build.info schema")
    rows = []
    for line in lines[1:]:
        if not line:
            continue
        values = line.split("|")
        if len(values) != len(headings):
            raise ValueError("Malformed .build.info row")
        row = dict(zip(headings, values))
        if row["Active"] not in {"0", "1"}:
            raise ValueError("Invalid .build.info active flag")
        rows.append(row)
    return rows


def selected_identity(rows, expected_build, executable_version):
    if not VERSION.fullmatch(expected_build) or executable_version != expected_build:
        raise ValueError("Selected executable is not the current Forever client")
    matches = [row for row in rows
               if row["Active"] == "1" and row["Version"] == expected_build]
    if len(matches) != 1:
        raise ValueError("Current executable has no unique active .build.info product")
    row = matches[0]
    if (not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", row["Product"])
            or not CONFIG.fullmatch(row["Build Key"])
            or not CONFIG.fullmatch(row["CDN Key"])):
        raise ValueError("Invalid active product/configuration")
    return {"product": row["Product"], "edition": "Forever", "build": expected_build,
            "buildConfig": row["Build Key"], "cdnConfig": row["CDN Key"]}


def executable_version(path):
    """Read Windows' PE version resource without launching the game or a shell."""
    if os.name != "nt":
        raise OSError("Executable version discovery requires Windows")
    path = regular(path)
    library = ctypes.WinDLL("version", use_last_error=True)
    library.GetFileVersionInfoSizeW.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(wintypes.DWORD)]
    library.GetFileVersionInfoSizeW.restype = wintypes.DWORD
    library.GetFileVersionInfoW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD,
                                           wintypes.DWORD, ctypes.c_void_p]
    library.GetFileVersionInfoW.restype = wintypes.BOOL
    library.VerQueryValueW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR,
                                      ctypes.POINTER(ctypes.c_void_p),
                                      ctypes.POINTER(wintypes.UINT)]
    library.VerQueryValueW.restype = wintypes.BOOL
    ignored = wintypes.DWORD()
    size = library.GetFileVersionInfoSizeW(str(path), ctypes.byref(ignored))
    if not 0 < size <= MAX_METADATA_BYTES:
        raise ValueError("Missing or oversized executable version resource")
    buffer = ctypes.create_string_buffer(size)
    if not library.GetFileVersionInfoW(str(path), 0, size, buffer):
        raise ctypes.WinError(ctypes.get_last_error())
    pointer, length = ctypes.c_void_p(), wintypes.UINT()
    if not library.VerQueryValueW(buffer, "\\", ctypes.byref(pointer), ctypes.byref(length)):
        raise ValueError("Missing fixed executable version")
    if length.value < 52:
        raise ValueError("Truncated fixed executable version")
    words = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_uint32))
    if words[0] != 0xFEEF04BD:
        raise ValueError("Invalid fixed executable version signature")
    # Blizzard's fixed numeric resource uses a different packing than its
    # displayed four-part build. Read the FileVersion string in each declared
    # translation; never guess a build by rearranging the fixed words.
    if not library.VerQueryValueW(buffer, "\\VarFileInfo\\Translation",
                                  ctypes.byref(pointer), ctypes.byref(length)):
        raise ValueError("Missing executable version translations")
    if not 0 < length.value <= 256 or length.value % 4:
        raise ValueError("Invalid executable version translation table")
    translations = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_uint16))
    versions = set()
    for index in range(length.value // 4):
        language, codepage = translations[index * 2], translations[index * 2 + 1]
        key = f"\\StringFileInfo\\{language:04x}{codepage:04x}\\FileVersion"
        if not library.VerQueryValueW(buffer, key, ctypes.byref(pointer), ctypes.byref(length)):
            raise ValueError("Missing translated executable FileVersion")
        if not 1 < length.value <= 128:
            raise ValueError("Invalid executable FileVersion string length")
        value = ctypes.wstring_at(pointer, length.value).rstrip("\0").strip()
        if not VERSION.fullmatch(value):
            raise ValueError("Executable FileVersion is not an exact Forever version")
        versions.add(value)
    if len(versions) != 1:
        raise ValueError("Executable version translations disagree")
    return versions.pop()


def discover(executable, fetch=download, version_reader=executable_version):
    """Selected executable determines directory; no beta path/name survives by assumption."""
    upstream = resolve_upstreams(fetch)
    executable = regular(executable)
    # Supported Battle.net layouts put metadata beside the exe or one parent up.
    candidates = [executable.parent / ".build.info", executable.parent.parent / ".build.info"]
    candidates = [path for path in candidates if path.is_file()]
    if len(candidates) != 1:
        raise ValueError("Selected client has no unique supported .build.info location")
    metadata = candidates[0]
    raw = read_metadata(metadata)
    identity = selected_identity(build_rows(raw), upstream["build"], version_reader(executable))
    if read_metadata(metadata) != raw:
        raise ValueError("Client configuration changed during discovery")
    inputs = {"identity": identity, "sources": upstream["sources"],
              "buildInfoSHA256": sha(raw)}
    return {"format": "rikui-current-input-resolution-v1",
            "resolvedAt": datetime.now(timezone.utc).isoformat(),
            "inputs": inputs, "fingerprint": sha(canonical(inputs)),
            "installation": {"executable": str(executable), "directory": str(executable.parent),
                             "storageRoot": str(metadata.parent), "buildInfo": str(metadata)},
            "compatibility": "not-yet-verified",
            "limitations": ["Metadata discovery does not verify provider semantics or client assets."]}


def validate_resolution(value):
    if (value.get("format") != "rikui-current-input-resolution-v1"
            or value.get("compatibility") != "not-yet-verified"):
        raise ValueError("Unsupported discovery receipt")
    inputs = value.get("inputs", {})
    if value.get("fingerprint") != sha(canonical(inputs)):
        raise ValueError("Discovery receipt input hash mismatch")
    identity = inputs.get("identity", {})
    build = identity.get("build", "")
    selected_identity([{"Active": "1", "Version": build,
                        "Product": identity.get("product", ""),
                        "Build Key": identity.get("buildConfig", ""),
                        "CDN Key": identity.get("cdnConfig", "")}], build, build)
    if identity.get("edition") != "Forever":
        raise ValueError("Receipt does not select Forever")
    sources = inputs.get("sources", {})
    if set(sources) != set(SOURCES):
        raise ValueError("Incomplete upstream inventory")
    for name, (repository, branch) in SOURCES.items():
        row = sources[name]
        if (row.get("repository") != repository
                or not REVISION.fullmatch(row.get("revision", ""))
                or not isinstance(row.get("branch"), str) or not row["branch"]
                or branch is not None and row["branch"] != branch):
            raise ValueError("Invalid upstream identity: " + name)
    for digest in (inputs.get("buildInfoSHA256", ""),
                   sources["ui"].get("versionSHA256", "")):
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError("Missing input digest")
    return value


def changes(previous, current):
    """Metadata equality is only a refresh hint; callers must verify assets for reuse."""
    validate_resolution(current)
    if previous is None:
        return ["client", *SOURCES]
    validate_resolution(previous)
    before, after = previous["inputs"], current["inputs"]
    changed = []
    if (before["identity"] != after["identity"]
            or before["buildInfoSHA256"] != after["buildInfoSHA256"]):
        changed.append("client")
    for name in SOURCES:
        if before["sources"][name] != after["sources"][name]:
            changed.append(name)
    return changed


def save_resolution(path, value):
    """Write-once receipt; never overwrite local data or a failed build's evidence."""
    validate_resolution(value)
    with Path(path).open("xb") as stream:
        stream.write(canonical(value) + b"\n")
        stream.flush()
        os.fsync(stream.fileno())
