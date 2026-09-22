
// Cross-tile Detour links can exceed the movement step profile. Reject both
// directions of that shared opening; never increase the agent's climb to fit it.
export function pruneStepPortals(polygons,maxStep) {
  const byID=new Map(polygons.map(p=>[p.id,p])),denied=new Set(),audit=[];
  const key=(a,b)=>Math.min(a,b)+':'+Math.max(a,b);
  const height=(points,p)=>{
    let best=null,error=Infinity;
    for(let i=0;i<points.length;i++){
      const a=points[i],b=points[(i+1)%points.length],dx=b[0]-a[0],dz=b[2]-a[2],n=dx*dx+dz*dz;
      if(n<=1e-12)continue;
      const t=((p[0]-a[0])*dx+(p[2]-a[2])*dz)/n;
      if(t<-.00001||t>1.00001)continue;
      const gap=Math.hypot(a[0]+t*dx-p[0],a[2]+t*dz-p[2]);
      if(gap<=.01&&gap<error){best=a[1]+t*(b[1]-a[1]);error=gap;}
    }
    return best;
  };
  for(const p of polygons)for(const edge of p.portals){
    const to=byID.get(edge.to);if(!to)throw Error('dangling-portal');
    const points=[edge.left,edge.right,edge.left.map((v,i)=>(v+edge.right[i])/2)];
    const samples=points.map(point=>[height(p.points,point),height(to.points,point)]);
    if(samples.some(pair=>pair.some(v=>v===null)))throw Error('portal-height-unresolved');
    const difference=Math.max(...samples.map(([a,b])=>Math.abs(a-b)));
    if(difference>maxStep+.002){
      denied.add(key(p.id,edge.to));
      audit.push({from:p.id,to:edge.to,reason:'portal-exceeds-modeled-step',maxDifference:difference,samples});
    }
  }
  let removed=0;
  for(const p of polygons)p.portals=p.portals.filter(edge=>{
    if(denied.has(key(p.id,edge.to))){removed++;return false;}return true;
  });
  return {removedDirectedLinks:removed,rejected:audit};
}

// Reject generated faces without a usable horizontal interior. Height alone cannot make a walking polygon.
export function hasHorizontalArea(points) {
  if (!Array.isArray(points) || points.length < 3) return false;
  const a=points[0];let area=0;
  for(let i=1;i<points.length-1;i++) {
    const b=points[i],c=points[i+1];
    area+=(b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0]);
  }
  return Number.isFinite(area) && Math.abs(area)>0.00001;
}

// Spatial buckets preserve the conservative closed AABB test exactly, including boundaries.

// Recover Recast's integer XZ voxel coordinates after its float32 tile storage.
// Height remains untouched. Reject inputs that do not fit the configured lattice.
export function voxelVertex(point,origin,cell) {
  return point.map((value,axis)=>{
    if(axis===1)return value;
    const exact=origin[axis]+Math.round((value-origin[axis])/cell)*cell;
    if(Math.abs(exact-value)>.0002)throw Error('off-Recast-voxel-lattice');
    return exact;
  });
}

export function exclusionLookup(boxes,cell=64) {
  const buckets=new Map();let entries=0;
  for(const box of boxes) {
    if(box.bounds?.length!==2||!box.bounds.every(p=>p.length===3&&p.every(Number.isFinite))
      ||!Number.isFinite(box.padding)||box.padding<0||box.padding>10
      ||box.bounds[0].some((v,i)=>v>box.bounds[1][i]))throw Error('exclusion-shape');
    const rect=[box.bounds[0][0]-box.padding,box.bounds[0][2]-box.padding,
      box.bounds[1][0]+box.padding,box.bounds[1][2]+box.padding];
    for(let x=Math.floor(rect[0]/cell);x<=Math.floor(rect[2]/cell);x++)
      for(let z=Math.floor(rect[1]/cell);z<=Math.floor(rect[3]/cell);z++) {
        if(++entries>262144)throw Error('exclusion-index-budget');
        const key=x+':'+z;let list=buckets.get(key);if(!list)buckets.set(key,list=[]);list.push(rect);
      }
  }
  return points=>{
    const xs=points.map(p=>p[0]),zs=points.map(p=>p[2]);
    const a=Math.min(...xs),b=Math.min(...zs),c=Math.max(...xs),d=Math.max(...zs);
    for(let x=Math.floor(a/cell);x<=Math.floor(c/cell);x++)
      for(let z=Math.floor(b/cell);z<=Math.floor(d/cell);z++)
        for(const r of buckets.get(x+':'+z)??[])if(c>=r[0]&&a<=r[2]&&d>=r[1]&&b<=r[3])return true;
    return false;
  };
}

export function removeBlockedPortals(portals,blocked) { return portals.filter(p=>!blocked.has(p.to)); }
// Detour stores seam endpoints as 8-bit edge fractions. Intersect that interval
// with the actual target edge; never enlarge it or connect noncollinear edges.
export function clipPortalToTarget(portal,points) {
  const a=portal.left,b=portal.right,dx=b[0]-a[0],dz=b[2]-a[2],length2=dx*dx+dz*dz;
  if(length2<=1e-12)return null;
  let best=null;
  const fraction=p=>((p[0]-a[0])*dx+(p[2]-a[2])*dz)/length2;
  const error=p=>Math.abs(dx*(p[2]-a[2])-dz*(p[0]-a[0]))/Math.sqrt(length2);
  for(let i=0;i<points.length;i++){
    const p=points[i],q=points[(i+1)%points.length];
    if(error(p)>.0002||error(q)>.0002)continue;
    const low=Math.max(0,Math.min(fraction(p),fraction(q)));
    const high=Math.min(1,Math.max(fraction(p),fraction(q)));
    if(high-low>1e-8&&(!best||high-low>best[1]-best[0]))best=[low,high];
  }
  if(!best)return null;
  const at=t=>a.map((v,i)=>Math.round((v+(b[i]-v)*t)*10000)/10000);
  return {...portal,left:at(best[0]),right:at(best[1])};
}

// Remove only complete triangle projections inside full-height source omissions.
// Finite-height roofs/colliders and partially intersecting triangles stay in raster input.
// The existing post-bake exclusion filter remains mandatory, with its original padding.
export function pruneFullHeightExcludedTriangles(positions,indices,exclusions,cell=64) {
  const buckets=new Map();let entries=0,eligible=0;
  const reasons=new Set(['unsupported-ADT-geometry','unsourced-physical-tile']);
  for(const box of exclusions) {
    if(!reasons.has(box.reason))continue;
    if(box.bounds?.length!==2||!box.bounds.every(p=>p.length===3&&p.every(Number.isFinite))
      ||box.bounds[0].some((v,i)=>v>box.bounds[1][i]))throw Error('exclusion-shape');
    if(box.bounds[0][1]>-100000||box.bounds[1][1]<100000)continue;
    eligible++;
    const a=box.bounds[0],b=box.bounds[1],rect=[a[0],a[2],b[0],b[2],box.reason];
    for(let x=Math.floor(a[0]/cell);x<=Math.floor(b[0]/cell);x++)
      for(let z=Math.floor(a[2]/cell);z<=Math.floor(b[2]/cell);z++) {
        if(++entries>262144)throw Error('exclusion-index-budget');
        const key=x+':'+z;let list=buckets.get(key);if(!list)buckets.set(key,list=[]);list.push(rect);
      }
  }
  const kept=[],removedByReason={};
  for(let at=0;at<indices.length;at+=3) {
    const offsets=[indices[at]*3,indices[at+1]*3,indices[at+2]*3];
    const first=offsets[0],list=buckets.get(Math.floor(positions[first]/cell)+':'+Math.floor(positions[first+2]/cell))??[];
    let contained;
    for(const r of list) {
      if(offsets.every(i=>positions[i]>=r[0]&&positions[i]<=r[2]&&positions[i+2]>=r[1]&&positions[i+2]<=r[3]
        &&positions[i+1]>=-100000&&positions[i+1]<=100000)){contained=r;break;}
    }
    if(contained)removedByReason[contained[4]]=(removedByReason[contained[4]]??0)+1;
    else kept.push(indices[at],indices[at+1],indices[at+2]);
  }
  return {indices:kept,audit:{method:'whole-triangle-in-unpadded-full-height-source-exclusion',eligibleBoxes:eligible,
    inputTriangles:indices.length/3,retainedTriangles:kept.length/3,removedTriangles:(indices.length-kept.length)/3,removedByReason}};
}
