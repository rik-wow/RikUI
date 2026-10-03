"""Acquire and bake a bounded current-client world for an isolated UI-free Studio capture.
Never reads historical renderer caches or changes the live isometric project/save.
Private outputs contain client assets: only reviewed screenshot bytes may be published.
"""
import argparse, csv, hashlib, io, json, re, shutil, subprocess, sys, urllib.request
from pathlib import Path

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def download(url):
    request=urllib.request.Request(url,headers={"User-Agent":"RikUI-Studio-capture"})
    return urllib.request.urlopen(request,timeout=180).read()

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--app-root",type=Path,required=True)
    p.add_argument("--work",type=Path,required=True)
    p.add_argument("--extractor",type=Path,required=True)
    p.add_argument("--client",type=Path,default=Path("C:/Program Files (x86)/World of Warcraft"))
    p.add_argument("--terrain-mode",choices=["map-textures","splat"],default="map-textures")
    a=p.parse_args();app=a.app_root.resolve();work=a.work.resolve()
    head=subprocess.check_output(["git","ls-remote","https://github.com/Gethe/wow-ui-source.git","refs/heads/forever"],text=True).split()[0]
    version=download(f"https://raw.githubusercontent.com/Gethe/wow-ui-source/{head}/version.txt").decode().strip()
    if not re.fullmatch(r"1\.\d+\.\d+\.\d+",version):raise RuntimeError("Invalid current client identity")
    exe=a.client/"_classic_beta_/WowB.exe"
    if exe.exists():
        installed=subprocess.check_output(["powershell","-NoProfile","-Command","(Get-Item -LiteralPath '"+str(exe).replace("'","''")+"').VersionInfo.FileVersion"],text=True).strip()
        if installed!=version:raise RuntimeError("Installed client differs from current Forever source")
    lines=(a.client/".build.info").read_text().splitlines();headers=[s.split("!")[0] for s in lines[0].split("|")]
    build=next(row for line in lines[1:] if (row:=dict(zip(headers,line.split("|")))).get("Product")=="wow_classic_beta" and row.get("Version")==version)
    identity={"version":version,"uiHead":head,"buildConfig":build["Build Key"],"cdnConfig":build["CDN Key"],"extractorSHA256":digest(a.extractor)}
    work.mkdir(parents=True,exist_ok=True);stamp=work/"identity.json"
    if stamp.exists() and json.loads(stamp.read_text())!=identity:raise RuntimeError("Scratch inputs differ; choose a fresh work directory")
    stamp.write_text(json.dumps(identity,indent=2)+"\n")
    scripts=work/"scripts";scripts.mkdir(exist_ok=True)
    db2=work/"db2";db2.mkdir(exist_ok=True)
    private=work/".qa/native-source";assets=private/"assets";assets.mkdir(parents=True,exist_ok=True)
    world=work/"world/azeroth";world.mkdir(parents=True,exist_ok=True)
    script_inputs=[]
    for source in (app/"scripts").glob("*.py"):
        text=source.read_text(encoding="utf-8-sig")
        # Bind the existing importer algorithms to this resolved acquisition.
        text=text.replace("D:/RikUI-local/forever-db2-70009",db2.as_posix()).replace("1.60.1.70009",version)
        (scripts/source.name).write_text(text,encoding="utf-8")
        script_inputs.append({"name":source.name,"sourceSHA256":digest(source),"boundSHA256":digest(scripts/source.name)})
    def table(name):
        target=db2/f"{name}-{version}.csv"
        if not target.exists():
            raw=download(f"https://wago.tools/db2/{name}/csv?build={version}")
            if raw.lstrip().startswith(b"<") or b"ID" not in raw[:512]:raise RuntimeError("Invalid current table "+name)
            target.write_bytes(raw)
        return list(csv.DictReader(io.StringIO(target.read_text(encoding="utf-8-sig"))))
    for name in ["Map","AreaTable","LiquidType","Light","LightParams","LightData","ZoneLight","ZoneLightPoint","LightSkybox"]:
        table(name)
    maprow=next(row for row in table("Map") if row["ID"]=="0")
    with (private/"maps.csv").open("w",newline="",encoding="utf-8") as f:
        writer=csv.DictWriter(f,fieldnames=list(maprow));writer.writeheader();writer.writerow(maprow)
    (private/"models.json").write_text('{"wmo":[],"m2":[]}')
    extraction=[]
    def extract(requests,folder=assets):
        folder.mkdir(parents=True,exist_ok=True)
        wanted={int(fid):name for fid,name in requests.items() if fid and not (folder/name).exists()}
        if wanted:
            if shutil.disk_usage(work).free<12*1024**3:raise RuntimeError("Capture acquisition needs a 12 GiB reserve")
            listpath=private/"current-request.list";listpath.write_text("".join(f"{fid};{name}\n" for fid,name in sorted(wanted.items())))
            log=private/f"extract-{len(extraction):03d}.log"
            command=[str(a.extractor.resolve()),"-p","wow_classic_beta","-b",build["Build Key"],"-c",build["CDN Key"],"-l","enUS","-m","list","-i",str(listpath),"-o",str(folder)]
            with log.open("w") as f:subprocess.run(command,cwd=work,stdout=f,stderr=subprocess.STDOUT,check=True)
        for fid,name in requests.items():
            if not fid:continue
            path=folder/name
            if not path.is_file() or not path.stat().st_size:raise RuntimeError("Missing current client file "+str(fid))
            extraction.append({"id":int(fid),"file":str(path.relative_to(work)),"sha256":digest(path)})
        print("Acquired",len(requests),"current files",flush=True)
    def run(name,*args):
        subprocess.run([sys.executable,str(scripts/name),*args],cwd=work,check=True)
    extract({int(maprow["WdtFileDataID"]):"0.wdt"},private/"wdt")
    run("import-native-catalog.py","terrain")
    source=json.loads((private/"catalog-source.json").read_text())
    source["maps"][0]["tiles"]=[t for t in source["maps"][0]["tiles"] if 30<=t["x"]<=34 and 47<=t["y"]<=51]
    (private/"catalog-source.json").write_text(json.dumps(source))
    requests={}
    for t in source["maps"][0]["tiles"]:
        for key,ext in [("root","adt"),("objects","adt"),("layers","adt"),("texture","blp")]:
            if t[key]:requests[t[key]]=f"{t[key]}.{ext}"
    extract(requests)
    run("import-native-catalog.py","models")
    def extract_list(name):
        rows={}
        for line in (private/name).read_text().splitlines():
            fid,filename=line.split(";",1);rows[int(fid)]=filename
        extract(rows)
        return len(rows)
    extract_list("models.list")
    for _ in range(8):
        run("native_dependencies.py")
        if not extract_list("dependencies.list"):break
    else:raise RuntimeError("Model dependency closure did not converge")
    # tex0 MDID is authoritative for the terrain textures actually used.
    sys.path.insert(0,str(scripts))
    import native_formats as nf
    textures=set()
    for t in source["maps"][0]["tiles"]:
        textures.update(nf.uints(dict(nf.chunks((assets/f"{t['layers']}.adt").read_bytes())).get("MDID",b"")))
    extract({fid:f"{fid}.blp" for fid in textures if fid})
    run("import-native-terrain.py")
    if a.terrain_mode=="splat":
        run("import-native-splat.py")
        report=json.loads((world/"splat-report.json").read_text())
        if report["failures"] or report["missingTextures"]:raise RuntimeError("Advanced terrain bake is incomplete")
    # The unchanged renderer explicitly falls back to native ground.webp when
    # layers are absent. This supported path needs no importer correction.
    run("import-native-lighting.py")
    if a.terrain_mode=="map-textures":
        mapfile=world/"0/map.json";detail=json.loads(mapfile.read_text())
        for tile in detail["tiles"]:tile.update(layers=False,water=False)
        mapfile.write_text(json.dumps(detail))

    # Lighting can add current skybox M2s to the model list.
    run("import-native-catalog.py","models");extract_list("models.list")
    for _ in range(8):
        run("native_dependencies.py")
        if not extract_list("dependencies.list"):break
    run("import-native-models.py","--kind","wmo","--retry")
    run("import-native-models.py","--kind","m2","--retry")
    run("bake-tileset-normals.py")
    extract({130561:"130561.blp",130628:"130628.blp"})
    run("import-native-sky.py")
    # This canned scene has no actor simulation or generated grass layer.
    (world/"ground-effects.json").write_text(json.dumps({"build":version,"effects":{},"doodads":{}}))
    (world/"weather.json").write_text('{"rows":[]}')
    (world/"liquids.json").write_text('{"kinds":{}}')
    for name in ["package.json","index.html","vite.config.ts"]:
        shutil.copyfile(app/name,work/name)
    public=work/"public"
    if public.is_junction():
        if public.resolve()!=app/"public":raise RuntimeError("Unexpected public junction")
        public.rmdir()  # remove the junction itself, never its target
    public.mkdir(exist_ok=True)
    source=work/"src"
    if source.is_junction():
        if source.resolve()!=app/"src":raise RuntimeError("Unexpected source junction")
        source.rmdir()
    shutil.copytree(app/"src",source,dirs_exist_ok=True)
    for name in ["node_modules"]:
        target=work/name
        if not target.exists():
            subprocess.run(["powershell","-NoProfile","-Command","New-Item -ItemType Junction -Path '"+str(target).replace("'","''")+"' -Target '"+str(app/name).replace("'","''")+"' | Out-Null"],check=True)
    # Retained scratch files still belong to this verified identity; hash the whole acquired closure.
    extraction=[{"id":int(p.stem),"file":str(p.relative_to(work)),"sha256":digest(p)} for p in sorted(assets.iterdir()) if p.is_file() and p.stem.isdigit()]
    extraction.append({"id":int(maprow["WdtFileDataID"]),"file":str((private/"wdt/0.wdt").relative_to(work)),"sha256":digest(private/"wdt/0.wdt")})
    provenance={"identity":identity,"terrainMode":a.terrain_mode,"appCommit":subprocess.check_output(["git","-C",str(app),"rev-parse","HEAD"],text=True).strip(),"scripts":script_inputs,"rendererSource":[{"file":str(p.relative_to(work)),"sha256":digest(p)} for p in sorted(source.rglob("*")) if p.is_file()],"tables":[{"table":p.name,"sha256":digest(p)} for p in sorted(db2.glob("*.csv"))],"extraction":extraction,
      "outputs":[{"file":str(p.relative_to(work)),"sha256":digest(p)} for p in sorted(world.rglob("*")) if p.is_file()],
      "limitations":["Current client scenery through the existing isometric renderer, not a native game screenshot.","No player/actor simulation, procedural grass, UI, live names or realm saves in the canned scene.","Terrain uses native map textures when the supported map-textures path is selected; advanced terrain layers/liquids are outside that capture."]}
    (work/"capture-inputs.json").write_text(json.dumps(provenance,indent=2)+"\n")
    print("Current isolated scene ready:",work,flush=True)
if __name__=="__main__":main()
