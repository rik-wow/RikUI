"""Admit only exact shared owned/halo geometry with reciprocal baked portals.
Missing neighbour batches remain pending; no proximity stitching exists here.
"""
import argparse,copy,json,math,pathlib,re
from world_source import canonical,sha,need
from world_storage import decode
KEY=re.compile(r'w(\d+):r(-?\d+):(-?\d+):(\d+):p(\d+)\Z')
POLYS_PER_TILE=4096  # bake_world_batch.mjs cap; polygon IDs pack the index in 12 bits
def key(value):
 m=KEY.fullmatch(value);need(m is not None,'invalid world polygon key');return tuple(map(int,m.groups()))
def owner(value):
 world,x,z,layer,poly=key(value);need(layer==0 and poly<POLYS_PER_TILE,'unsupported polygon layer/index');return (world,x//8,z//8)
def signature(poly):return tuple(sorted(tuple(v) for v in poly['points']))
def distance_boundary(point,points):
 best=(math.inf,None)
 for i,a in enumerate(points):
  b=points[(i+1)%len(points)];dx,dz=b[0]-a[0],b[2]-a[2];n=dx*dx+dz*dz
  if n==0:continue
  q=max(0,min(1,((point[0]-a[0])*dx+(point[2]-a[2])*dz)/n));gap=math.hypot(point[0]-a[0]-q*dx,point[2]-a[2]-q*dz)
  if gap<best[0]:best=(gap,a[1]+q*(b[1]-a[1]))
 return best

def validate_poly(poly):
 world,gx,gz,layer,ordinal=key(poly['key']);need(poly.get('grid')==[gx,gz,layer],'polygon grid/key mismatch')
 points=poly['points'];need(type(points) is list and 3<=len(points)<=6,'polygon point count')
 need(all(type(p) is list and len(p)==3 and all(type(v) in (int,float) and math.isfinite(v) and abs(v)<100000 for v in p) for p in points),'polygon points')
 need(len({(p[0],p[2]) for p in points})==len(points),'duplicate polygon vertex')
 need(all(gx*64-.0001<=p[0]<=(gx+1)*64+.0001 and gz*64-.0001<=p[2]<=(gz+1)*64+.0001 for p in points),'polygon outside grid')
 need(type(poly.get('center')) is list and len(poly['center'])==3 and all(type(v) in (int,float) and math.isfinite(v) for v in poly['center']),'polygon center shape')
 turns=[]
 for i,a in enumerate(points):
  b=points[(i+1)%len(points)];c=points[(i+2)%len(points)];v=(b[0]-a[0])*(c[2]-b[2])-(b[2]-a[2])*(c[0]-b[0])
  if abs(v)>1e-7:turns.append(v)
 need(turns and (all(v>0 for v in turns) or all(v<0 for v in turns)),'nonconvex polygon')
 sign=1 if turns[0]>0 else -1
 for i,a in enumerate(points):
  b=points[(i+1)%len(points)];need(all(((b[0]-a[0])*(p[2]-a[2])-(b[2]-a[2])*(p[0]-a[0]))*sign>=-1e-5 for p in points),'nonconvex polygon edges')
 need(all(abs(sum(p[i] for p in points)/len(points)-poly['center'][i])<=.000051 for i in range(3)),'polygon center mismatch')
 need(type(poly.get('portals')) is list and len(poly['portals'])<=32,'portal count')
 seen=set()
 for edge in poly['portals']:
  need(edge['to'] not in seen and edge['to']!=poly['key'],'duplicate/self portal');seen.add(edge['to']);need(key(edge['to'])[0]==world,'cross-world portal')
  need(type(edge.get('meters')) in (int,float) and math.isfinite(edge['meters']) and edge['meters']>0,'portal cost')
  for pt in (edge['left'],edge['right']):
   need(len(pt)==3 and all(type(v) in (int,float) and math.isfinite(v) for v in pt),'portal coordinate')
   gap,height=distance_boundary(pt,points);need(gap<=.002 and abs(pt[1]-height)<=.002,'portal source boundary mismatch')
  need(math.hypot(edge['left'][0]-edge['right'][0],edge['left'][2]-edge['right'][2])>1e-6,'empty portal')

def load(path,expected):
 path=pathlib.Path(path);raw=(path/'manifest.json').read_bytes();need(len(raw)<=16*1024*1024 and sha(raw)==expected,'batch manifest hash')
 m=json.loads(raw);need(m.get('format')=='rikui-world-nav-batch-v1' and m.get('nativeVerified') is False,'batch format')
 need(len(m['files'])==2,'batch file count');records={r['filename']:r for r in m['files']};need(set(records) in ({'polygons.json','boundary-witnesses.json'},{'polygons.json.gz','boundary-witnesses.json.gz'}),'batch file set')
 documents={}
 for name,row in records.items():
  data=(path/name).read_bytes();need(len(data)<=64*1024*1024 and len(data)==row['bytes'] and sha(data)==row['sha256'],'batch payload hash')
  d=json.loads(decode(data,64*1024*1024) if name.endswith('.gz') else data);need(d.get('worldMapID')==m['worldMapID'] and d.get('jobID')==m['job']['id'],'payload identity');documents[name.removesuffix('.gz')]=d['polygons']
 namespace=(m['worldMapID'],*m['job']['batchGrid']);polys={};witnesses={}
 for name,target in [('polygons.json',polys),('boundary-witnesses.json',witnesses)]:
  for row in documents[name]:
   need(row['key'] not in target and key(row['key'])[0]==m['worldMapID'],'polygon identity');validate_poly(row)
   need((owner(row['key'])==namespace)==(name=='polygons.json'),'polygon ownership')
   target[row['key']]=row
 need(len(polys)<=65536 and len(witnesses)<=65536,'batch polygon cap')
 all_polys={**polys,**witnesses}
 for row in polys.values():
  for edge in row['portals']:
   target=all_polys.get(edge['to']);need(target is not None,'batch dangling portal')
   midpoint=[(v+w)/2 for v,w in zip(edge['left'],edge['right'])]
   cost=math.dist(row['center'],midpoint)+math.dist(target['center'],midpoint)
   need(abs(cost-edge['meters'])<=.000051,'portal cost mismatch')
 return dict(manifest=m,namespace=namespace,polygons=polys,witnesses=witnesses,sha256=expected,path=str(path.resolve()))

def shared_interval(forward,reverse):
 a,b=forward['left'],forward['right'];dx,dz=b[0]-a[0],b[2]-a[2];length=math.hypot(dx,dz)
 need(length>1e-6,'empty forward seam interval');axis=0 if abs(dx)>=abs(dz) else 2
 for point in (reverse['left'],reverse['right']):
  need(abs(dx*(point[2]-a[2])-dz*(point[0]-a[0]))/length<=.002,'reciprocal interval off source boundary line')
 f=sorted((a[axis],b[axis]));r=sorted((reverse['left'][axis],reverse['right'][axis]))
 low,high=max(f[0],r[0]),min(f[1],r[1]);need(high-low>1e-6,'disjoint or touch-only seam intervals')
 # Endpoints come from the intersection. Do not round outward or enlarge either
 # baked interval. Y remains the forward/source edge's linear height.
 def at(value):
  if value==a[axis]:return list(a)
  if value==b[axis]:return list(b)
  q=(value-a[axis])/(b[axis]-a[axis]);need(-1e-12<=q<=1+1e-12,'intersection escaped source interval')
  point=[x+(y-x)*q for x,y in zip(a,b)];point[axis]=value;return point
 left,right=(at(low),at(high)) if a[axis]<b[axis] else (at(high),at(low))
 width=math.hypot(left[0]-right[0],left[2]-right[2]);need(width>1e-6,'empty retained seam interval')
 discrepancy=max(abs(f[0]-r[0]),abs(f[1]-r[1]))*length/abs(b[axis]-a[axis])
 return left,right,width,discrepancy

def exact_center(poly):return [sum(float(p[a]) for p in poly['points'])/len(poly['points']) for a in range(3)]

def admit(a,b):
 wa,ax,az=a['namespace'];wb,bx,bz=b['namespace'];need(wa==wb and abs(ax-bx)+abs(az-bz)==1,'batches must share a world and face')
 need(a['manifest']['job']['lattice']==b['manifest']['job']['lattice'],'seam lattice mismatch')
 for field in ('profileSHA256','tileWorklistSHA256','projectionSources'):
  need(a['manifest']['job']['source'][field]==b['manifest']['job']['source'][field],'seam source mismatch')
 for field in ('wrapperSHA256','boundedWrapperSHA256','filterSHA256'):
  need(a['manifest']['generator'][field]==b['manifest']['generator'][field],'seam generator mismatch')
 links=[];matches=set();narrowed=[];maximum=0;minimum=math.inf
 for source,target in ((a,b),(b,a)):
  for row in source['polygons'].values():
   for edge in row['portals']:
    if owner(edge['to'])!=target['namespace']:continue
    other=target['polygons'].get(edge['to']);proof=source['witnesses'].get(edge['to'])
    need(other is not None and proof is not None,'seam missing owner/witness')
    need(signature(proof)==signature(other) and proof['center']==other['center'],'seam witness geometry mismatch')
    back=[e for e in other['portals'] if e['to']==row['key']];need(len(back)==1,'missing reciprocal seam portal')
    reverse=target['witnesses'].get(row['key']);need(reverse is not None and signature(reverse)==signature(row),'reverse witness mismatch')
    left,right,width,discrepancy=shared_interval(edge,back[0]);maximum=max(maximum,discrepancy);minimum=min(minimum,width)
    midpoint=[(v+w)/2 for v,w in zip(left,right)]
    for p in (left,right,midpoint):
     source_gap,source_y=distance_boundary(p,row['points']);gap,y=distance_boundary(p,other['points'])
     need(source_gap<=.002 and abs(p[1]-source_y)<=.002,'seam source boundary/height mismatch')
     need(gap<=.002 and abs(source_y-y)<=1.002,'seam target boundary/step mismatch')
    cost=math.dist(exact_center(row),midpoint)+math.dist(midpoint,exact_center(other))
    normalized=dict(fromKey=row['key'],to=edge['to'],left=left,right=right,meters=cost)
    if left!=edge['left'] or right!=edge['right']:
     narrowed.append(dict(fromKey=row['key'],toKey=edge['to'],original=copy.deepcopy(edge),reciprocal=copy.deepcopy(back[0]),retained=copy.deepcopy(normalized)))
    links.append(normalized);matches.add(edge['to'])
 return dict(format='rikui-world-seam-proof-v1',worldMapID=wa,batches=[dict(namespace=list(x['namespace']),sha256=x['sha256']) for x in (a,b)],
  exactWitnessMatches=len(matches),directedLinks=sorted(links,key=lambda e:(e['fromKey'],e['to'])),normalization=dict(policy='nonzero-intersection-of-reciprocal-baked-portals-v1',narrowedDirectedLinks=len(narrowed),maxEndpointDiscrepancy=maximum,minimumRetainedWidth=minimum if links else 0,records=narrowed),nativeVerified=False)

def main():
 p=argparse.ArgumentParser();p.add_argument('--first',required=True);p.add_argument('--first-sha256',required=True);p.add_argument('--second',required=True);p.add_argument('--second-sha256',required=True);p.add_argument('--output',required=True);a=p.parse_args()
 result=admit(load(a.first,a.first_sha256),load(a.second,a.second_sha256));raw=canonical(result)
 with pathlib.Path(a.output).open('xb') as f:f.write(raw)
 print(json.dumps(dict(matches=result['exactWitnessMatches'],directedLinks=len(result['directedLinks']),sha256=sha(raw))))
if __name__=='__main__':main()
