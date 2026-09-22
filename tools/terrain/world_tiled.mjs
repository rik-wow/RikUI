// Canonical per-tile triangle inputs make independently generated batch halos
// reproducible. Fixed world-rounded geometry and one common vertical lattice.
import {Raw,VerticesArray,TrianglesArray,ChunkIdsArray,RecastChunkyTriMesh,RecastBuildContext,
 NavMesh,NavMeshParams,Detour,statusFailed,statusToReadableString,freeHeightfield,freeCompactHeightfield,
 freeContourSet,freePolyMesh,freePolyMeshDetail} from '@recast-navigation/core';
import {buildTiledNavMeshRcConfig,generateTileNavMeshData,tiledNavMeshGeneratorConfigDefaults} from '@recast-navigation/generators';
const compare=(a,b)=>{for(let i=0;i<a.length;i++)if(a[i]!==b[i])return a[i]-b[i];return 0;};
const disposeTile=t=>{for(const [name,free] of [['polyMeshDetail',freePolyMeshDetail],['polyMesh',freePolyMesh],['contourSet',freeContourSet],['compactHeightfield',freeCompactHeightfield],['heightfield',freeHeightfield]])if(t?.[name]){free(t[name]);t[name]=undefined;}};
export function canonicalTriangles(positions,indices,selected){
 const rows=[];
 for(const n of selected){
  const v=[0,1,2].map(k=>positions.slice(indices[n+k]*3,indices[n+k]*3+3));
  let first=0;if(compare(v[1],v[first])<0)first=1;if(compare(v[2],v[first])<0)first=2;
  rows.push([...v[first],...v[(first+1)%3],...v[(first+2)%3]]);
 }
 rows.sort(compare);const verts=[],tris=[],ids=new Map();
 for(const row of rows)for(let at=0;at<9;at+=3){
  const xyz=row.slice(at,at+3),key=xyz.join(',');let id=ids.get(key);
  if(id===undefined){id=verts.length/3;ids.set(key,id);verts.push(...xyz);}tris.push(id);
 }
 return {positions:verts,indices:tris};
}
export function generateBoundedTiled(positions,indices,config={}){
 const audit={method:'canonical-tile-local-Y-common-ch-lattice',maxSpanVoxels:0,maxGeometrySpan:0,maxOverlappingChunks:0,builtTiles:0,emptyGeometryTiles:0,emptyWalkableTiles:0,tiles:[]};
 let nav,params,rc,gridSize,context,retained=false;
 try{
  if(!Raw.Module||positions.length%3||indices.length%3)throw Error('world geometry initialization');
  const points=Array.from(Float32Array.from(positions));
  if(!points.every(Number.isFinite)||!indices.every(i=>Number.isInteger(i)&&i>=0&&i<points.length/3))throw Error('world geometry shape');
  const cfg={...tiledNavMeshGeneratorConfigDefaults,...config};
  if(cfg.offMeshConnections?.length||!cfg.bounds)throw Error('world walking bounds required');
  const setup=buildTiledNavMeshRcConfig({recastConfig:cfg,navMeshBounds:cfg.bounds});
  rc=setup.config;gridSize=setup.gridSize;
  const {tileWidth:width,tileHeight:height,tcs,orig,maxTiles,maxPolysPerTile}=setup;
  if(!(width>0&&height>0)||width*height>100)throw Error('world batch tile bound');
  const [bbMin]=cfg.bounds,border=rc.borderSize*rc.cs,ch=rc.ch;
  let slack=0;for(const [axis,count] of [[0,width],[2,height]])for(let i=0;i<=count;i++)for(const sign of [-1,1]){const v=bbMin[axis]+i*tcs+sign*border;slack=Math.max(slack,Math.abs(Math.fround(v)-v));}slack+=1e-9;
  const selected=Array.from({length:width*height},()=>[]),padding=border+slack;
  for(let n=0;n<indices.length;n+=3){
   const a=indices[n]*3,b=indices[n+1]*3,c=indices[n+2]*3;
   const x0=Math.min(points[a],points[b],points[c]),x1=Math.max(points[a],points[b],points[c]);
   const z0=Math.min(points[a+2],points[b+2],points[c+2]),z1=Math.max(points[a+2],points[b+2],points[c+2]);
   const tx0=Math.max(0,Math.ceil((x0-bbMin[0]-padding)/tcs)-1),tx1=Math.min(width-1,Math.floor((x1-bbMin[0]+padding)/tcs));
   const tz0=Math.max(0,Math.ceil((z0-bbMin[2]-padding)/tcs)-1),tz1=Math.min(height-1,Math.floor((z1-bbMin[2]+padding)/tcs));
   for(let z=tz0;z<=tz1;z++)for(let x=tx0;x<=tx1;x++){const list=selected[z*width+x];if(list.length>=262144)throw Error('world per-tile triangle bound');list.push(n);}
  }
  audit.grid=[width,height];audit.ch=ch;audit.globalYOrigin=bbMin[1];audit.heightQuerySlack=slack;
  nav=new NavMesh();params=NavMeshParams.create({orig,tileWidth:tcs,tileHeight:tcs,maxTiles,maxPolys:maxPolysPerTile});if(!nav.initTiled(params))throw Error('world nav init');context=new RecastBuildContext();
  for(let z=0;z<height;z++)for(let x=0;x<width;x++){
   const list=selected[z*width+x],row={x,z,inputTriangles:list.length};
   if(!list.length){audit.emptyGeometryTiles++;audit.tiles.push({...row,emptyGeometry:true});continue;}
   const local=canonicalTriangles(points,indices,list);let lo=Infinity,hi=-Infinity;
   for(let i=1;i<local.positions.length;i+=3){lo=Math.min(lo,local.positions[i]);hi=Math.max(hi,local.positions[i]);}
   const v0=Math.floor((lo-bbMin[1])/ch)-1,v1=Math.ceil((hi-bbMin[1])/ch)+1,span=v1-v0;
   if(!Number.isSafeInteger(span)||span>8190)throw Error('world tile height span');
   const minY=bbMin[1]+v0*ch,maxY=bbMin[1]+v1*ch;
   Object.assign(row,{geometryMinY:lo,geometryMaxY:hi,minY,maxY,spanVoxels:span});
   let vertices,triangles,chunks,ids;
   try{
    vertices=new VerticesArray();vertices.copy(local.positions);triangles=new TrianglesArray();triangles.copy(local.indices);chunks=new RecastChunkyTriMesh();
    if(!chunks.init(vertices,triangles,local.indices.length/3,cfg.chunkyTriMeshTrisPerChunk))throw Error('world tile chunky build');
    ids=new ChunkIdsArray();ids.resize(513);
    const tile={x,y:z,bmin:[bbMin[0]+x*tcs,minY,bbMin[2]+z*tcs],bmax:[bbMin[0]+(x+1)*tcs,maxY,bbMin[2]+(z+1)*tcs]};
    const overlap=chunks.getChunksOverlappingRect([tile.bmin[0]-border,tile.bmin[2]-border],[tile.bmax[0]+border,tile.bmax[2]+border],ids,513);
    if(overlap>512)throw Error('world chunky overlap bound');row.overlappingChunks=overlap;
    audit.maxOverlappingChunks=Math.max(audit.maxOverlappingChunks,overlap);audit.maxSpanVoxels=Math.max(audit.maxSpanVoxels,span);audit.maxGeometrySpan=Math.max(audit.maxGeometrySpan,hi-lo);
    const result=generateTileNavMeshData(vertices,triangles,rc,chunks,tile,{buildBvTree:cfg.buildBvTree},true,context);
    try{
     if(!result.success){if(result.error==='Failed to create Detour navmesh data'&&result.intermediates.polyMesh?.npolys()===0){row.emptyWalkable=true;audit.emptyWalkableTiles++;}else throw Error('world tile bake:'+result.error);}
     else if(result.data){const added=nav.addTile(result.data,Detour.DT_TILE_FREE_DATA,0);if(statusFailed(added.status)){result.data.destroy();throw Error(statusToReadableString(added.status));}row.built=true;audit.builtTiles++;}
     else{row.emptyWalkable=true;audit.emptyWalkableTiles++;}
    }finally{disposeTile(result.intermediates);}
   }finally{if(chunks)Raw.destroy(chunks.raw);if(ids)ids.destroy();if(triangles)triangles.destroy();if(vertices)vertices.destroy();}
   audit.tiles.push(row);context.logs.length=0;
  }
  retained=true;return {success:true,navMesh:nav,heightAudit:audit};
 }catch(error){return {success:false,error:String(error.message||error),heightAudit:audit};}
 finally{if(nav&&!retained)nav.destroy();if(params)Raw.destroy(params.raw);if(rc)Raw.destroy(rc);if(gridSize)Raw.destroy(gridSize);if(context)Raw.destroy(context.raw);}
}
