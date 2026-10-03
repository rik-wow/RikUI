// Executes only the generated public addon source; imported packs remain data.
import {createEngine} from "./pack-engine.mjs";
self.onmessage=event=>{
 const {sources,pack,options}=event.data;
 try {
  const engine=createEngine(sources);
  self.postMessage({result:engine.call("Optimize",pack,options)});
 } catch(error){self.postMessage({error:error.message});}
};
