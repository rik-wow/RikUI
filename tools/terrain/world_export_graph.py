"""Admit stitched physical batches and build lossless bounded export graphs.
The legacy Dun Morogh source admission remains untouched. World batch evidence
has its own exact hash chain, exclusions and cross-batch portal proof.
"""
import copy,json,math,pathlib
import world_stitch as stitch
import world_projection as projection
import terrain_partition as partition
import benchmark_backbone as backbone
import compile_backbone as compact
import compile_quest_terrain as compiler
from world_source import Source,canonical,sha,need
from terrain_contract import runtime_geometry,runtime_metadata
from client_build import RUNTIME_IDENTITY
MAX_BATCHES=2290
MAX_GROUP_POLYGONS=524288

def read(path,expected,cap):
 path=pathlib.Path(path);need(path.is_file() and not path.is_symlink() and 0<path.stat().st_size<=cap,'export input file bound')
 data=path.read_bytes();need(sha(data)==expected,'export input hash mismatch:'+str(path));return data

def capture(runs):
 batches=[];gaps=[];plans=[]
 for path in runs:
  root=pathlib.Path(path).resolve();plan_raw=(root/'plan.json').read_bytes();progress_raw=(root/'progress.json').read_bytes();plan=json.loads(plan_raw);progress=json.loads(progress_raw)
  need(plan.get('format')=='rikui-world-bake-run-v1' and progress.get('planSHA256')==sha(canonical(plan)),'run plan/progress mismatch')
  names=set();need(len(progress['results'])==progress['completed'],'run completion count')
  plans.append(dict(path=str(root),planSHA256=sha(plan_raw),progressSHA256=sha(progress_raw)))
  for row in progress['results']:
   name=row['jobID'];need(name in plan['jobs'] and name not in names and '/' not in name and '\\' not in name,'run job identity');names.add(name)
   receipt_path=root/name/'receipt.json';receipt_raw=read(receipt_path,row['receiptSHA256'],4*1024*1024);receipt=json.loads(receipt_raw)
   need(receipt['input']['tools']==plan['tools'] and receipt['input']['sourceProfileSHA256']==plan['sourceProfileSHA256'] and receipt['input']['indexSHA256']==plan['indexSHA256'],'run receipt source mismatch')
   if receipt['status']=='derived-pending-seam-validation':
    manifest=root/name/'bake/manifest.json';records={r['filename']:r for r in receipt['files']};need('bake/manifest.json' in records,'missing successful bake manifest')
    batches.append(dict(directory=str(manifest.parent),manifestSHA256=records['bake/manifest.json']['sha256'],receiptPath=str(receipt_path),receiptSHA256=sha(receipt_raw)))
   else:gaps.append(dict(jobID=name,status=receipt['status'],reason=receipt.get('error','unknown'),receiptPath=str(receipt_path),receiptSHA256=sha(receipt_raw)))
  gaps.extend(dict(jobID=name,status='not-completed') for name in plan['jobs'] if name not in names)
 need(0<len(batches)<=MAX_BATCHES,'no successful bounded batches')
 return dict(format='rikui-world-export-input-v1',identity=RUNTIME_IDENTITY,runs=plans,batches=sorted(batches,key=lambda r:r['directory']),gaps=gaps)

def validate_receipt(record,batch):
 raw=read(record['receiptPath'],record['receiptSHA256'],4*1024*1024);r=json.loads(raw);root=pathlib.Path(record['receiptPath']).parent.resolve()
 need(r.get('status')=='derived-pending-seam-validation' and r.get('nativeVerified') is False,'unaccepted bake receipt state')
 need(pathlib.Path(record['directory']).resolve()==root/'bake','receipt/bake location mismatch')
 records={e['filename']:e for e in r['files']};need(len(records)==len(r['files']) and 'geometry.json' in records,'receipt file coverage')
 geometry=None
 for name,row in records.items():
  path=(root/name).resolve();need(path.is_relative_to(root),'receipt path escape')
  data=read(path,row['sha256'],256*1024*1024);need(len(data)==row['bytes'],'receipt output size mismatch')
  if name=='geometry.json':geometry=json.loads(data)
 need(batch['manifest']['geometrySHA256']==records['geometry.json']['sha256'],'geometry/manifest hash mismatch')
 need(geometry['job']==batch['manifest']['job'] and geometry['source']==batch['manifest']['source'] and geometry['exclusions']==batch['manifest']['exclusions'],'geometry/manifest evidence mismatch')
 need(sha(canonical(geometry['job']))==r['input']['jobSHA256'] and geometry['job']['source']['profileSHA256']==r['input']['sourceProfileSHA256'] and geometry['source']['placementIndexSHA256']==r['input']['indexSHA256'],'geometry source identity mismatch')
 for generator,tool in [('wrapperSHA256','bake_world_batch.mjs'),('boundedWrapperSHA256','world_tiled.mjs'),('filterSHA256','mesh_filter.mjs')]:
  need(batch['manifest']['generator'][generator]==r['input']['tools'][tool],'generator/receipt tool mismatch')
 need(geometry['source']['parserSHA256']==r['input']['tools']['world_geometry.py'],'geometry parser/receipt mismatch')
 rectangles=[];surfaces=[]
 for row in geometry['exclusions']:
  b=row['bounds'];pad=row['padding'];need(len(b)==2 and len(b[0])==len(b[1])==3 and .5<=pad<=10,'exclusion shape')
  # Unswimmable liquid only excludes up to its surface (mesh_filter.mjs), so
  # a polygon wholly above it (a bridge) is valid.
  (surfaces if row.get('belowSurface') is True else rectangles).append(([b[0][0]-pad,b[0][2]-pad,b[1][0]+pad,b[1][2]+pad],b[1][1]))
 query=compiler.exclusion_index([rect for rect,_ in rectangles])
 below=compiler.exclusion_index([rect for rect,_ in surfaces]);tops={}
 for rect,top in surfaces:tops[tuple(rect)]=max(top,tops.get(tuple(rect),top))
 for row in batch['polygons'].values():
  need(not any(compiler.carve_aabb(row['points'],box) for box in query(row['points'])),'world polygon touches recorded exclusion')
  low=min(p[1] for p in row['points'])
  need(not any(compiler.carve_aabb(row['points'],box) and low<=tops[tuple(box)] for box in below(row['points'])),'world polygon reaches below an unswimmable liquid surface')
 return r

def load_input(path,expected,source_directory=None):
 raw=read(path,expected,8*1024*1024);doc=json.loads(raw);need(doc.get('format')=='rikui-world-export-input-v1' and doc.get('identity')==RUNTIME_IDENTITY,'world export identity')
 rows=doc.get('batches');need(type(rows) is list and 0<len(rows)<=MAX_BATCHES,'world export batch cap')
 batches={};tools=None;source=None;index=None
 for record in rows:
  batch=stitch.load(record['directory'],record['manifestSHA256']);receipt=validate_receipt(record,batch);ns=batch['namespace'];need(ns not in batches,'duplicate physical batch')
  current=(receipt['input']['tools'],receipt['input']['sourceProfileSHA256'],receipt['input']['indexSHA256'])
  if tools is None:tools,source,index=current
  else:need(current==(tools,source,index),'mixed decoder/source/index generations')
  batch['receiptSHA256']=record['receiptSHA256'];batches[ns]=batch
 seams=[]
 for (world,x,z),batch in sorted(batches.items()):
  for other in ((world,x+1,z),(world,x,z+1)):
   if other in batches:seams.append(stitch.admit(batch,batches[other]))
 # Cross-batch links may be exported only if their exact pair was proven above.
 admitted={(e['fromKey'],e['to']):e for proof in seams for e in proof['directedLinks']}
 all_keys={key for b in batches.values() for key in b['polygons']}
 for ns,batch in batches.items():
  for row in batch['polygons'].values():
   for edge in row['portals']:
    if edge['to'] in all_keys and stitch.owner(edge['to'])!=ns:
     normalized=admitted.get((row['key'],edge['to']));need(normalized is not None,'unproven cross-batch edge')
     edge.update({k:normalized[k] for k in ('left','right','meters')})
 coverage=[]
 if source_directory is not None:
  import world_bake
  need(tools==world_bake.hashes(),'bake tools changed; regenerate affected batches')
  root=pathlib.Path(source_directory);first=next(iter(batches.values()))['manifest']['job']['source']
  actual=Source(first['profilePath'],first['profileSHA256'],root,root/'all-projected-world-tile-worklist.csv',root/'inventory.json')
  for ns,batch in batches.items():need(actual.job(*ns)==batch['manifest']['job'],'batch differs from pinned physical source plan')
  for world in sorted({ns[0] for ns in batches}):
   expected_jobs=actual.jobs(world);present={batch['manifest']['job']['id'] for ns,batch in batches.items() if ns[0]==world}
   missing=[j['id'] for j in expected_jobs if j['id'] not in present]
   coverage.append(dict(worldMapID=world,expectedPhysicalJobs=len(expected_jobs),bakedPhysicalJobs=len(present),missingPhysicalJobs=missing,physicalBatchesComplete=not missing,nativeVerified=False))
 return dict(inputSHA256=expected,document=doc,batches=batches,seams=seams,sourceProfileSHA256=source,indexSHA256=index,tools=tools,coverage=coverage)

def view_record(assignment):
 full=assignment.record();ui=full['validUIRectangle'];world=full['validWorldRectangle'];source_sha=projection.SOURCE_HASHES['UiMapAssignment']
 return dict(assignmentID=assignment.id,uiMapID=assignment.ui_map_id,worldMapID=assignment.world_map_id,
  projection=full['projection'],projectionSHA256=sha(canonical(dict(assignment=full,sourceSHA256=source_sha))),
  projectionSourceSHA256=source_sha,validUIRectangle=[ui['minX'],ui['minY'],ui['maxX'],ui['maxY']],
  validWorldRectangle=[world['minX'],world['minZ'],world['maxX'],world['maxZ']],elevationBounds=[world['minY'],world['maxY']])

def group_graph(admitted,names,catalog):
 batches=[admitted['batches'][name] for name in sorted(names)];need(batches,'empty group');world=batches[0]['namespace'][0];need(all(b['namespace'][0]==world for b in batches),'group crosses worlds')
 physical=[dict(namespace=list(b['namespace']),manifestSHA256=b['sha256'],receiptSHA256=b['receiptSHA256']) for b in batches]
 source_hash=sha(canonical(dict(format='rikui-world-graph-source-v1',worldMapID=world,batches=physical,sourceProfileSHA256=admitted['sourceProfileSHA256'],placementIndexSHA256=admitted['indexSHA256'],seamPolicySHA256=sha(pathlib.Path(stitch.__file__).read_bytes()),seamProofs=[sha(canonical(proof)) for proof in admitted['seams'] if any(tuple(r['namespace']) in names for r in proof['batches'])])))
 if len(names)==1:
  _,x,z=names[0];token=lambda v:('n' if v<0 else 'p')+str(abs(v));namespace='W%d_X%s_Z%s'%(world,token(x),token(z))
 else:namespace='W%d_G%s'%(world,source_hash[:16])
 bounds=[min(b['manifest']['job']['ownedXZ'][i] for b in batches) if i<2 else max(b['manifest']['job']['ownedXZ'][i] for b in batches) for i in range(4)]
 intersects=lambda r:bounds[0]<r[2] and bounds[2]>r[0] and bounds[1]<r[3] and bounds[3]>r[1]
 views=[view_record(a) for a in catalog.assignments if a.world_map_id==world and a.supported and intersects([a.game_y_min,a.game_x_min,a.game_y_max,a.game_x_max])]
 need(views,'physical group has no acquired projection binding');views.sort(key=lambda r:r['assignmentID']);base=views[0]
 source_polys={k:p for b in batches for k,p in b['polygons'].items()};need(0<len(source_polys)<=MAX_GROUP_POLYGONS,'group polygon resource bound')
 ordered=sorted(source_polys,key=stitch.key);mapping={key:i for i,key in enumerate(ordered,1)};nodes=[];frontiers=[]
 for key in ordered:
  row=source_polys[key];portals=[]
  for edge in row['portals']:
   if edge['to'] in mapping:portals.append(dict(to=mapping[edge['to']],left=list(map(float,edge['left'])),right=list(map(float,edge['right']))))
   else:frontiers.append(dict(fromKey=key,fromID=mapping[key],**edge))
  nodes.append(dict(id=mapping[key],points=[list(map(float,p)) for p in row['points']],portals=portals))
 meta=dict(format='rikui-navmesh-v1',identity=RUNTIME_IDENTITY,revision=source_hash,uiMapID=base['uiMapID'],worldMapID=world,
  source=dict(sha256=source_hash,parser='rikui-world-export-v1',profileSHA256=admitted['sourceProfileSHA256']),projection=base['projection'],
  counts=dict(polygons=len(nodes),portals=sum(len(n['portals']) for n in nodes)),exclusions=[],bounds=bounds,blockers=[],coverageScope='outside-exclusions',
  modeledMaxStep=1,nativeVerified=False,agentProfileCalibrated=False,agentProfile='classic-reference-step-v1',
  sourceRegion=dict(kind='world-batch-group',regionID=namespace,batches=len(batches),sourceSHA256=source_hash),
  limitations=['Validated static source graph outside recorded exclusions; native traversal remains unverified.',
   'Missing batches and pack boundaries are explicit coverage frontiers; no edge is inferred from proximity.',
   'Dynamic obstacles, phasing, swimming, transport and calibrated Forever physics remain unmodeled.'])
 runtime_metadata(meta);normalized=partition.normalize(nodes)
 graph_hash=sha(partition.canonical(dict(metadata=meta,polygons=list(normalized.values()))).encode())
 result=partition.partition_graph(list(normalized.values()),meta,cell_size=256);partition.verify_partition(list(normalized.values()),meta,result)
 need(len(result['packs'])<=256,'group region resource bound')
 for pack in result['packs']:runtime_geometry(pack['polygons'])
 return dict(namespace=namespace,metadata=meta,nodes=normalized,partition=result,graphSHA256=graph_hash,sourceSHA256=source_hash,
  ownedBounds=bounds,views=views,physicalBatches=physical,sourceKeys=ordered,frontiers=frontiers)

def contract_gateways(adjacency,owners,required=()):
 # Promote external seam endpoints in addition to ordinary regional gateways.
 # Every shortcut is still an exact directed, region-confined Dijkstra witness.
 boundary=set(required);need(boundary<=set(adjacency),'required gateway missing from graph')
 network={};local={};trees={};used=set()
 for node,edges in adjacency.items():
  local.setdefault(owners[node],set())
  for target,cost,edge in edges:
   if owners[node]!=owners[target]:
    boundary.update((node,target));network.setdefault(node,[]).append((target,cost,edge));used.add(edge)
 for node in boundary:local[owners[node]].add(node);network.setdefault(node,[])
 for root in sorted(boundary):
  distances,parents,_=backbone.dijkstra(adjacency,{root:0},owners,owners[root]);selected={}
  for target in sorted(local[owners[root]]-{root}):
   if target not in distances:continue
   network[root].append((target,distances[target],None));cursor=target
   while cursor!=root and cursor not in selected:
    prior,edge=parents[cursor];selected[cursor]=(prior,edge);used.add(edge);cursor=prior
  trees[root]=[[node,*selected[node]] for node in sorted(selected)]
 return network,trees,used,boundary

def contract(group):
 nodes=group['nodes'];catalog=group['partition']['catalog'];owners={r['id']:r['region'] for r in catalog['polygonOwners']}
 centers={i:tuple(sum(p[a] for p in row['points'])/len(row['points']) for a in range(3)) for i,row in nodes.items()};adjacency={};geometry={};edge_id=0
 for ident,row in nodes.items():
  adjacency[ident]=[]
  for portal in row['portals']:
   edge_id+=1;target=portal['to'];mid=tuple((portal['left'][a]+portal['right'][a])/2 for a in range(3));cost=math.dist(centers[ident],mid)+math.dist(mid,centers[target])
   geometry[edge_id]=(ident,target,*mid);adjacency[ident].append((target,cost,edge_id))
 network,trees,used,boundary=contract_gateways(adjacency,owners,{row['fromID'] for row in group['frontiers']})
 if not boundary:return None
 vertices=set(boundary)
 for edge in used:vertices.update(geometry[edge][:2])
 payload=dict(format='rikui-backbone-benchmark-v1',graphSHA256=group['graphSHA256'],sourceManifestSHA256=group['sourceSHA256'],partitionAuditSHA256=sha(partition.canonical(catalog).encode()),metadata=group['metadata'],boundary=sorted(boundary),network={str(k):[[target,cost] for target,cost,_ in v] for k,v in sorted(network.items())},trees={str(k):v for k,v in trees.items()},geometry={str(k):list(geometry[k]) for k in sorted(used)},centers={str(k):list(centers[k]) for k in sorted(vertices)})
 surfaces=compact.pack_surface_geometry(payload,nodes,group['sourceSHA256'],group['graphSHA256'])
 files,receipt=compact.build_files(payload,sha(compact.canonical(payload)),surfaces)
 return dict(files=files,receipt=receipt,payload=payload)
