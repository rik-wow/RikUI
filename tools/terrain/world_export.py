"""Export exact world batches into lazy projected regional/compact addons.
No legacy source admission is bypassed: world batches use their own hash-chain,
exclusion and seam admission before the existing lossless graph/codec builders.
"""
import argparse,copy,importlib,json,pathlib,time
import world_export_graph as graph
import world_projection as projection
import terrain_partition as partition
import compile_backbone as compact
import compile_quest_terrain as compiler
from compile_terrain_regions import encode_polygon
from terrain_contract import runtime_geometry,runtime_metadata
from world_source import canonical,sha,need

def addon_toc(title,files,lazy=True,dependency='RikUI'):
 return ('## Interface: 16001\n## Title: '+title+'\n## AllowLoadGameType: camelot\n## Dependencies: '+dependency+'\n'+('## LoadOnDemand: 1\n' if lazy else '')+'\n'+'\n'.join(files)+'\n').encode()

def regional_files(group):
 ns=group['namespace'];catalog=group['partition']['catalog'];packs=group['partition']['packs'];nodes=group['nodes'];files={};descriptors=[]
 owners={p['id']:index for index,pack in enumerate(packs,1) for p in pack['polygons']};payloads={}
 for index,region in enumerate(catalog['regions'],1):
  rows=[nodes[i] for i in region['polygonIDs']];runtime_geometry(rows);pages=[];part=''
  for row in rows:
   record=encode_polygon(row,owners);need(len(record)<=16384,'world regional record cap')
   if part and len(part)+len(record)>32000:pages.append(part);part=''
   part+=record
  if part:pages.append(part)
  counts={}
  for row in rows:
   for edge in row['portals']:target=owners[edge['to']];counts[target]=counts.get(target,0)+1
  addon='RikUIQuestTerrain_'+ns+'_R%03d'%index
  descriptor=dict(id=index,addon=addon,polygons=len(rows),portals=region['outgoingPortalCount'],bounds=[region['bounds']['min'][0],region['bounds']['min'][2],region['bounds']['max'][0],region['bounds']['max'][2]],neighbors=sorted(k for k in counts if k!=index),edgeCounts=counts,pages=len(pages),bytes=sum(len(v) for v in pages))
  need(len(pages)<=128 and descriptor['bytes']<=4*1024*1024,'world regional page cap');descriptors.append(descriptor);payloads[index]=pages
 views={v['assignmentID']:v for v in group['views']}
 revision=sha(canonical(dict(graph=group['graphSHA256'],regions=descriptors,namespace=ns,sourceSHA256=group['sourceSHA256'],views=views)))
 meta=copy.deepcopy(group['metadata']);meta['counts']=dict(polygons=1,portals=0);runtime_metadata(meta)
 wire=dict(format='rikui-region-catalog-v1',namespace=ns,revision=revision,meta=meta,regions=descriptors,sourceBytes=sum(d['bytes'] for d in descriptors),graphSHA256=group['graphSHA256'],sourceSHA256=group['sourceSHA256'],ownedBounds=group['ownedBounds'],views=views)
 need(wire['sourceBytes']<=128*1024*1024,'world regional source cache cap')
 for descriptor in descriptors:
  names=[]
  for number,page in enumerate(payloads[descriptor['id']],1):
   name='page-%03d.lua'%number;names.append(name)
   body='RikUI.QuestPlanner.Regions.RegisterPage('+compiler.lua(revision)+','+str(descriptor['id'])+','+str(number)+',[['+page+']],'+compiler.lua(ns)+')\n'
   need(len(body.encode())<=32768,'world regional file cap');files[descriptor['addon']+'/'+name]=body.encode()
  files[descriptor['addon']+'/'+descriptor['addon']+'.toc']=addon_toc('RikUI Terrain '+ns+' '+str(descriptor['id']),names)
 return files,wire

def compact_files(group,contracted):
 if contracted is None:return {},None
 catalog=copy.deepcopy(contracted['receipt']['catalog']);old=catalog['addonName'];new='RikUIQuestPaths_'+group['namespace'];files={}
 for name,data in contracted['files'].items():
  if not name.startswith(old+'/') and not name.startswith(old+'_P'):continue
  path=name.replace(old,new)
  if path.endswith('.toc'):
   body=data.decode().replace(old,new)
   if path==new+'/'+new+'.toc':body=body.replace('## Dependencies: RikUIQuestPaths\n','## Dependencies: RikUI\n')
   data=body.encode()
  files[path]=data
 catalog.update(namespace=group['namespace'],addonName=new,sourceSHA256=group['sourceSHA256'],ownedBounds=group['ownedBounds'])
 for part in catalog['loadParts']:part['addon']=part['addon'].replace(old,new)
 return files,catalog

def seam_files(ledger):
 files={};descriptors=[];pairs={}
 for row in ledger:pairs.setdefault((row['worldMapID'],row['fromNamespace'],row['toNamespace']),[]).append(row)
 for (world,first,last),rows in sorted(pairs.items()):
  page=[]
  def emit(selected):
   revision=sha(canonical(selected));addon='RikUIQuestSeams_S'+revision[:16]
   body=('RikUI.QuestPlanner.TerrainPacks.RegisterSeams('+compiler.lua(revision)+','+compiler.lua(selected)+')\n').encode()
   need(len(body)<=32768 and len(selected)<=128,'seam addon page cap')
   files[addon+'/seams.lua']=body;files[addon+'/'+addon+'.toc']=addon_toc('RikUI Physical Seams '+revision[:16],['seams.lua'])
   descriptors.append(dict(fromNamespace=first,toNamespace=last,seamAddon=addon,seamRevision=revision,rows=len(selected),bytes=len(body),worldMapID=world))
  for row in rows:
   trial=page+[row];size=len(('RikUI.QuestPlanner.TerrainPacks.RegisterSeams('+compiler.lua('0'*64)+','+compiler.lua(trial)+')\n').encode())
   if page and (len(trial)>128 or size>32768):emit(page);page=[row]
   else:page=trial
  if page:emit(page)
 return files,descriptors

def prepare_groups(admitted,catalog,max_batches):
 output=[]
 def prepare(names):
  try:
   group=graph.group_graph(admitted,names,catalog);contracted=graph.contract(group)
   regional,wire=regional_files(group);paths,path_catalog=compact_files(group,contracted)
   group.update(files={**regional,**paths},wire=wire,pathCatalog=path_catalog,compact=contracted);output.append(group)
  except ValueError as error:
   resource=any(t in str(error) for t in ('resource bound','exceeds u16','payload record limit','stream exceeds bounds','source cache cap','load group count exceeds','regional page cap'))
   if not resource or len(names)==1:raise
   half=len(names)//2;prepare(names[:half]);prepare(names[half:])
 by_world={}
 for name in sorted(admitted['batches']):
  if admitted['batches'][name]['polygons']:by_world.setdefault(name[0],[]).append(name)
 for world,names in sorted(by_world.items()):
  for start in range(0,len(names),max_batches):prepare(names[start:start+max_batches])
 need(output,'no nonempty admitted geometry');return output

def export(input_path,expected,source_directory,output,max_batches=2290,verify=False):
 admitted=graph.load_input(input_path,expected,source_directory);catalog=projection.Catalog(source_directory);groups=prepare_groups(admitted,catalog,max_batches)
 files={};indices={};owners={};source_to_dense={}
 for group in groups:
  files.update(group['files'])
  for i,key in enumerate(group['sourceKeys'],1):need(key not in owners,'duplicate exported physical owner');owners[key]=group['namespace'];source_to_dense[key]=i
 # Stable source seam identities survive different local dense IDs and preserve
 # exact admitted direction/endpoints. Runtime composition consumes this ledger.
 ledger=[]
 for proof in admitted['seams']:
  proof_hash=sha(canonical(proof))
  for edge in proof['directedLinks']:
   first,last=edge['fromKey'],edge['to']
   if first not in owners or last not in owners or owners[first]==owners[last]:continue
   identity=sha(canonical(dict(worldMapID=proof['worldMapID'],fromKey=first,toKey=last,left=edge['left'],right=edge['right'])))
   ledger.append(dict(id=identity,worldMapID=proof['worldMapID'],fromNamespace=owners[first],toNamespace=owners[last],fromID=source_to_dense[first],toID=source_to_dense[last],fromKey=first,toKey=last,left=edge['left'],right=edge['right'],midpoint=[(a+b)/2 for a,b in zip(edge['left'],edge['right'])],meters=edge['meters'],authoredCenterCost=edge['meters'],proofSHA256=proof_hash))
 ledger.sort(key=lambda r:(r['worldMapID'],r['fromKey'],r['toKey']));seam_raw=canonical(dict(format='rikui-world-pack-seams-v1',inputSHA256=expected,seams=ledger,nativeVerified=False));seam_sha=sha(seam_raw);files['world-pack-seams.json']=seam_raw
 seam_payloads,connections=seam_files(ledger);files.update(seam_payloads)
 for group in groups:
  ns=group['namespace'];wire=group['wire'];wire['seamRevision']=seam_sha;wire['outgoingSeams']=sum(row['fromNamespace']==ns for row in ledger)
  addon='RikUIQuestTerrain_'+ns;body='RikUI.QuestPlanner.Regions.Install('+compiler.lua(wire)+')\n'
  if group['pathCatalog'] is not None:body+='RikUI.QuestPlanner.Paths.Install('+compact.lua(group['pathCatalog'])+')\n'
  files[addon+'/catalog.lua']=body.encode();files[addon+'/'+addon+'.toc']=addon_toc('RikUI Physical Navigation '+ns,['catalog.lua'])
  for view in group['views']:
   ui=view['uiMapID'];index=indices.setdefault(ui,dict(format='rikui-region-map-index-v1',identity=graph.RUNTIME_IDENTITY,uiMapID=ui,bindings=[]))
   binding=next((b for b in index['bindings'] if b['assignmentID']==view['assignmentID']),None)
   if binding is None:binding=copy.deepcopy(view);binding['packs']=[];index['bindings'].append(binding)
   binding['packs'].append(dict(namespace=ns,catalogAddon=addon,catalogRevision=wire['revision'],graphSHA256=group['graphSHA256'],sourceSHA256=group['sourceSHA256'],ownedBounds=group['ownedBounds']))
  audit=dict(format='rikui-world-pack-source-audit-v1',namespace=ns,sourceSHA256=group['sourceSHA256'],graphSHA256=group['graphSHA256'],metadata=group['metadata'],physicalBatches=group['physicalBatches'],sourceKeys=group['sourceKeys'],frontiers=group['frontiers'],views=group['views'],partitionAudit=group['partition']['catalog'],compactProof=group['compact']['receipt']['proof'] if group['compact'] else None,gatewayOriginalIDs=group['compact']['payload']['boundary'] if group['compact'] else [],nativeVerified=False)
  files['audit/'+ns+'.json']=canonical(audit)
 for ui,index in sorted(indices.items()):
  index['bindings'].sort(key=lambda b:b['assignmentID'])
  for binding in index['bindings']:
   binding['packs'].sort(key=lambda p:p['namespace']);names={p['namespace'] for p in binding['packs']}
   binding['connections']=[c for c in connections if c['worldMapID']==binding['worldMapID'] and c['fromNamespace'] in names and c['toNamespace'] in names]
   need(len(binding['connections'])<=1024,'map binding connection descriptor cap')
  index['revision']=sha(canonical(index));addon='RikUIQuestTerrainMap_M%d'%ui
  files[addon+'/index.lua']=('RikUI.QuestPlanner.Regions.InstallIndex('+compiler.lua(index)+')\n').encode();files[addon+'/'+addon+'.toc']=addon_toc('RikUI Navigation Map '+str(ui),['index.lua'])
 tool_names=('world_export','world_export_graph','world_source','world_projection','world_stitch','terrain_partition','benchmark_backbone','compile_backbone','compile_quest_terrain','compile_terrain_regions','terrain_contract','region_contract','coverage_contract')
 compiler_tools={name+'.py':sha(pathlib.Path(importlib.import_module(name).__file__).read_bytes()) for name in tool_names}
 receipt=dict(format='rikui-world-addon-export-v1',identity=graph.RUNTIME_IDENTITY,compilerTools=compiler_tools,bakeTools=admitted['tools'],inputSHA256=expected,exporterSHA256=sha(pathlib.Path(__file__).read_bytes()),graphAdapterSHA256=sha(pathlib.Path(graph.__file__).read_bytes()),sourceProfileSHA256=admitted['sourceProfileSHA256'],placementIndexSHA256=admitted['indexSHA256'],seamSHA256=seam_sha,seams=len(ledger),coverage=admitted['coverage'],sourceGaps=admitted['document']['gaps'],maps=sorted(indices),packs=[dict(namespace=g['namespace'],worldMapID=g['metadata']['worldMapID'],sourceSHA256=g['sourceSHA256'],graphSHA256=g['graphSHA256'],ownedBounds=g['ownedBounds'],polygons=len(g['nodes']),regions=len(g['wire']['regions']),compact=g['pathCatalog'] is not None,sourceBytes=g['wire']['sourceBytes']) for g in groups],files=[dict(path=name,bytes=len(raw),sha256=sha(raw)) for name,raw in sorted(files.items())],nativeVerified=False,agentProfileCalibrated=False)
 files['world-export-receipt.json']=canonical(receipt);compact.write_or_verify(files,output,verify)
 return receipt

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--capture-runs',nargs='+');p.add_argument('--input');p.add_argument('--expected-sha256');p.add_argument('--source-directory');p.add_argument('--output',required=True);p.add_argument('--max-batches',type=int,default=2290);p.add_argument('--verify-output',action='store_true');a=p.parse_args();started=time.monotonic()
 if a.capture_runs:
  need(not a.input and not a.verify_output,'capture/export modes differ');raw=canonical(graph.capture(a.capture_runs))
  with pathlib.Path(a.output).open('xb') as f:f.write(raw)
  print(json.dumps(dict(input=a.output,sha256=sha(raw))));return
 need(a.input and a.expected_sha256 and a.source_directory and 1<=a.max_batches<=2290,'export arguments')
 result=export(a.input,a.expected_sha256,a.source_directory,a.output,a.max_batches,a.verify_output)
 print(json.dumps(dict(output=a.output,maps=result['maps'],packs=len(result['packs']),seams=result['seams'],recordedRunFailures=len(result['sourceGaps']),missingPhysicalJobs=sum(len(v['missingPhysicalJobs']) for v in result['coverage']),seconds=time.monotonic()-started,verified=a.verify_output,nativeVerified=False)))
if __name__=='__main__':main()
