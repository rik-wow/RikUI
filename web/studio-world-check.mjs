// Exact reviewed user-supplied screenshot; no renderer or client-build claim.
import {readFile} from "node:fs/promises";
import {createHash} from "node:crypto";
export function validateWorld(record,raw){
 if(record.width!==3840||record.height!==2160||record.source?.kind!=="user-provided-game-screenshot"||!record.source.filename||!record.reviewedAt)throw Error("Background screenshot provenance is incomplete");
 if(!/^[a-z0-9-]+\.jpg$/.test(record.file))throw Error("Unsafe background filename");
 if(!/^[0-9a-f]{64}$/.test(record.sha256)||record.reviewedSHA256!==record.sha256)throw Error("Background needs exact hash review");
 if(createHash("sha256").update(raw).digest("hex")!==record.sha256)throw Error("Reviewed background bytes changed");
 return {record,raw};
}
export async function reviewedWorld(){
 const root=new URL("../tools/site-renders/worlds/",import.meta.url),record=JSON.parse(await readFile(new URL("studio-background.json",root),"utf8"));
 if(!/^[a-z0-9-]+\.jpg$/.test(record.file))throw Error("Unsafe background filename");
 return validateWorld(record,await readFile(new URL(record.file,root)));
}
