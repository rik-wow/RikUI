"""Lossless deterministic bounded partitions of validated directed polygon graphs."""
import collections,copy,hashlib,json,math
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)
def normalize(polygons):
    nodes={}
    for raw in polygons:
        node=copy.deepcopy(raw);pid=node['id']
        if type(pid) is not int or pid<=0 or pid in nodes:raise ValueError('invalid polygon identity')
        if not node.get('points'):raise ValueError('missing polygon geometry')
        node['portals']=sorted(node.get('portals',[]),key=lambda p:(p['to'],canonical(p)))
        nodes[pid]=node
    if not nodes:raise ValueError('empty graph')
    for node in nodes.values():
        if any(p['to'] not in nodes for p in node['portals']):raise ValueError('dangling portal')
    canonical(list(nodes.values()))
    return dict(sorted(nodes.items()))
def components(ids,adjacency):
    allowed=set(ids);forward={i:sorted(set(adjacency[i])&allowed) for i in ids};reverse={i:[] for i in ids}
    for i in ids:
        for j in forward[i]:reverse[j].append(i)
    seen=set();finished=[]
    for root in sorted(ids):
        if root in seen:continue
        seen.add(root);stack=[(root,iter(forward[root]))]
        while stack:
            vertex,children=stack[-1];child=next(children,None)
            if child is None:finished.append(vertex);stack.pop()
            elif child not in seen:seen.add(child);stack.append((child,iter(forward[child])))
    seen=set();groups=[]
    for root in reversed(finished):
        if root in seen:continue
        seen.add(root);stack=[root];group=[]
        while stack:
            vertex=stack.pop();group.append(vertex)
            for child in reverse[vertex]:
                if child not in seen:seen.add(child);stack.append(child)
        groups.append(sorted(group))
    return sorted(groups,key=lambda g:g[0])
def bounds(nodes):
    pts=[p for node in nodes for p in node['points']]
    return {'min':[min(p[a] for p in pts) for a in range(3)],'max':[max(p[a] for p in pts) for a in range(3)]}
def edge_records(nodes,owners,component):
    seams=[];links=[];ordinal=0
    for pid,node in nodes.items():
        for portal in node['portals']:
            ordinal+=1;target=portal['to']
            row=dict(id='edge-%09d'%ordinal,fromRegion=owners[pid],toRegion=owners[target],
                fromPolygon=pid,toPolygon=target,fromComponent=component[pid],toComponent=component[target],portal=copy.deepcopy(portal))
            if owners[pid]!=owners[target]:seams.append(row)
            if component[pid]!=component[target]:links.append(copy.deepcopy(row))
    return seams,links
def partition_graph(polygons,metadata,*,max_polygons=8192,max_portals=32768,cell_size=None):
    if type(max_polygons) is not int or not 1<=max_polygons<=8192 or type(max_portals) is not int or not 1<=max_portals<=32768:
        raise ValueError('invalid partition caps')
    nodes=normalize(polygons);canonical(metadata)
    adjacency={i:[p['to'] for p in n['portals']] for i,n in nodes.items()}
    neighbors={i:set(targets) for i,targets in adjacency.items()}
    for i,targets in adjacency.items():
        if len(targets)>max_portals:raise ValueError('polygon exceeds outgoing portal cap')
        for target in targets:neighbors[target].add(i) # Packing locality only; never an inferred edge.
    remaining=set(nodes);groups=[]
    for seed in nodes:
        if seed not in remaining:continue
        queue=collections.deque([seed]);queued={seed};group=[];count=0
        while queue and len(group)<max_polygons:
            pid=queue.popleft()
            if pid not in remaining or count+len(adjacency[pid])>max_portals:continue
            group.append(pid);remaining.remove(pid);count+=len(adjacency[pid])
            for target in sorted(neighbors[pid]):
                if target in remaining and target not in queued:queued.add(target);queue.append(target)
        if not group:raise ValueError('partition made no progress')
        groups.append(sorted(group))
    if cell_size is not None:
        if type(cell_size) not in (int,float) or not 64<=cell_size<=1024:raise ValueError('invalid spatial partition size')
        bins={}
        for pid,node in nodes.items():
            center=[sum(p[a] for p in node['points'])/len(node['points']) for a in (0,2)]
            origin=metadata.get('bounds',[0,0])
            bins.setdefault(tuple(math.floor((v-origin[a])/cell_size) for a,v in enumerate(center)),[]).append(pid)
        groups=[]
        for key in sorted(bins):
            group=[];portals=0
            for pid in bins[key]:
                cost=len(adjacency[pid])
                if group and (len(group)>=max_polygons or portals+cost>max_portals):
                    groups.append(group);group=[];portals=0
                group.append(pid);portals+=cost
            if group:groups.append(group)
    owners={};component={};packs=[];regions=[]
    for number,group in enumerate(groups,1):
        rid='region-%04d'%number;owned=set(group);parts=[]
        for pid in group:owners[pid]=rid
        for index,members in enumerate(components(group,adjacency),1):
            cid='%s:scc-%04d'%(rid,index);parts.append(dict(id=cid,polygonIDs=members))
            for pid in members:component[pid]=cid
        packed=[]
        for pid in group:
            row=copy.deepcopy(nodes[pid]);row['portals']=[p for p in row['portals'] if p['to'] in owned];packed.append(row)
        internal=sum(len(p['portals']) for p in packed);outgoing=sum(len(adjacency[pid]) for pid in group)
        regions.append(dict(id=rid,polygonIDs=group,bounds=bounds(packed),polygonCount=len(group),
            internalPortalCount=internal,outgoingPortalCount=outgoing,seamCount=outgoing-internal,components=parts))
        packs.append(dict(id=rid,metadata=copy.deepcopy(metadata),polygons=packed))
    seams,links=edge_records(nodes,owners,component)
    catalog=dict(schema='rikui-terrain-region-catalog-v1',metadata=copy.deepcopy(metadata),
        graphSha256=hashlib.sha256(canonical(dict(metadata=metadata,polygons=list(nodes.values()))).encode()).hexdigest(),
        limits=dict(maxPolygons=max_polygons,maxOutgoingPortals=max_portals),polygonCount=len(nodes),
        portalCount=sum(len(n['portals']) for n in nodes.values()),regions=regions,seams=seams,componentLinks=links,
        polygonOwners=[dict(id=i,region=owners[i],component=component[i]) for i in nodes])
    if cell_size is not None:catalog['spatialCellSize']=cell_size
    return dict(catalog=catalog,packs=packs)
def verify_partition(polygons,metadata,result):
    def need(ok,reason):
        if not ok:raise ValueError(reason)
    original=normalize(polygons);catalog=result['catalog'];packs=result['packs']
    need(catalog['schema']=='rikui-terrain-region-catalog-v1','wrong schema')
    need(canonical(catalog['metadata'])==canonical(metadata),'metadata mismatch')
    regions={r['id']:r for r in catalog['regions']}
    need(len(regions)==len(catalog['regions'])==len(packs),'duplicate/missing region')
    restored={};owners={};component={};pack_ids=set();limits=catalog['limits']
    need(type(limits['maxPolygons']) is int and 1<=limits['maxPolygons']<=8192,'invalid polygon cap')
    need(type(limits['maxOutgoingPortals']) is int and 1<=limits['maxOutgoingPortals']<=32768,'invalid portal cap')
    for pack in packs:
        rid=pack['id'];need(rid in regions and rid not in pack_ids,'invalid pack ID');pack_ids.add(rid)
        need(canonical(pack['metadata'])==canonical(metadata),'pack metadata mismatch')
        region=regions[rid];packed=normalize(pack['polygons'])
        need(list(packed)==region['polygonIDs'],'polygon index mismatch')
        need(len(packed)<=limits['maxPolygons'] and region['polygonCount']==len(packed),'polygon count/cap')
        need(region['bounds']==bounds(list(packed.values())),'bounds mismatch')
        need(region['internalPortalCount']==sum(len(n['portals']) for n in packed.values()),'internal portal count')
        adjacency={i:[p['to'] for p in n['portals']] for i,n in packed.items()}
        expected=[dict(id='%s:scc-%04d'%(rid,i),polygonIDs=group) for i,group in enumerate(components(list(packed),adjacency),1)]
        need(region['components']==expected,'incorrect directed components')
        for c in expected:
            for pid in c['polygonIDs']:component[pid]=c['id']
        for pid,node in packed.items():
            need(pid not in restored,'duplicate owner');restored[pid]=node;owners[pid]=rid
    need(set(restored)==set(original),'polygon set mismatch')
    for seam in catalog['seams']:
        pid=seam['fromPolygon'];target=seam['toPolygon']
        need(pid in restored and target in restored,'unresolved seam')
        need(owners[pid]!=owners[target] and seam['fromRegion']==owners[pid] and seam['toRegion']==owners[target],'seam owner')
        need(seam['portal']['to']==target,'seam target');restored[pid]['portals'].append(copy.deepcopy(seam['portal']))
    restored=normalize(list(restored.values()))
    need(canonical(list(restored.values()))==canonical(list(original.values())),'changed geometry or directed edges')
    seams,links=edge_records(original,owners,component)
    need(catalog['seams']==seams and catalog['componentLinks']==links,'seam/component identity')
    need(catalog['polygonOwners']==[dict(id=i,region=owners[i],component=component[i]) for i in original],'owner index')
    for region in regions.values():
        outgoing=sum(len(original[i]['portals']) for i in region['polygonIDs'])
        need(outgoing<=limits['maxOutgoingPortals'] and region['outgoingPortalCount']==outgoing,'outgoing cap/count')
        need(region['seamCount']==outgoing-region['internalPortalCount'],'seam count')
    need(catalog['polygonCount']==len(original) and catalog['portalCount']==sum(len(n['portals']) for n in original.values()),'catalog counts')
    digest=hashlib.sha256(canonical(dict(metadata=metadata,polygons=list(original.values()))).encode()).hexdigest()
    need(catalog['graphSha256']==digest,'graph digest')
    return True
