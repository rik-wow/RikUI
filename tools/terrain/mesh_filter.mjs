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
