// Figures for reviewed Lua captures: one image, or a sequence of frames with a control.
export const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c]));
const WIDE_RENDER=600;
export function renderFigure(page,capture,caption){
 const title=caption||capture.title;
 return '<figure data-kind="'+escapeHTML(page?.kind??"page")+'" data-render="'+escapeHTML(capture.id)+'" data-wide="'+(capture.width>=WIDE_RENDER)+'" id="visual-'+escapeHTML(capture.id)+'"><a class="enlarge-example" href="'+capture.url+'" aria-label="Open '+escapeHTML(title)+' at full size"><img class="ui-example" src="'+capture.url+'" width="'+capture.width+'" height="'+capture.height+'" loading="lazy" alt="'+escapeHTML(title)+'"></a><figcaption><strong>'+escapeHTML(title)+'</strong><span>Open full size</span></figcaption></figure>';
}
// A sequence: one frame per value of a setting. Every frame is in the page; the control (a range, a
// switch or a select over the frame index) shows one at a time. Without scripting only the default
// frame shows and the control stays hidden.
export function sequenceFigure(page,capture,caption){
 const title=caption||capture.title, spec=capture.sequence, frames=capture.frames;
 const defaultIndex=Math.max(0,frames.findIndex(frame=>frame.value===spec.default));
 const labelOf=(frame,index)=>spec.labels?.[index]??String(frame.value);
 const images=frames.map((frame,index)=>'<a class="enlarge-example" href="'+frame.url+'" data-frame="'+index+'"'+(index===defaultIndex?"":" hidden")+' aria-label="Open '+escapeHTML(title+", "+labelOf(frame,index))+' at full size"><img class="ui-example" src="'+frame.url+'" width="'+frame.width+'" height="'+frame.height+'" loading="'+(index===defaultIndex?"lazy":"eager")+'" alt="'+escapeHTML(title+" at "+labelOf(frame,index))+'"></a>').join("");
 let control;
 if(spec.control==="toggle")control='<input type="checkbox" role="switch"'+(defaultIndex===1?" checked":"")+' aria-label="'+escapeHTML(spec.label)+'">';
 else if(spec.control==="dropdown")control='<select aria-label="'+escapeHTML(spec.label)+'">'+frames.map((frame,index)=>'<option value="'+index+'"'+(index===defaultIndex?" selected":"")+'>'+escapeHTML(labelOf(frame,index))+'</option>').join("")+'</select>';
 else control='<input type="range" min="0" max="'+(frames.length-1)+'" step="1" value="'+defaultIndex+'" aria-label="'+escapeHTML(spec.label)+'" aria-valuetext="'+escapeHTML(labelOf(frames[defaultIndex],defaultIndex))+'">';
 const values=frames.map((frame,index)=>labelOf(frame,index));
 return '<figure data-kind="'+escapeHTML(page?.kind??"page")+'" data-render="'+escapeHTML(capture.id)+'" data-sequence="'+escapeHTML(spec.control||"slider")+'" data-wide="'+(capture.width>=WIDE_RENDER)+'" id="visual-'+escapeHTML(capture.id)+'"><div class="preview-frames">'+images+'</div><figcaption><strong>'+escapeHTML(title)+'</strong><label class="preview-control" hidden data-values="'+escapeHTML(JSON.stringify(values))+'"><span>'+escapeHTML(spec.label)+'</span>'+control+'<output>'+escapeHTML(values[defaultIndex])+'</output></label><span>Open full size</span></figcaption></figure>';
}
