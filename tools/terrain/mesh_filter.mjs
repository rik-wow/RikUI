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
