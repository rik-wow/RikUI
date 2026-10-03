// A reviewed screenshot, never a packaged client asset or a submitted renderer.
import {readFile} from "node:fs/promises";
import {createHash} from "node:crypto";
export function validateWorld(record,raw){
 if(record.width!==3840||record.height!==2160||!record.app?.commit||!Array.isArray(record.app.dirty)||record.app.dirty.length||record.request?.realm!==false||!record.inputs?.identity?.uiHead||!record.inputs.identity.version||!record.inputs.manifestSHA256)throw Error("World plate provenance is incomplete");
 if(!/^[a-z0-9-]+\.jpg$/.test(record.file))throw Error("Unsafe world plate filename");
 if(!/^[0-9a-f]{64}$/.test(record.sha256)||record.reviewedSHA256!==record.sha256)throw Error("World plate needs exact hash review");
 if(createHash("sha256").update(raw).digest("hex")!==record.sha256)throw Error("Reviewed world plate bytes changed");
 return {record,raw};
}
export async function reviewedWorld(){
 const root=new URL("../tools/site-renders/worlds/",import.meta.url),record=JSON.parse(await readFile(new URL("studio-elwynn-4k.json",root),"utf8"));
 if(!/^[a-z0-9-]+\.jpg$/.test(record.file))throw Error("Unsafe world plate filename");
 return validateWorld(record,await readFile(new URL(record.file,root)));
}
