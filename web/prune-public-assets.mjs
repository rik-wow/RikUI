// Generated public assets only. Reviewed baselines in web/ui-renders are never touched.
import {readdir,unlink,realpath} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import path from "node:path";
export async function prunePublicAssets(directory,urls,prefix){
 if(!["docs","studio"].includes(prefix))throw Error("Unknown generated asset directory");
 const root=path.resolve(fileURLToPath(directory));
 if(await realpath(root)!==root)throw Error("Refusing redirected generated asset directory");
 if(!root.endsWith(path.join("web","public","assets",prefix)))throw Error("Refusing asset cleanup outside the generated directory");
 const keep=new Set(urls.map(url=>{const base="/assets/"+prefix+"/";if(!url.startsWith(base)||url.slice(base.length).includes("/")||url.includes(".."))throw Error("Invalid generated asset URL");return url.slice(base.length);}));
 let removed=0;
 for(const name of await readdir(root)){if(keep.has(name))continue;
  if(!/^[a-zA-Z0-9_-]+-[a-f0-9]{12}\.(webp|json|js)$/.test(name))throw Error("Unrecognized generated asset: "+name);
  await unlink(path.join(root,name));removed++;
 }
 if(removed)console.log("Removed "+removed+" superseded public "+prefix+" assets; reviewed baselines retained.");
}
