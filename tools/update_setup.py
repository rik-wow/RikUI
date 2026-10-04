"""Obtain newer verified public RikUI setup programs from the existing release channel."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import time
import urllib.parse
import urllib.request
import forever_inputs as current

API="https://api.github.com/repos/rik-wow/RikUI/releases?per_page=20"
NAME="RikUI-Setup-manifest.json"
MAX_BINARY=256*1024*1024

def version(value):
    match=re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?",value)
    if not match:raise ValueError("Unsupported setup release version")
    return (*map(int,match.group(1,2,3)),int(match.group(4) is None),int(match.group(4) or 0))

def url(value):
    parsed=urllib.parse.urlsplit(value)
    if parsed.scheme!="https" or parsed.username or parsed.password:raise ValueError("Setup release HTTPS URL required")
    if parsed.hostname=="github.com" and parsed.path.startswith("/rik-wow/RikUI/releases/download/"):return value
    raise ValueError("Unexpected setup release publisher")

def opener():
    class Redirects(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,request,fp,code,message,headers,target):
            parsed=urllib.parse.urlsplit(target)
            if parsed.scheme!="https" or parsed.hostname not in (
                "github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"):
                raise ValueError("Unexpected release download redirect")
            return super().redirect_request(request,fp,code,message,headers,target)
    return urllib.request.build_opener(Redirects())

def fetch(value,maximum):
    request=urllib.request.Request(url(value),headers={"User-Agent":"RikUI-setup-update/1"})
    with opener().open(request,timeout=60) as response:
        raw=response.read(maximum+1)
    if not raw or len(raw)>maximum:raise ValueError("Setup release metadata byte bound")
    return raw

def checked_manifest(release,fetcher=fetch):
    asset=next((row for row in release.get("assets",[]) if row["name"]==NAME),None)
    if not asset:return None
    raw=fetcher(asset["browser_download_url"],1024*1024)
    if asset.get("digest") and asset["digest"]!="sha256:"+current.sha(raw):
        raise ValueError("Setup manifest publisher checksum mismatch")
    value=json.loads(raw)
    if value.get("format")!="rikui-public-installer-v1" or value.get("version")!=release["tag_name"].removeprefix("v"):
        raise ValueError("Setup manifest release identity mismatch")
    version(value["version"])
    artifact=value["artifact"]
    url(artifact["url"])
    if (artifact.get("filename")!="RikUI-Setup.exe"
            or not re.fullmatch("[a-f0-9]{64}",artifact.get("sha256",""))
            or type(artifact.get("bytes")) is not int or not 0<artifact["bytes"]<=MAX_BINARY):
        raise ValueError("Setup artifact contract invalid")
    published=next((row for row in release["assets"] if row["name"]==artifact["filename"]),None)
    if (not published or published["browser_download_url"]!=artifact["url"]
            or published["size"]!=artifact["bytes"]
            or (published.get("digest") and published["digest"]!="sha256:"+artifact["sha256"])):
        raise ValueError("Setup artifact disagrees with its published asset")
    return value

def select(releases,current_version,fetcher=fetch,current_sha=None):
    present=version(current_version)
    if not isinstance(releases,list) or len(releases)>20:raise ValueError("Setup release catalogue bound")
    candidates=[]
    for release in releases:
        if release.get("draft"):continue
        try:target=version(release["tag_name"].removeprefix("v"))
        except (ValueError,KeyError):continue
        if target<present or (target==present and current_sha is None):continue
        candidates.append((target,release))
    for _,release in sorted(candidates,key=lambda row:row[0],reverse=True):
        manifest=checked_manifest(release,fetcher)
        if manifest:
            if version(manifest["version"])==present:
                if manifest["artifact"]["sha256"]!=current_sha:raise ValueError("Published setup bytes changed without a newer release version")
                return None
            return manifest
    return None

def directory(root):
    root=Path(root).absolute()
    for part in (root,*root.parents):
        if part.exists() and (part.is_symlink() or (hasattr(part,"is_junction") and part.is_junction())):
            raise ValueError("Linked setup update directory")
    root.mkdir(parents=True,exist_ok=True)
    return root

def download_artifact(artifact,root):
    root=directory(root)
    folder=directory(root/artifact["sha256"])
    target=folder/"RikUI-Setup.exe"
    def digest(path):
        with current.regular(path).open("rb") as stream:return hashlib.file_digest(stream,"sha256").hexdigest()
    if target.exists():
        if target.stat().st_size==artifact["bytes"] and digest(target)==artifact["sha256"]:return target
        current.regular(target)
        target.rename(folder/("RikUI-Setup-retained-"+str(time.time_ns())+".exe"))
    if shutil.disk_usage(root).free<artifact["bytes"]*2+64*1024*1024:
        raise ValueError("More disk space is needed to update RikUI setup")
    partial=folder/("download.partial-"+str(time.time_ns()))
    request=urllib.request.Request(url(artifact["url"]),headers={"User-Agent":"RikUI-setup-update/1"})
    with opener().open(request,timeout=60) as response,partial.open("xb") as stream:
        count=0
        while raw:=response.read(1024*1024):
            count+=len(raw)
            if count>artifact["bytes"]:raise ValueError("Setup download byte bound")
            stream.write(raw)
        stream.flush();os.fsync(stream.fileno())
    if count!=artifact["bytes"] or digest(partial)!=artifact["sha256"]:
        raise ValueError("Setup download checksum mismatch; incomplete bytes retained")
    partial.rename(target)
    return target

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("version","programs","result"):parser.add_argument("--"+name,required=True)
    parser.add_argument("--current-program",required=True)
    args=parser.parse_args()
    with current.regular(args.current_program).open("rb") as stream:program_sha=hashlib.file_digest(stream,"sha256").hexdigest()
    releases=json.loads(current.download(API))
    manifest=select(releases,args.version,current_sha=program_sha)
    result=dict(format="rikui-setup-update-result-v1",state="current",channel=API)
    if manifest:
        target=download_artifact(manifest["artifact"],args.programs)
        result.update(state="verified-update",program=str(target),sha256=manifest["artifact"]["sha256"],version=manifest["version"])
    from local_assembly import atomic
    atomic(args.result,result)
if __name__=="__main__":main()
