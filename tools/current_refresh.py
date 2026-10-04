"""Current-input refresh policy shared by the installer and daily update checks.

A discovery match alone is insufficient for reuse. All recorded input/output
bytes and producing tools must still verify; a changed input scopes a rebuild.
"""
from pathlib import Path
import json
import os
import stat
import sqlite3
import zipfile
import forever_inputs as current


def file_hash(path):
    path=current.regular(path)
    if path.stat().st_size > 512*1024*1024:
        raise ValueError("Refresh file byte bound")
    import hashlib
    with path.open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def verify_files(root, rows):
    root=Path(root).resolve()
    if not isinstance(rows,list) or not 0<len(rows)<=65536:
        raise ValueError("Refresh inventory bound")
    names=set()
    for row in rows:
        name=row.get("path","")
        target=root/name
        if (not name or Path(name).is_absolute() or "\\" in name or ":" in name
                or ".." in Path(name).parts or name.casefold() in names
                or not target.resolve().is_relative_to(root)):
            raise ValueError("Unsafe refresh inventory")
        names.add(name.casefold())
        target=current.regular(target)
        if target.stat().st_size!=row["bytes"] or file_hash(target)!=row["sha256"]:
            raise ValueError("Refresh bytes changed: "+name)
    return True



def tool_scopes(before,after):
    """Map changes to producing stages; unknown dependencies invalidate all."""
    products=set()
    all_products={"acquisition","corpus","bakes","roads"}
    for name in set(before)|set(after):
        if before.get(name)==after.get(name):continue
        lower=name.lower()
        if lower.endswith(("/license","/license.txt","/copying",".dist-info/licenses/license")) or "/licenses/" in lower:continue
        if name in ("tools/local_assembly.py","tools/build_installer_bundle.py","tools/package_addon.py",
                    "tools/update_quest_data.py","tools/update_setup.py","tools/terrain/world_bake_parallel.py",
                    "tools/terrain/node_modules/.package-lock.json"):
            # Legacy npm installation bookkeeping is not a runtime producer.
            products.add("bundle")
        elif name in ("tools/export_forever.py","tools/export_forever.lua","tools/quest_corpus.py","tools/source_archive.py") or name.startswith("python/site-packages/lupa"):
            products.update(("corpus","roads"))
        elif name.startswith("tools/terrain/road") or name in ("tools/terrain/travel_links.py","tools/terrain/quest_pockets.py"):
            products.add("roads")
        elif name in ("tools/current_refresh.py",):
            # Repeat the new verifier before reuse; packaging refreshes the receipt.
            products.add("bundle")
        else:
            products.update(all_products)
    return products


def scopes(previous, resolution, tools, verify):
    """Return affected products. verify is mandatory even on unchanged metadata."""
    changed=current.changes(previous.get("resolution") if previous else None,resolution)
    if previous is None:
        return ["acquisition","corpus","bakes","roads"], changed
    if previous.get("format")!="rikui-local-assembly-v1":
        return ["acquisition","corpus","bakes","roads"], changed+["format"]
    products=tool_scopes(previous.get("tools",{}),tools)
    if previous.get("tools")!=tools:changed.append("tools")
    if any(key in changed for key in ("client","schemas","ui")):
        products.update(("acquisition","corpus","bakes","roads"))
    if any(key in changed for key in ("provider","events")):
        products.update(("corpus","roads"))
    try:
        verify(previous)
    except (ValueError,OSError,KeyError,TypeError,zipfile.BadZipFile,sqlite3.DatabaseError):
        products.update(("acquisition","corpus","bakes","roads"))
        changed.append("unverified-bytes")
    return [name for name in ("acquisition","corpus","bakes","roads","bundle") if name in products],changed


def find_client(storage_roots, fetch=current.download, version_reader=current.executable_version):
    """Discover a release installation without assuming the beta directory survives."""
    source=current.resolve_upstreams(fetch)
    build=source["build"]
    matches=[]
    for storage in storage_roots:
        root=Path(storage).absolute()
        candidates=[root]
        if root.is_dir():
            candidates.extend(path for path in root.iterdir() if path.is_dir())
        if len(candidates)>128:
            raise ValueError("Client directory discovery bound")
        for folder in candidates:
            if not folder.is_dir(): continue
            for exe in folder.glob("Wow*.exe"):
                try:
                    if version_reader(exe)!=build: continue
                    receipt=current.discover(exe,fetch,version_reader)
                except (ValueError,OSError):
                    continue
                matches.append(receipt)
    unique={row["installation"]["executable"]:row for row in matches}
    if len(unique)!=1:
        raise ValueError("Choose your current Forever executable: discovery found "+str(len(unique))+" matching clients")
    return next(iter(unique.values()))
