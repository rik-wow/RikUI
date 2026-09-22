// Public Recast 0.43.1 tile APIs; preserve the common vertical voxel lattice.
// Global region height can exceed rcSpan's 13-bit storage. Never silently clamp it.
import {
 Raw, VerticesArray, TrianglesArray, ChunkIdsArray, RecastChunkyTriMesh,
 RecastBuildContext, NavMesh, NavMeshParams, Detour, statusFailed,
 statusToReadableString, freeHeightfield, freeCompactHeightfield,
 freeContourSet, freePolyMesh, freePolyMeshDetail
} from '@recast-navigation/core';
import {
 buildTiledNavMeshRcConfig, generateTileNavMeshData,
 tiledNavMeshGeneratorConfigDefaults, getBoundingBox
} from '@recast-navigation/generators';
export function generateBoundedTiled(positions, indices, config = {}) {
 const audit = {method:'tile-local-Y-common-ch-lattice',maxSpanVoxels:0,
  maxGeometrySpan:0,maxOverlappingChunks:0,builtTiles:0,
  emptyGeometryTiles:0,emptyWalkableTiles:0,tiles:[]};
 let vertices,triangles,chunks,ids,context,navMesh,rc,gridSize,params,retained=false;
 const disposeTile=t=>{
  for(const [name,free] of [['polyMeshDetail',freePolyMeshDetail],['polyMesh',freePolyMesh],
   ['contourSet',freeContourSet],['compactHeightfield',freeCompactHeightfield],['heightfield',freeHeightfield]])
   if(t?.[name]){free(t[name]);t[name]=undefined;}
 };
 try {
  if(!Raw.Module)throw Error('recast-not-initialized');
  if(!positions.length||positions.length%3||indices.length%3)throw Error('invalid-geometry-arrays');
  const points=Float32Array.from(positions);
  for(const v of points)if(!Number.isFinite(v))throw Error('nonfinite-geometry');
  for(const i of indices)if(!Number.isInteger(i)||i<0||i>=points.length/3)throw Error('invalid-triangle-index');
  const cfg={...tiledNavMeshGeneratorConfigDefaults,...config};
  if(cfg.offMeshConnections?.length)throw Error('bounded-tiler-walking-only');
  if(!(cfg.cs>0)||!(cfg.ch>0))throw Error('invalid-cell-size');
  const bounds=cfg.bounds||(()=>{const b=getBoundingBox(points,indices);return[b.bbMin,b.bbMax];})();
  if(bounds.length!==2||!bounds.every(v=>v.length===3&&v.every(Number.isFinite))||
   bounds[0].some((v,a)=>v>bounds[1][a]))throw Error('invalid-bounds');
  const setup=buildTiledNavMeshRcConfig({recastConfig:cfg,navMeshBounds:bounds});
  rc=setup.config;gridSize=setup.gridSize;
  const {tileWidth:width,tileHeight:height,tcs,orig,maxTiles,maxPolysPerTile}=setup;
  if(!(width>0&&height>0)||width*height>4096)throw Error('offline-tile-budget');
  const [bbMin]=bounds,border=rc.borderSize*rc.cs,ch=rc.ch;
  let slack=0;
  for(const [axis,count] of [[0,width],[2,height]])
   for(let i=0;i<=count;++i)for(const sign of [-1,1]){
    const v=bbMin[axis]+i*tcs+sign*border;slack=Math.max(slack,Math.abs(Math.fround(v)-v));
   }
  slack+=1e-9;
  const lo=new Float64Array(width*height).fill(Infinity),hi=new Float64Array(width*height).fill(-Infinity);
  const padding=border+slack;
  for(let n=0;n<indices.length;n+=3){
   const a=indices[n]*3,b=indices[n+1]*3,c=indices[n+2]*3;
   const x0=Math.min(points[a],points[b],points[c]),x1=Math.max(points[a],points[b],points[c]);
   const y0=Math.min(points[a+1],points[b+1],points[c+1]),y1=Math.max(points[a+1],points[b+1],points[c+1]);
   const z0=Math.min(points[a+2],points[b+2],points[c+2]),z1=Math.max(points[a+2],points[b+2],points[c+2]);
   const tx0=Math.max(0,Math.ceil((x0-bbMin[0]-padding)/tcs)-1);
   const tx1=Math.min(width-1,Math.floor((x1-bbMin[0]+padding)/tcs));
   const tz0=Math.max(0,Math.ceil((z0-bbMin[2]-padding)/tcs)-1);
   const tz1=Math.min(height-1,Math.floor((z1-bbMin[2]+padding)/tcs));
   for(let z=tz0;z<=tz1;++z)for(let x=tx0;x<=tx1;++x){
    const k=z*width+x;lo[k]=Math.min(lo[k],y0);hi[k]=Math.max(hi[k],y1);
   }
  }
  audit.grid=[width,height];audit.ch=ch;audit.globalYOrigin=bbMin[1];audit.heightQuerySlack=slack;
  vertices=new VerticesArray();vertices.copy(points);
  triangles=new TrianglesArray();triangles.copy(indices);
  chunks=new RecastChunkyTriMesh();
  if(!chunks.init(vertices,triangles,indices.length/3,cfg.chunkyTriMeshTrisPerChunk))throw Error('chunky-triangle-build-failed');
  ids=new ChunkIdsArray();ids.resize(513);context=new RecastBuildContext();navMesh=new NavMesh();
  params=NavMeshParams.create({orig,tileWidth:tcs,tileHeight:tcs,maxTiles,maxPolys:maxPolysPerTile});
  if(!navMesh.initTiled(params))throw Error('tiled-navmesh-init-failed');
  for(let z=0;z<height;++z)for(let x=0;x<width;++x){
   const k=z*width+x,row={x,z,geometryMinY:lo[k],geometryMaxY:hi[k]};
   if(!Number.isFinite(lo[k])){audit.emptyGeometryTiles++;audit.tiles.push({x,z,emptyGeometry:true});continue;}
   const v0=Math.floor((lo[k]-bbMin[1])/ch)-1,v1=Math.ceil((hi[k]-bbMin[1])/ch)+1,spanVoxels=v1-v0;
   if(!Number.isSafeInteger(spanVoxels)||spanVoxels>8190)throw Error('tile-heightfield-span-overflow:'+x+','+z);
   const minY=bbMin[1]+v0*ch,maxY=bbMin[1]+v1*ch;
   const tile={x,y:z,bmin:[bbMin[0]+x*tcs,minY,bbMin[2]+z*tcs],
    bmax:[bbMin[0]+(x+1)*tcs,maxY,bbMin[2]+(z+1)*tcs]};
   const overlapping=chunks.getChunksOverlappingRect(
    [tile.bmin[0]-border,tile.bmin[2]-border],[tile.bmax[0]+border,tile.bmax[2]+border],ids,513);
   if(overlapping>512)throw Error('tile-chunk-overlap-budget:'+x+','+z);
   if(overlapping===0){row.emptyGeometry=true;row.overlappingChunks=0;audit.emptyGeometryTiles++;audit.tiles.push(row);continue;}
   Object.assign(row,{minY,maxY,spanVoxels,overlappingChunks:overlapping});
   audit.maxSpanVoxels=Math.max(audit.maxSpanVoxels,spanVoxels);
   audit.maxGeometrySpan=Math.max(audit.maxGeometrySpan,hi[k]-lo[k]);
   audit.maxOverlappingChunks=Math.max(audit.maxOverlappingChunks,overlapping);
   const result=generateTileNavMeshData(vertices,triangles,rc,chunks,tile,{buildBvTree:cfg.buildBvTree},true,context);
   try {
    if(!result.success){
     if(result.error==='Failed to create Detour navmesh data'&&result.intermediates.polyMesh?.npolys()===0){
      row.emptyWalkable=true;audit.emptyWalkableTiles++;
     }else throw Error('tile-build-failed:'+x+','+z+':'+result.error);
    }else if(result.data){
     const added=navMesh.addTile(result.data,Detour.DT_TILE_FREE_DATA,0);
     if(statusFailed(added.status)){result.data.destroy();throw Error('tile-add-failed:'+x+','+z+':'+statusToReadableString(added.status));}
     row.built=true;audit.builtTiles++;
    }else{row.emptyWalkable=true;audit.emptyWalkableTiles++;}
   }finally{disposeTile(result.intermediates);}
   audit.tiles.push(row);context.logs.length=0;
  }
  retained=true;return{success:true,navMesh,heightAudit:audit};
 }catch(error){return{success:false,navMesh:undefined,error:String(error.message||error),heightAudit:audit};}
 finally{
  if(navMesh&&!retained)navMesh.destroy();
  if(chunks)Raw.destroy(chunks.raw);if(ids)ids.destroy();if(triangles)triangles.destroy();if(vertices)vertices.destroy();
  if(params)Raw.destroy(params.raw);if(rc)Raw.destroy(rc);if(gridSize)Raw.destroy(gridSize);if(context)Raw.destroy(context.raw);
 }
}
