"""Compile hash-validated canonical topology into lazy bounded regional source pages."""
import argparse,copy,json,pathlib,time
import compile_quest_terrain as compiler
import terrain_partition as partition
from terrain_contract import need,runtime_geometry,runtime_metadata
def encode_polygon(row,owners):
    values=[row['id'],len(row['points']),len(row['portals'])]
    for point in row['points']:values.extend(point)
    for edge in row['portals']:
        values.extend((edge['to'],owners[edge['to']]))
        values.extend(edge['left']);values.extend(edge['right'])
    return ','.join(str(v) for v in values)+'\n'
def compile_regions(manifest,expected,out):
    meta,shards,receipt=compiler.validate(manifest,expected,regional=True)
    polygons=[p for shard in shards for p in shard['polygons']]
    result=partition.partition_graph(polygons,meta,cell_size=256)
    partition.verify_partition(polygons,meta,result)
    catalog=result['catalog'];packs=result['packs']
    need(len(packs)<=256,'regional-catalog-limit')
    owners={p['id']:i for i,pack in enumerate(packs,1) for p in pack['polygons']}
    original={p['id']:p for p in polygons}
    descriptors=[];payloads={}
    for index,(pack,region) in enumerate(zip(packs,catalog['regions']),1):
        rows=[original[i] for i in region['polygonIDs']]
        runtime_geometry(rows)
        pages=[];part=''
        for row in rows:
            encoded=encode_polygon(row,owners)
            need(len(encoded)<=16384,'regional-record-size')
            if part and len(part)+len(encoded)>32768:pages.append(part);part=''
            part+=encoded
        if part:pages.append(part)
        edge_counts={}
        for row in rows:
            for edge in row['portals']:
                target=owners[edge['to']];edge_counts[target]=edge_counts.get(target,0)+1
        neighbors=sorted(target for target in edge_counts if target!=index)
        addon='RikUIQuestTerrain_R%03d'%index
        descriptor=dict(id=index,addon=addon,polygons=len(rows),portals=region['outgoingPortalCount'],
            bounds=[region['bounds']['min'][0],region['bounds']['min'][2],region['bounds']['max'][0],region['bounds']['max'][2]],
            neighbors=neighbors,edgeCounts=edge_counts,pages=len(pages),bytes=sum(len(s) for s in pages))
        need(descriptor['bytes']<=4*1024*1024 and len(pages)<=128,'regional-page-budget')
        descriptors.append(descriptor);payloads[index]=pages
    revision=compiler.sha(partition.canonical(dict(graph=catalog['graphSha256'],regions=descriptors)).encode())
    runtime=copy.deepcopy(meta)
    runtime['exclusions']=[] # Every excluded source polygon/portal was already carved and validated.
    runtime['sourceRegion']={k:v for k,v in runtime['sourceRegion'].items() if k!='tiles'}
    runtime['limitations']=[
        'Canonical full-map topology is carved around recorded collision and liquid exclusions.',
        'A regional working set is a bounded search candidate; missing regions are an explicit frontier.',
        'Native traversal, dynamic access and Forever movement calibration remain unverified.']
    runtime['counts']=dict(polygons=1,portals=0) # Actual admitted window supplies its exact counts.
    runtime_metadata(runtime)
    wire=dict(format='rikui-region-catalog-v1',revision=revision,meta=runtime,regions=descriptors,
        sourceBytes=sum(d['bytes'] for d in descriptors),graphSHA256=catalog['graphSha256'])
    need(wire['sourceBytes']<=128*1024*1024,'regional-source-cache-budget')
    out=pathlib.Path(out).absolute();compiler.output_ready(out);out.mkdir(exist_ok=True)
    written=[]
    def write(relative,body):
        path=out/relative;path.parent.mkdir(parents=True,exist_ok=True);raw=body.encode()
        with path.open('xb') as stream:stream.write(raw)
        written.append(dict(filename=relative,bytes=len(raw),sha256=compiler.sha(raw)))
    write('RikUIQuestTerrain/RikUIQuestTerrain.toc','## Interface: 16001\n## Title: RikUI Quest Terrain Regions\n## Dependencies: RikUI\n\ncatalog.lua\n')
    write('RikUIQuestTerrain/catalog.lua','RikUI.QuestPlanner.Regions.Install('+compiler.lua(wire)+')\n')
    for d in descriptors:
        names=[]
        for index,page in enumerate(payloads[d['id']],1):
            name='page-%03d.lua'%index;names.append(name)
            # Numeric wire bytes require no escaping/evaluation in the runtime parser.
            write(d['addon']+'/'+name,'RikUI.QuestPlanner.Regions.RegisterPage('+compiler.lua(revision)+','+str(d['id'])+','+str(index)+',[['+page+']])\n')
        write(d['addon']+'/'+d['addon']+'.toc','## Interface: 16001\n## Title: RikUI Terrain Region '+str(d['id'])+'\n## Dependencies: RikUI\n## LoadOnDemand: 1\n\n'+'\n'.join(names)+'\n')
    write('partition-audit.json',partition.canonical(catalog)+'\n')
    receipt.update(format='rikui-regional-compile-receipt-v1',catalogRevision=revision,regions=len(descriptors),
        sourceBytes=wire['sourceBytes'],runtimeLimits=dict(polygons=65536,portals=131072),outputs=copy.deepcopy(written))
    write('compile-receipt.json',json.dumps(receipt,indent=2)+'\n')
    return dict(output=str(out),revision=revision,regions=len(descriptors),sourceBytes=wire['sourceBytes'],
        polygons=len(polygons),portals=sum(len(p['portals']) for p in polygons),seams=len(catalog['seams']),
        maxRegionPolygons=max(d['polygons'] for d in descriptors),maxRegionPortals=max(d['portals'] for d in descriptors))
def main():
    p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--expected-sha256',required=True);p.add_argument('--out')
    a=p.parse_args();started=time.perf_counter()
    if a.out:result=compile_regions(a.manifest,a.expected_sha256,a.out)
    else:
        meta,shards,receipt=compiler.validate(a.manifest,a.expected_sha256,regional=True)
        result=dict(validated=True,counts=receipt['counts'],revision=meta['revision'])
    result['seconds']=time.perf_counter()-started;print(json.dumps(result))
if __name__=='__main__':main()
