"""Acquire source snapshots separately from their publishers; never a baked addon ZIP."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import urllib.request
import zipfile

FORMAT = "rikui-publisher-source-v1"
MAX_ARCHIVE = 128 * 1024 * 1024
MAX_EXPANDED = 512 * 1024 * 1024
MAX_FILES = 32768


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def inventory(root):
    rows=[]
    for path in sorted(Path(root).rglob("*")):
        if path.is_symlink() or getattr(path.stat(), "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0):
            raise ValueError("Linked publisher source")
        if path.is_file() and path.name != ".rikui-source.json":
            if path.stat().st_size>64*1024*1024:
                raise ValueError("Publisher source file byte bound")
            rows.append(dict(path=path.relative_to(root).as_posix(),bytes=path.stat().st_size,sha256=digest(path)))
    if not 0<len(rows)<=MAX_FILES or sum(row["bytes"] for row in rows)>MAX_EXPANDED:
        raise ValueError("Publisher source inventory bound")
    return rows


def verify(root, revision):
    root=Path(root)
    receipt=json.loads((root/".rikui-source.json").read_bytes())
    if (receipt.get("format")!=FORMAT or receipt.get("revision")!=revision
            or receipt.get("repository") not in ("Questie/QuestieDB","Questie/Questie","Kruithne/wow.export")):
        raise ValueError("Unsupported publisher source receipt")
    if receipt["files"]!=inventory(root):
        raise ValueError("Publisher source changed after acquisition")
    return receipt


def acquire(repository,revision,output):
    if repository not in ("Questie/QuestieDB","Questie/Questie","Kruithne/wow.export") or not re.fullmatch("[0-9a-f]{40}",revision):
        raise ValueError("Unsupported publisher source identity")
    output=Path(output)
    if output.exists():
        return verify(output,revision)
    output.parent.mkdir(parents=True,exist_ok=True)
    url="https://codeload.github.com/"+repository+"/zip/"+revision
    request=urllib.request.Request(url,headers={"User-Agent":"RikUI-local-assembly/1"})
    with urllib.request.urlopen(request,timeout=90) as response:
        raw=response.read(MAX_ARCHIVE+1)
    if not 0<len(raw)<=MAX_ARCHIVE:
        raise ValueError("Publisher source archive byte bound")
    files={}
    folded=set()
    expanded=0
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        records=archive.infolist()
        if len(records)>MAX_FILES:
            raise ValueError("Publisher archive member bound")
        prefixes={PurePosixPath(row.filename).parts[0] for row in records}
        if len(prefixes)!=1:
            raise ValueError("Publisher archive root layout")
        for row in records:
            path=PurePosixPath(row.filename)
            if (path.is_absolute() or any(part in (".","..") for part in path.parts)
                    or "\\" in row.orig_filename or ":" in row.orig_filename
                    or any(part.rstrip(" .") != part or re.fullmatch(r"(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?", part, re.I) for part in path.parts)
                    or stat.S_ISLNK(row.external_attr>>16)):
                raise ValueError("Unsafe publisher archive member")
            if row.is_dir():
                continue
            relative=PurePosixPath(*path.parts[1:]).as_posix()
            if repository == "Questie/Questie" and not (relative.startswith("Database/Corrections/Holidays/quests/") or re.fullmatch(r"(?:LICENSE|COPYING)(?:\.[A-Za-z]+)?", relative, re.I)):
                continue
            if relative in files or relative.casefold() in folded:
                raise ValueError("Duplicate publisher archive member")
            if row.file_size>64*1024*1024 or expanded+row.file_size>MAX_EXPANDED:
                raise ValueError("Expanded publisher archive byte bound")
            files[relative]=archive.read(row)
            folded.add(relative.casefold())
            expanded += row.file_size
    output.mkdir()
    try:
        for name,body in files.items():
            path=output/name
            path.parent.mkdir(parents=True,exist_ok=True)
            with path.open("xb") as stream:
                stream.write(body)
        receipt=dict(format=FORMAT,repository=repository,revision=revision,url=url,
                     archiveSHA256=hashlib.sha256(raw).hexdigest(),files=inventory(output))
        (output/".rikui-source.json").write_text(json.dumps(receipt,sort_keys=True,indent=2)+"\n",encoding="utf-8")
        return verify(output,revision)
    except BaseException:
        # Preserve the failed snapshot for inspection; never silently accept/resume it.
        raise

if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository",required=True)
    parser.add_argument("--revision",required=True)
    parser.add_argument("--output",required=True)
    options=parser.parse_args()
    result=acquire(options.repository,options.revision,options.output)
    print(json.dumps({key:result[key] for key in ("repository","revision","archiveSHA256")}))
