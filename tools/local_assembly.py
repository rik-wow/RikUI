"""Player-facing installer worker: verified local acquisition, assembly and refresh.

The native installer owns addon staging and rollback. This worker produces only
a private local bundle after the complete supported generation has verified.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sqlite3
import sys
import time
import urllib.request
import zipfile

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import forever_inputs as current
import current_refresh as refresh
import source_archive
import quest_corpus
import build_installer_bundle

TABLES=("Map","UiMap","UiMapAssignment","LiquidType","QuestV2","TaxiNodes","TaxiPath","TaxiPathNode","AreaTrigger","TransportAnimation")


def atomic(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name(path.name+".next")
    temporary.write_bytes(current.canonical(value)+b"\n")
    # Windows readers can briefly hold a handle without delete sharing.
    for attempt in range(40):
        try:
            temporary.replace(path)
            return
        except PermissionError:
            if attempt==39:raise
            time.sleep(.05)


def digest(path):
    with current.regular(path).open("rb") as stream:return hashlib.file_digest(stream,"sha256").hexdigest()


def inventory(root, active_only=False):
    root=Path(root).resolve()
    rows=[]
    for path in sorted(root.rglob("*")):
        if active_only and any(part.startswith("retained-") or "-retained-" in part for part in path.relative_to(root).parts):continue
        if active_only and (path.name.endswith(".log") or path.name=="generation-progress.json"):continue
        if path.is_file():
            current.regular(path)
            rows.append(dict(path=path.relative_to(root).as_posix(),bytes=path.stat().st_size,sha256=digest(path)))
    return rows


def verify_acquisition(folder,resolution):
    folder=Path(folder)
    receipt=json.loads((folder/"current-inputs.json").read_bytes())
    old=current.validate_resolution(receipt["resolution"])
    # Provider changes affect semantics; physical input identity/schema must agree.
    if old["inputs"]["identity"]!=resolution["inputs"]["identity"] or any(
            old["inputs"]["sources"][key]!=resolution["inputs"]["sources"][key] for key in ("ui","schemas")):
        raise ValueError("Acquisition is not current")
    model=receipt["m2Proof"]
    if digest(model["path"])!=model["sha256"]:raise ValueError("Current model proof changed")
    profile=json.loads((folder/"acquisition-profile.json").read_bytes())
    if digest(folder/"acquisition-profile.json")!=receipt["profileSHA256"]:
        raise ValueError("Acquisition profile changed")
    for row in profile["files"]:
        path=current.regular(row["path"])
        if path.stat().st_size!=row["bytes"] or digest(path)!=row["sha256"]:
            raise ValueError("Acquired geometry changed")
    tables=json.loads((folder/"db2/db2-inputs.json").read_bytes())
    if tables["build"]!=resolution["inputs"]["identity"]["build"] or set(tables["tables"])!=set(TABLES):
        raise ValueError("Required current table inventory incomplete")
    for name,row in tables["tables"].items():
        for suffix,key in ((".db2","db2SHA256"),(".dbd","dbdSHA256"),("-"+tables["build"]+".csv","csvSHA256")):
            if digest(folder/"db2"/(name+suffix))!=row[key]:raise ValueError("Current table changed")
    tex=json.loads((folder/"tex0-manifest.json").read_bytes())
    for row in tex["files"]:
        path=(folder/row["path"]).resolve()
        if not path.is_relative_to(folder.resolve()) or digest(path)!=row["sha256"]:raise ValueError("Texture inputs changed")
    return receipt



def region_names(acquisition,worlds,build):
    """Names come from the same byte-verified current Map table as navigation."""
    import csv
    import io
    raw=current.read_metadata(Path(acquisition)/"db2"/("Map-"+build+".csv"))
    labels={}
    for row in csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))):
        key=int(row["ID"])
        if key in labels:raise ValueError("Duplicate current map identity")
        name=row.get("MapName_lang","").strip()
        labels[key]=name if name and len(name)<=256 and not any(ord(char)<32 for char in name) else None
    return [dict(mapID=world["worldMapID"],name=labels.get(world["worldMapID"]) or
                 ("Map "+str(world["worldMapID"])+" (name unavailable)")) for world in worlds]


def verify_index(index, receipt, terrain):
    index,terrain=Path(index),Path(terrain)
    document=json.loads(index.with_suffix(".sqlite.receipt.json").read_bytes())
    if digest(index)!=document["sha256"]:raise ValueError("Placement index changed")
    with sqlite3.connect(index.resolve().as_uri()+"?mode=ro",uri=True) as database:
        row=database.execute("SELECT value FROM metadata WHERE key=?",("manifest",)).fetchone()
        if not row:raise ValueError("Incomplete placement index")
        meta=json.loads(row[0])
    expected={key:digest(terrain/name) for key,name in (
        ("terrain","terrain_probe.py"),("collision","collision_probe.py"),
        ("wmo","wmo_probe.py"),("emptyPlacements","world_empty_placements.py"))}
    if (meta.get("format")!="rikui-world-placement-index-v2"
            or meta.get("sourceProfileSHA256")!=receipt["profileSHA256"]
            or meta.get("indexModuleSHA256")!=digest(terrain/"world_placements.py")
            or meta.get("decoderSHA256")!=expected):
        raise ValueError("Placement index source or decoder changed")
    return document


def listfile_identity(meta):
    asset=next(row for row in meta["assets"] if row["name"]=="community-listfile.csv")
    return dict(tag=meta["tag_name"],id=asset["id"],bytes=asset["size"],
                updated=asset["updated_at"],digest=asset.get("digest"))


def verify_local_bundle(path, inputs):
    path=Path(path)
    receipt=json.loads(current.regular(path.with_suffix(".receipt.json")).read_bytes())
    if receipt.get("inputs")!=inputs or receipt.get("sha256")!=digest(path):
        raise ValueError("Local bundle inputs or bytes changed")
    return build_installer_bundle.verify_bundle(current.regular(path))


def retain_owned_file(path):
    path=Path(path)
    if path.exists():
        current.regular(path)
        path.rename(path.with_name(path.name+"-retained-"+str(time.time_ns())))


def checkpoint_job(cache, checkpoint, resolution, tools, base_sha, list_identity):
    cache=Path(cache).absolute()
    candidate=Path(checkpoint["job"]).absolute()
    old=current.validate_resolution(checkpoint["resolution"])
    if (checkpoint.get("format")!="rikui-preparation-checkpoint-v1" or candidate.parent!=cache
        or not candidate.name.startswith("job-") or old["inputs"]!=resolution["inputs"]
        or checkpoint.get("baseSHA256")!=base_sha or checkpoint.get("listfileIdentity")!=list_identity
        or refresh.tool_scopes(checkpoint["tools"],tools)-{"bundle"}):
        return None
    if candidate.is_symlink() or (hasattr(candidate,"is_junction") and candidate.is_junction()):
        raise ValueError("Linked preparation checkpoint")
    return candidate


class Assembly:
    def __init__(self,args):
        self.args=args
        self.runtime=Path(args.runtime).resolve()
        self.cache=Path(args.cache).absolute()
        for part in (self.cache,*self.cache.parents):
            if part.exists() and (part.is_symlink() or (hasattr(part,"is_junction") and part.is_junction())):
                raise ValueError("Linked local cache path")
        if self.cache.is_relative_to(self.runtime) or self.runtime.is_relative_to(self.cache):
            raise ValueError("Local cache must be separate from the runtime")
        self.cache.mkdir(parents=True,exist_ok=True)
        current.regular(self.cache/"lock") if (self.cache/"lock").exists() else None
        self.lock=(self.cache/"lock").open("a+b")
        if os.name=="nt":
            import msvcrt
            self.lock.seek(0);self.lock.write(b"1");self.lock.flush();self.lock.seek(0)
            try:msvcrt.locking(self.lock.fileno(),msvcrt.LK_NBLCK,1)
            except OSError:raise ValueError("Another RikUI preparation is using this cache")
        self.manifest=json.loads((self.runtime/"runtime.json").read_bytes())
        if self.manifest.get("format")!="rikui-local-runtime-v1":raise ValueError("Runtime manifest unavailable")
        refresh.verify_files(self.runtime,self.manifest["files"])
        self.tools={row["path"]:row["sha256"] for row in self.manifest["files"]}
        if args.executable:
            try:
                self.resolution=current.discover(args.executable)
            except (ValueError,OSError):
                if not args.storage_root:raise
                self.resolution=refresh.find_client(args.storage_root)
        else:
            self.resolution=refresh.find_client(args.storage_root)
        args.executable=self.resolution["installation"]["executable"]
        game=Path(self.resolution["installation"]["directory"])
        if self.cache.is_relative_to(game) or game.is_relative_to(self.cache):
            raise ValueError("Local cache must be separate from the game folder")
        self.start=time.monotonic()
        self.cancel=self.cache/"cancel"
        self.base_sha=digest(args.base_bundle) if args.base_bundle else None
        self.status=Path(args.status)
        self.env=dict(os.environ,RIKUI_NODE=str(self.runtime/"node/node.exe"))
        self.env["PATH"]=str(self.runtime/"node")+os.pathsep+self.env.get("PATH","")
        self.python=self.runtime/"python/python.exe"
        self.phase="Checking your game"
        self.job=None

    def report(self,message,**extra):
        atomic(self.status,dict(phase=self.phase,message=message,seconds=round(time.monotonic()-self.start,1),
                               build=self.resolution["inputs"]["identity"]["build"],**extra))

    def fresh(self):
        if current.discover(self.args.executable)["fingerprint"]!=self.resolution["fingerprint"]:
            raise ValueError("Forever or a publisher changed during preparation. Retry to refresh inputs.")
        if self.cancel.exists():raise InterruptedError("Preparation paused. Verified completed work is retained.")

    def run(self,script,*arguments,progress=None,unit_progress=None):
        self.fresh()
        if shutil.disk_usage(self.cache).free<4*1024**3:raise ValueError("Less than 4 GiB remains on the preparation drive. Free space, then Resume setup. Completed work is retained.")
        log=self.job/(script.replace("/","-")+".log")
        command=[str(self.python),"-B",str(self.runtime/"tools"/script),*map(str,arguments)]
        with log.open("ab") as stream:
            process=subprocess.Popen(command,env=self.env,cwd=self.runtime/"tools",stdout=stream,stderr=subprocess.STDOUT,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name=="nt" else 0)
            try:
                while process.poll() is None:
                    if self.cancel.exists() or shutil.disk_usage(self.cache).free<4*1024**3:
                        low_space=not self.cancel.exists()
                        if os.name=="nt":
                            subprocess.run(["taskkill.exe","/PID",str(process.pid),"/T","/F"],
                                stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW)
                        else:process.kill()
                        process.wait()
                        if low_space:raise ValueError("Less than 4 GiB remains on the preparation drive. Free space, then Resume setup. Completed work is retained.")
                        raise InterruptedError("Preparation paused. Reopen setup to resume verified work.")
                    if progress and Path(progress).is_file():
                        data=json.loads(Path(progress).read_bytes())
                        self.report("Reading current game files." if "acquisition" in script else "Preparing routes. You can pause and resume.",units="files" if "acquisition" in script else "jobs",completed=data.get("completed",data.get("files",0)),
                                    total=data.get("total"),counts=data.get("counts"),measuredSeconds=data.get("seconds"))
                    elif unit_progress:
                        folder,pattern,total=unit_progress
                        done=sum(1 for _ in Path(folder).glob(pattern)) if Path(folder).is_dir() else 0
                        self.report("Preparing road preferences from current game textures.",completed=done,total=total,units="tiles")
                    else:
                        self.report(self.phase+". You can pause; completed work is retained.")
                    time.sleep(.3)
            except BaseException:
                if process.poll() is None:
                    if os.name=="nt":
                        subprocess.run(["taskkill.exe","/PID",str(process.pid),"/T","/F"],
                            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW)
                    else:process.kill()
                    process.wait()
                raise
        if process.returncode:raise ValueError("Preparation failed in "+self.phase+". Logs and existing data are retained: "+str(log))

    def verify_previous(self,previous):
        receipt=verify_acquisition(previous["acquisition"],self.resolution)
        verify_index(Path(previous["acquisition"])/"placements.sqlite",receipt,self.runtime/"tools/terrain")
        for row in previous["supportFiles"]:
            path=current.regular(row["path"])
            if path.stat().st_size!=row["bytes"] or digest(path)!=row["sha256"]:
                raise ValueError("Assembly input bytes changed")
        travel=json.loads(current.regular(previous["travel"]).read_bytes())
        if travel.get("format")!="rikui-travel-links-v1" or travel.get("build")!=receipt["identity"]["build"]:
            raise ValueError("Travel inputs are not current")
        for filename,expected in travel["sources"].items():
            if digest(Path(previous["acquisition"])/"db2"/filename)!=expected:raise ValueError("Travel source changed")
        quest_corpus.verify(previous["corpus"])
        refresh.verify_files(previous["outputRoot"],previous["outputs"])
        bundle_inputs=dict(base=previous["baseSHA256"],corpus=digest(Path(previous["corpus"])/"manifest.json"),
                           roads=digest(Path(previous["roads"])/"road-network-receipt.json"))
        if bundle_inputs!=previous["bundleInputs"]:raise ValueError("Bundle source receipt changed")
        verify_local_bundle(previous["bundle"],bundle_inputs)
        if digest(previous["bundle"])!=previous["bundleSHA256"]:raise ValueError("Local bundle changed")
        for product in previous["products"]:
            refresh.verify_files(product["root"],product["files"])
        for key,repository in (("provider","Questie/QuestieDB"),("events","Questie/Questie")):
            receipt=source_archive.verify(previous[key+"Root"],previous["resolution"]["inputs"]["sources"][key]["revision"])
            if receipt["repository"]!=repository:raise ValueError("Unexpected source publisher")

    def reusable(self,folder,verify):
        folder=Path(folder)
        if not folder.exists():return False
        try:
            verify(folder)
            return True
        except (ValueError,OSError,KeyError,TypeError,zipfile.BadZipFile,sqlite3.DatabaseError):
            parent=folder.parent.resolve()
            if parent not in (self.cache.resolve(),self.job.resolve()):raise ValueError("Retention outside local job")
            if folder.is_symlink() or (hasattr(folder,"is_junction") and folder.is_junction()):
                raise ValueError("Linked local job")
            folder.rename(parent/(folder.name+"-retained-"+str(time.time_ns())))
            return False

    def listfile(self,meta):
        asset=next(row for row in meta["assets"] if row["name"]=="community-listfile.csv")
        url=asset["browser_download_url"]
        if not url.startswith("https://github.com/wowdev/wow-listfile/releases/download/"):raise ValueError("Listfile publisher URL")
        target=self.job/"community-listfile.csv"
        maximum=256*1024*1024
        if not 0<asset["size"]<=maximum:raise ValueError("Listfile byte bound")
        if target.exists():
            source=json.loads((self.job/"listfile-source.json").read_bytes()) if (self.job/"listfile-source.json").is_file() else {}
            if source.get("identity")==listfile_identity(meta) and source.get("sha256")==digest(target) and target.stat().st_size==asset["size"]:
                return target
            target.rename(target.with_name(target.name+"-retained-"+str(time.time_ns())))
        temporary=target.with_name(target.name+".partial-"+str(time.time_ns()))
        with urllib.request.urlopen(urllib.request.Request(url,headers={"User-Agent":"RikUI-local-assembly/1"}),timeout=90) as response, temporary.open("xb") as stream:
            total=0
            while data:=response.read(1024*1024):
                total+=len(data)
                if total>maximum:raise ValueError("Listfile download bound")
                stream.write(data)
                if self.cancel.exists():raise InterruptedError("Listfile download paused. Retry setup to resume preparation.")
                self.report("Downloading road names from their publisher.",completed=total,total=asset["size"],units="bytes")
        if total!=asset["size"]:raise ValueError("Incomplete listfile download")
        actual=digest(temporary)
        if asset.get("digest") and asset["digest"]!="sha256:"+actual:raise ValueError("Listfile publisher checksum mismatch")
        temporary.replace(target)
        atomic(self.job/"listfile-source.json",dict(publisher="wowdev/wow-listfile",identity=listfile_identity(meta),url=url,bytes=total,sha256=actual))
        return target

    def local_bundle(self,corpus,roads):
        bundle=self.job/"local-bundle.zip"
        inputs=dict(base=self.base_sha,corpus=digest(Path(corpus)/"manifest.json"),
                    roads=digest(Path(roads)/"road-network-receipt.json"))
        if not self.reusable(bundle,lambda path:verify_local_bundle(path,inputs)):
            retain_owned_file(bundle.with_suffix(".receipt.json"))
            build_installer_bundle.assemble_local(self.args.base_bundle,corpus,roads,bundle)
            atomic(bundle.with_suffix(".receipt.json"),dict(inputs=inputs,sha256=digest(bundle)))
        verify_local_bundle(bundle,inputs)
        return bundle,inputs

    def prepare(self):
        self.report("Checking the latest Forever build and separately published quest information.")
        latest=self.cache/"latest.json"
        previous=json.loads(latest.read_bytes()) if latest.is_file() else None
        scopes,changed=refresh.scopes(previous,self.resolution,self.tools,self.verify_previous)
        # Listfile publisher changes can alter road preferences, independently of geometry.
        list_meta=json.loads(current.download("https://api.github.com/repos/wowdev/wow-listfile/releases/latest"))
        list_identity=listfile_identity(list_meta)
        if previous and previous.get("listfileIdentity")!=list_identity and "roads" not in scopes:
            scopes.append("roads");changed.append("listfile")
        if previous and self.base_sha and previous.get("baseSHA256")!=self.base_sha:
            scopes.append("bundle")
            changed.append("addon")
        if self.args.check_only:
            self.report("Update available." if scopes else "Your quest guide and routes are current.",changed=changed,rebuild=scopes)
            return dict(format="rikui-refresh-probe-v1",resolution=self.resolution,rebuild=scopes,changed=changed)
        if not scopes:
            self.report("Your quest guide and routes are current. Verified local files reused.",state="verified-no-op")
            # Reuse generated bytes while targeting the freshly selected/discovered installation.
            # Installation paths are not the content fingerprint and can move independently.
            result=dict(previous,resolution=self.resolution)
            if previous["resolution"]["installation"]!=self.resolution["installation"]:
                atomic(latest,result)
            return result
        key=current.sha(current.canonical(dict(inputs=self.resolution["inputs"],tools=self.tools,base=self.base_sha,listfile=list_identity)))[:24]
        self.job=self.cache/("job-"+key)
        preparing=self.cache/"preparing.json"
        if self.args.resume_runtime:
            prior_runtime=Path(self.args.resume_runtime).resolve()
            prior_manifest=json.loads((prior_runtime/"runtime.json").read_bytes())
            refresh.verify_files(prior_runtime,prior_manifest["files"])
            prior_tools={row["path"]:row["sha256"] for row in prior_manifest["files"]}
            if refresh.tool_scopes(prior_tools,self.tools)-{"bundle"}:
                raise ValueError("Previous preparation runtime has changed producing tools; a fresh generation is required")
            prior_key=current.sha(current.canonical(dict(inputs=self.resolution["inputs"],tools=prior_tools,base=self.base_sha,listfile=list_identity)))[:24]
            prior_job=self.cache/("job-"+prior_key)
            verify_acquisition(prior_job/"acquisition",self.resolution)
            atomic(preparing,dict(format="rikui-preparation-checkpoint-v1",job=str(prior_job),resolution=self.resolution,
                tools=prior_tools,baseSHA256=self.base_sha,listfileIdentity=list_identity))
        if not previous and preparing.exists():
            try:
                checkpoint=json.loads(current.read_metadata(preparing))
                candidate=checkpoint_job(self.cache,checkpoint,self.resolution,self.tools,self.base_sha,list_identity)
                if candidate:self.job=candidate
            except (ValueError,OSError,KeyError,TypeError):
                retain_owned_file(preparing)
        required=8 if self.job.exists() else (80 if "acquisition" in scopes else 40 if "bakes" in scopes else 24 if "roads" in scopes else 8)
        free=shutil.disk_usage(self.cache).free/1024**3
        if free<required:
            raise ValueError(f"Preparation needs {required} GiB free; {free:.1f} GiB is available at {self.cache.anchor}. Choose Preparation folder on a roomier drive, or free space and retry.")
        self.job.mkdir(exist_ok=True)
        atomic(preparing,dict(format="rikui-preparation-checkpoint-v1",job=str(self.job),resolution=self.resolution,
            tools=self.tools,baseSHA256=self.base_sha,listfileIdentity=list_identity))
        if previous and set(scopes)=={"bundle"}:
            # The scope verifier already checked every current source/product byte.
            # An interface/controller update must not regenerate terrain receipts.
            self.phase="Verifying your installation"
            self.report("Updating RikUI with your verified current quest guide and routes.")
            self.fresh()
            bundle,bundle_inputs=self.local_bundle(previous["corpus"],previous["roads"])
            result=dict(previous,resolution=self.resolution,tools=self.tools,baseSHA256=self.base_sha,
                bundle=str(bundle),bundleSHA256=digest(bundle),bundleInputs=bundle_inputs,
                seconds=round(time.monotonic()-self.start,1),
                coverage=dict(previous["coverage"],regions=region_names(previous["acquisition"],previous["coverage"]["worlds"],self.resolution["inputs"]["identity"]["build"])))
            self.verify_previous(result)
            self.fresh()
            atomic(latest,result)
            self.report("Quest guide and supported routes prepared and verified.",state="prepared",coverage=result["coverage"])
            return result
        # Steps are individually verified. A failed attempt remains available in its log/staging directories.
        acquisition=Path(previous["acquisition"]) if previous and "acquisition" not in scopes else self.job/"acquisition"
        if not self.reusable(acquisition,lambda folder:verify_acquisition(folder,self.resolution)):
            self.phase="Reading your game"
            self.report("Reading terrain and current quest membership from your installed Forever client.")
            self.run("terrain/current_acquisition.py","--executable",self.args.executable,
                     "--extractor",self.runtime/"extractor/TACTTool.exe","--reader",self.runtime/"reader",
                     "--output",acquisition,progress=acquisition/"acquisition-progress.json")
        receipt=verify_acquisition(acquisition,self.resolution)
        self.env["RIKUI_CURRENT_INPUTS"]=str(acquisition/"current-inputs.json")
        self.phase="Getting quest information"
        self.report("Downloading QuestieDB source separately from its publisher, then composing all supported player variants.")
        corpus=Path(previous["corpus"]) if previous and "corpus" not in scopes else self.job/"corpus"
        sources=self.resolution["inputs"]["sources"]
        provider=self.cache/("provider-"+sources["provider"]["revision"])
        events=self.cache/("events-"+sources["events"]["revision"])
        if not self.reusable(corpus,quest_corpus.verify):
            self.reusable(provider,lambda folder:source_archive.verify(folder,sources["provider"]["revision"]))
            self.reusable(events,lambda folder:source_archive.verify(folder,sources["events"]["revision"]))
            self.fresh();source_archive.acquire("Questie/QuestieDB",sources["provider"]["revision"],provider)
            self.fresh();source_archive.acquire("Questie/Questie",sources["events"]["revision"],events)
            export=self.job/"provider.json"
            self.run("export_forever.py","--source-root",provider,"--revision",sources["provider"]["revision"],"--output",export,"--reuse")
            self.run("quest_corpus.py","build","--export",export,"--output",corpus,
                     "--client-index",acquisition/"db2"/("QuestV2-"+receipt["identity"]["build"]+".csv"),
                     "--client-build",receipt["identity"]["build"],"--client-index-sha256",receipt["sourceHashes"]["QuestV2"],
                     "--event-source-root",events,"--event-revision",sources["events"]["revision"])
        quest_corpus.verify(corpus)
        self.phase="Preparing routes"
        self.report("Building routes on this computer. Quest and regional gaps remain explicit until preparation finishes.")
        bakes=Path(previous["bakes"]) if previous and "bakes" not in scopes else self.job/"bakes"
        index=acquisition/"placements.sqlite"
        base=["--profile",acquisition/"acquisition-profile.json","--expected-sha256",receipt["profileSHA256"],
              "--source-directory",acquisition/"db2","--tile-csv",acquisition/"db2/all-projected-world-tile-worklist.csv",
              "--topology-inventory",acquisition/"db2/inventory.json"]
        if index.exists():
            try:verify_index(index,receipt,self.runtime/"tools/terrain")
            except (ValueError,OSError,KeyError,sqlite3.DatabaseError):
                current.regular(index)
                index.rename(index.with_name("placements-retained-"+str(time.time_ns())+".sqlite"))
                sidecar=index.with_suffix(".sqlite.receipt.json")
                if sidecar.exists():
                    current.regular(sidecar)
                    sidecar.rename(sidecar.with_name(sidecar.name+"-retained-"+str(time.time_ns())))
        if not index.exists():
            retain_owned_file(index.with_suffix(".sqlite.receipt.json"))
            self.run("terrain/world_bake.py",*base,"--build-index",index)
        index_receipt=verify_index(index,receipt,self.runtime/"tools/terrain")
        self.run("terrain/world_bake_parallel.py",*base,"--placement-index",index,
                 "--index-sha256",index_receipt["sha256"],"--root",bakes,"--workers",self.args.workers,
                 progress=bakes/"generation-progress.json")
        capture=self.job/"network-input.json"
        # Capture accepted run directories again after byte-verified resume.
        if capture.exists():capture.rename(capture.with_name("network-input-retained-"+str(time.time_ns())+".json"))
        self.run("terrain/road_network.py","--capture",bakes,"--output",capture)
        raster_tool="tools/terrain/road_textures.py"
        rasters=Path(previous["rasters"]) if (previous and "acquisition" not in scopes
            and previous.get("listfileIdentity")==list_identity
            and previous.get("tools",{}).get(raster_tool)==self.tools.get(raster_tool)) else self.job/"road-rasters"
        def verify_rasters(folder):
            audit=json.loads((folder/"road-audit.json").read_bytes())
            if audit["tex0ManifestSHA256"]!=digest(acquisition/"tex0-manifest.json"):raise ValueError("Raster source changed")
            if audit["parserSHA256"]!=digest(self.runtime/"tools/terrain/road_textures.py"):raise ValueError("Raster compiler changed")
            refresh.verify_files(folder,audit["files"])
        if not self.reusable(rasters,verify_rasters):
            listfile=self.listfile(list_meta)
            self.run("terrain/road_textures.py","--tex0-directory",acquisition,
                     "--manifest-sha256",digest(acquisition/"tex0-manifest.json"),"--listfile",listfile,
                     "--listfile-sha256",digest(listfile),"--output",rasters,
                     unit_progress=(rasters,"w*.npy",len(json.loads((acquisition/"tex0-manifest.json").read_bytes())["files"])))
        travel_tool="tools/terrain/travel_links.py"
        travel=Path(previous["travel"]) if (previous and "acquisition" not in scopes
            and previous.get("tools",{}).get(travel_tool)==self.tools.get(travel_tool)) else self.job/"travel.json"
        if not travel.exists():self.run("terrain/travel_links.py","--tables",acquisition/"db2","--build",receipt["identity"]["build"],"--output",travel)
        roads=Path(previous["roads"]) if previous and "roads" not in scopes else self.job/"roads"
        from terrain.install_roads import source_pack
        def verify_roads(folder):
            document=json.loads((folder/"road-network-receipt.json").read_bytes())
            for key,path in (("inputSHA256",capture),("semanticSHA256",corpus/"audit/semantic-quests.json"),
                             ("travelSHA256",travel),("compilerSHA256",self.runtime/"tools/terrain/road_network.py")):
                if document.get(key)!=digest(path):raise ValueError("Road inputs changed")
            return source_pack(folder,digest(folder/"road-network-receipt.json"))
        if not self.reusable(roads,verify_roads):
            worlds=sorted(map(int,receipt["topology"]))
            args=["--input",capture,"--expected-sha256",digest(capture),"--source-directory",acquisition/"db2",
                  "--road-rasters",rasters,"--output",roads,"--workers",self.args.workers,
                  "--semantic-quests",corpus/"audit/semantic-quests.json","--semantic-sha256",digest(corpus/"audit/semantic-quests.json"),
                  "--travel",travel,"--travel-sha256",digest(travel)]
            for world in worlds:args.extend(("--world",world))
            self.run("terrain/road_network.py",*args)
        self.phase="Verifying your installation"
        self.report("Checking generated files and supported coverage before installation.")
        road_receipt=json.loads((roads/"road-network-receipt.json").read_bytes())
        from terrain.install_roads import source_pack
        source_pack(roads,digest(roads/"road-network-receipt.json"))
        self.fresh()
        bundle,bundle_inputs=self.local_bundle(corpus,roads)
        coverage=json.loads((corpus/"coverage.json").read_bytes())
        result=dict(format="rikui-local-assembly-v1",resolution=self.resolution,tools=self.tools,
                    acquisition=str(acquisition),corpus=str(corpus),bakes=str(bakes),roads=str(roads),rasters=str(rasters),travel=str(travel),
                    providerRoot=str(provider),eventsRoot=str(events),baseSHA256=self.base_sha,
                    supportFiles=[dict(path=str(path),bytes=path.stat().st_size,sha256=digest(path)) for path in (travel,capture,index,index.with_suffix(".sqlite.receipt.json"))],
                    products=[dict(root=str(folder),files=inventory(folder,active_only=True)) for folder in (corpus,bakes,rasters)],
                    bundle=str(bundle),bundleSHA256=digest(bundle),bundleInputs=bundle_inputs,outputRoot=str(self.job),
                    outputs=inventory(roads),listfileIdentity=list_identity,seconds=round(time.monotonic()-self.start,1),
                    coverage=dict(questCounts=coverage["counts"],clientUniverse={key:value for key,value in coverage.get("clientUniverse",{}).items() if not isinstance(value,list)},
                                  worlds=road_receipt["worlds"],regions=region_names(acquisition,road_receipt["worlds"],receipt["identity"]["build"]),limits=["Provider reference data can lag the current server.",
                                  "Unknown quests, floors, phases, physics and unsupported projections remain explicit.",
                                  "Transport times are estimates; server-specific portals and lift endpoints require compatible evidence."]))
        # Outputs are relative to their own verified road root.
        result["outputRoot"]=str(roads)
        self.verify_previous(result)
        atomic(latest,result)
        self.report("Quest guide and supported routes prepared and verified.",state="prepared",coverage=result["coverage"])
        return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("runtime","cache","status","result"):parser.add_argument("--"+name,required=True)
    parser.add_argument("--executable")
    parser.add_argument("--storage-root",action="append",default=[])
    parser.add_argument("--base-bundle")
    parser.add_argument("--resume-runtime",help="Verify and resume an older packaged preparation after an orchestration-only update")
    parser.add_argument("--workers",type=int,default=2)
    parser.add_argument("--check-only",action="store_true")
    args=parser.parse_args()
    if not 1<=args.workers<=4:parser.error("workers must be 1 through 4")
    if not args.executable and not args.storage_root:parser.error("Choose a Forever executable or storage folder")
    if not args.check_only and not args.base_bundle:parser.error("base bundle required")
    assembly=None
    try:
        assembly=Assembly(args)
        result=assembly.prepare();atomic(args.result,result)
    except (ValueError,OSError,KeyError,TypeError,StopIteration,InterruptedError,zipfile.BadZipFile,sqlite3.DatabaseError) as error:
        atomic(args.status,dict(phase="Preparation paused" if isinstance(error,InterruptedError) else "Preparation needs attention",
              message=str(error),state="cancelled" if isinstance(error,InterruptedError) else "failed",
              recovery="Reopen setup to retry. Existing installation, local inputs and backups are preserved."))
        raise SystemExit(130 if isinstance(error,InterruptedError) else 1)
    finally:
        if assembly:assembly.lock.close()


if __name__=="__main__":main()
