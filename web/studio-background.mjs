// A fixed photograph is fitted independently from all pack/layout semantics.
// Never stretches the world or compounds creator frame positions.
export function coverCrop(sourceWidth,sourceHeight,width,height){
 if(![sourceWidth,sourceHeight,width,height].every(n=>Number.isFinite(n)&&n>0))throw Error("Invalid background dimensions");
 const ratio=Math.max(width/sourceWidth,height/sourceHeight),sw=width/ratio,sh=height/ratio;
 return {sx:(sourceWidth-sw)/2,sy:(sourceHeight-sh)/2,sw,sh,width,height};
}
export async function paintBackground(ctx,background,mode,loadImage,isCurrent=()=>true){
 const {width,height}=ctx.canvas;ctx.fillStyle="#0c1117";ctx.fillRect(0,0,width,height);
 if(mode==="plain"||!background)return "plain";
 try{
  const image=await loadImage(background.url),crop=coverCrop(image.naturalWidth,image.naturalHeight,width,height);
  if(!isCurrent())return "superseded";
  ctx.drawImage(image,crop.sx,crop.sy,crop.sw,crop.sh,0,0,width,height);
  if(mode==="dim"){ctx.fillStyle="#0c11177a";ctx.fillRect(0,0,width,height);}
  return "ready";
 }catch{return "unavailable";}
}
