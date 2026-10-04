"""Compile bounded gear-source references joined to exact-client equipment slots.

Inputs are acquired outside the repository. Only the compiled factual index is
distributed; no client files, artwork, player cache or submitted code is bundled.
Maintained QuestieDB sources are references, not verified Forever reward payouts.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

INVENTORY_SLOTS = {1:[1],2:[2],3:[3],5:[5],6:[6],7:[7],8:[8],9:[9],10:[10],
    11:[11,12],12:[13,14],13:[16,17],14:[17],15:[18],16:[15],17:[16],
    20:[5],21:[16],22:[17],23:[17],25:[18],26:[18],28:[18]}
# Reviewed classic dungeon/raid areas; additions require a source review.
DUNGEONS = {1581:"The Deadmines",718:"Wailing Caverns",2437:"Ragefire Chasm",
    209:"Shadowfang Keep",717:"The Stockade",719:"Blackfathom Deeps",1337:"Uldaman",
    721:"Gnomeregan",491:"Razorfen Kraul",722:"Razorfen Downs",796:"Scarlet Monastery",
    1176:"Zul'Farrak",1477:"Sunken Temple",2100:"Maraudon",1583:"Blackrock Spire",
    1584:"Blackrock Depths",2057:"Scholomance",2017:"Stratholme",2557:"Dire Maul"}
QUEST_FIELDS = ["name","requiredLevel","requiredMaxLevel","requiredClasses","requiredRaces",
    "preQuestGroup","preQuestSingle","exclusiveTo","parentQuest","nextQuestInChain",
    "requiredSkill","requiredMinRep","requiredMaxRep","requiredSpell","requiredSpecialization",
    "availableUntilCompleted","availableStartingWith","disabledByQuest","requiredRanks",
    "zoneOrSort","questFlags","questLevel"]
def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def array(raw):
    if raw is None: return []
    if isinstance(raw,list): return raw
    if not isinstance(raw,dict): raise ValueError("Expected positional data")
    return [raw[str(i)] for i in range(1,len(raw)+1)]
def ids(raw):
    values=array(raw)
    if len(values)>4096 or any(type(x) is not int or not 0<x<2**31 for x in values):
        raise ValueError("Invalid source IDs")
    return sorted(set(values))
def clean(value):
    if isinstance(value,dict):
        if all(str(k).isdigit() for k in value) and set(value)=={str(i) for i in range(1,len(value)+1)}:
            return [clean(x) for x in array(value)]
        return {k:clean(v) for k,v in value.items()}
    if isinstance(value,list):return [clean(x) for x in value]
    if isinstance(value,str):
        if len(value)>2048 or any(ord(x)<32 for x in value):raise ValueError("Invalid text")
        return value.replace("|","")
    return value
def lua(value):
    if value is None:return "nil"
    if value is True:return "true"
    if value is False:return "false"
    if isinstance(value,(int,float)):return str(value)
    if isinstance(value,str):return '"'+value.replace("\\","\\\\").replace('"','\\"')+'"'
    if isinstance(value,list):return "{"+",".join(lua(x) for x in value)+"}"
    if isinstance(value,dict):
        return "{"+",".join("["+lua(int(k) if str(k).isdigit() else k)+"]="+lua(v) for k,v in sorted(value.items(),key=lambda x:str(x[0])))+"}"
    raise ValueError("Unsupported value")
def compile_catalog(provider,items,sparse,identity):
    if provider.get("provider",{}).get("flavor")!="Forever":raise ValueError("Wrong provider")
    if not re.fullmatch(r"1\.\d+\.\d+\.\d+",identity.get("build","")):raise ValueError("Invalid client identity")
    base=provider["base"]; quests=base["quests"]; npcs=base["npcs"]
    result={}; slot_index={}; needed=set(); sources=0
    for key,row in sorted(base["items"].items(),key=lambda x:int(x[0])):
        meta=items.get(key)
        if not meta or meta.get("ClassID") not in (2,4):continue
        slots=INVENTORY_SLOTS.get(meta.get("InventoryType"))
        if not slots:continue
        src=[]
        for qid in ids(row.get("questRewards")):
            if str(qid) in quests:
                src.append({"kind":"quest","id":qid,"name":quests[str(qid)]["name"],"authority":"reference"})
                needed.add(qid)
        drop_ids=ids(row.get("npcDrops"))
        # Broad world drops are not a curated encounter recommendation.
        for nid in (drop_ids if len(drop_ids)<=20 else []):
            npc=npcs.get(str(nid),{}); area=npc.get("zoneID")
            if area in DUNGEONS and npc.get("rank",0)>=1:
                src.append({"kind":"dungeon","id":nid,"name":npc.get("name","Unknown encounter"),
                    "area":area,"dungeon":DUNGEONS[area],"authority":"reference"})
        if not src:continue
        if len(src)>32:raise ValueError("Item source bound")
        native=sparse.get(key,{})
        result[key]={"name":native.get("Display_lang") or row["name"],"inventoryType":meta["InventoryType"],
            "classID":meta["ClassID"],"subclassID":meta["SubclassID"],"icon":meta["IconFileDataID"],
            "level":native.get("RequiredLevel",row.get("requiredLevel",0)),
            "itemLevel":native.get("ItemLevel",row.get("itemLevel",0)),
            "metadataAuthority":"client" if native else "reference","sources":src,
            "quality":native.get("OverallQualityID"),"classes":native.get("AllowableClass"),
            "skill":native.get("RequiredSkill",0),"skillRank":native.get("RequiredSkillRank",0)}
        sources+=len(src)
        for slot in slots:slot_index.setdefault(slot,[]).append(int(key))
    # Complete prerequisite closure, including alternatives; no arbitrary flattening.
    pending=list(needed)
    while pending:
        qid=pending.pop()
        rows=[quests.get(str(qid),{})]+[v.get("quests",{}).get(str(qid),{}) for v in provider["variants"]]
        for row in rows:
            for field in ("preQuestGroup","preQuestSingle"):
                for child in ids([abs(x) for x in array(row.get(field))]):
                    if child not in needed:needed.add(child);pending.append(child)
    quest_index={str(qid):clean({k:v for k,v in quests[str(qid)].items() if k in QUEST_FIELDS})
        for qid in sorted(needed) if str(qid) in quests}
    variants={}
    for v in provider["variants"]:
        changes={qid:clean({k:x for k,x in r.items() if k in QUEST_FIELDS})
            for qid,r in v["quests"].items() if int(qid) in needed}
        selector=v["selector"]
        variants[selector["faction"]+"/"+selector["classFile"]]={"quests":changes,
            "removed":[qid for qid in v.get("questsRemoved",[]) if qid in needed]}
    if len(result)>10000 or len(quest_index)>8192 or sources>32768:raise ValueError("Catalog capacity")
    for slot,values in slot_index.items():
        values.sort(key=lambda i:(result[str(i)]["level"],i))
    return {"version":1,"identity":identity,"items":clean(result),"slots":slot_index,"quests":quest_index,
        "variants":variants,"counts":{"items":len(result),"sources":sources,"quests":len(quest_index)},
        "coverage":"Maintained source references; rewards and drops may change. Live client offers take precedence. Curated classic dungeons; new dungeons and complete world coverage are unknown."}
def main():
    p=argparse.ArgumentParser();p.add_argument("--inputs",type=Path,required=True)
    p.add_argument("--build",required=True);p.add_argument("--output",type=Path,required=True)
    args=p.parse_args(); root=args.inputs.resolve(); output=args.output.resolve()
    repo=Path(__file__).resolve().parents[1]
    if output.is_relative_to(repo):raise ValueError("Use external output, then apply reviewed files through Workbench")
    receipt=json.loads((root/"item-inputs.json").read_text())
    if receipt["build"]!=args.build:raise ValueError("Client provenance mismatch")
    for name in ("Item","ItemSparse"):
        for suffix,key in (("json","jsonSHA256"),("db2","db2SHA256"),("dbd","dbdSHA256")):
            if digest(root/(name+"."+suffix))!=receipt["tables"][name][key]:raise ValueError("Input hash mismatch: "+name)
    manifest=json.loads((root/"provider.manifest.json").read_text())
    if digest(root/"provider.json")!=manifest["exportSha256"]:raise ValueError("Provider hash mismatch")
    identity={"build":args.build,"providerRevision":manifest["revision"],"providerSHA256":manifest["exportSha256"],
        "definitionsRevision":receipt["definitionsRevision"],"items":receipt["tables"],"compilerSHA256":digest(__file__)}
    data=compile_catalog(json.loads((root/"provider.json").read_text(encoding="utf-8")),
        json.loads((root/"Item.json").read_text()),json.loads((root/"ItemSparse.json").read_text()),identity)
    text="-- Generated factual gear index. See docs/gear-goals-data.md for authority and coverage.\nRikUI.GearCatalog="+lua(data).replace("},[","},\n[")+"\n"
    if len(text.encode())>4*1024*1024:raise ValueError("Compiled index exceeds 4 MiB")
    output.mkdir(parents=True,exist_ok=True)
    (output/"gear-catalog.lua").write_text(text,encoding="utf-8",newline="\n")
    (output/"gear-catalog.json").write_text(json.dumps(data,ensure_ascii=False,sort_keys=True)+"\n",encoding="utf-8")
    # Keep each distribution file and Workbench write below 200 KiB.
    parts=[]
    root_data={**data,"items":{},"quests":{}}
    parts.append(("gear-catalog.lua","RikUI.GearCatalog="+lua(root_data)+"\n"))
    for field in ("items","quests"):
        batch={};size=0;part=1
        for key,value in data[field].items():
            length=len(lua({key:value}).encode())
            if batch and size+length>180000:
                parts.append((f"gear-{field}-{part}.lua",f"local t=RikUI.GearCatalog.{field}\nfor id,row in pairs("+lua(batch)+") do t[id]=row end\n"))
                batch={};size=0;part+=1
            batch[key]=value;size+=length
        if batch:parts.append((f"gear-{field}-{part}.lua",f"local t=RikUI.GearCatalog.{field}\nfor id,row in pairs("+lua(batch)+") do t[id]=row end\n"))
    for name,content in parts:
        content="-- Generated factual gear index; docs/gear-goals-data.md\n"+content.replace("},[","},\n[")
        if len(content.encode())>200000:raise ValueError("Distribution part too large")
        (output/name).write_text(content,encoding="utf-8",newline="\n")
    (output/"parts.json").write_text(json.dumps([name for name,_ in parts])+"\n")
    print(json.dumps({**data["counts"],"bytes":len(text.encode()),"sha256":digest(output/"gear-catalog.lua")}))
if __name__=="__main__":main()
