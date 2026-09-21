import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {LIMITS,ensure,sha,parseJSON,validateManifest,validateGeometry,validateSites} from './stage_contract.mjs';
export const MODULE_HASHES=Object.freeze({
 '@recast-navigation/core/package.json':'e0915ae4e0b21b26d5f289fd355dac645d40d9d944a7a665278c3d2aeb3de6c1',
 '@recast-navigation/core/dist/index.mjs':'902d38b3dceb6eebdaad5f917d9f177f9ad4cd3ec936ee486f44dce91ba8bac0',
 '@recast-navigation/generators/package.json':'50120d4c821e12c08d2a5dd72a390f5c833c3ec7f514a29624c3736ca037125b',
 '@recast-navigation/generators/dist/index.mjs':'293eab40944b1bdbf1460aea569e3560d54425e5ff14a1d62c5cbcb59cc12546',
 '@recast-navigation/wasm/package.json':'db05fddcb1188010548d64ca9b49eb466ca59c3698e734bdf0c309d51a43d28c',
 '@recast-navigation/wasm/dist/recast-navigation.wasm-compat.js':'df034a241a7c2db1d37dfca51135a0a35bb5fea253b99f75804342fee9f54cbb',
 '@recast-navigation/wasm/dist/recast-navigation.wasm.js':'5951471d851966cef9e48848c469dc649088a6bd7255fd8b3ed766abcf5bd0e2',
 '@recast-navigation/wasm/dist/recast-navigation.wasm.wasm':'008696e1a67df34aa3c830417a520034a2a358c838fc631084681f7f8f1f7a38',
});
export function noLinks(input){
 const resolved=path.resolve(input);let at=resolved;
 while(true){let stat;try{stat=fs.lstatSync(at);}catch(e){if(e.code!=='ENOENT')throw e;}
  ensure(!stat?.isSymbolicLink(),'symbolic-path:'+at);const parent=path.dirname(at);if(parent===at)break;at=parent;
 }return resolved;
}
export function boundedReadDescriptor(fd,limit,label,io=fs){
 const before=io.fstatSync(fd);
 ensure(before.isFile()&&Number.isSafeInteger(before.size)&&before.size>0&&before.size<=limit,'input-file-size:'+label);
 const buffer=Buffer.allocUnsafe(before.size+1);let size=0;
 while(size<buffer.length){const count=io.readSync(fd,buffer,size,buffer.length-size,null);if(count===0)break;size+=count;}
 const after=io.fstatSync(fd);
 ensure(size===before.size&&after.size===before.size,'input-size-changed:'+label);
 return buffer.subarray(0,size);
}
export function readBound(input,limit){
 const file=noLinks(input),fd=fs.openSync(file,fs.constants.O_RDONLY|(fs.constants.O_NOFOLLOW??0));
 try{const bytes=boundedReadDescriptor(fd,limit,file);return {path:file,bytes,sha256:sha(bytes)};}
 finally{fs.closeSync(fd);}
}

export function newOutput(input){
 const output=noLinks(input);let exists=false,at=path.dirname(output);
 while(true){ensure(!fs.existsSync(path.join(at,'.git')),'output-inside-git-worktree');const parent=path.dirname(at);if(parent===at)break;at=parent;}
 try{fs.lstatSync(output);exists=true;}catch(e){if(e.code!=='ENOENT')throw e;}
 ensure(!exists,'output-already-exists');ensure(fs.statSync(path.dirname(output)).isDirectory(),'output-parent-missing');return output;
}
export function argumentsFor(args){
 const names=['manifest','manifest-sha256','geometry','modules','sites','output'],values={};
 ensure(args.length===names.length*2,'expected-six-named-arguments');
 for(let i=0;i<args.length;i+=2){const key=args[i].slice(2);
  ensure(args[i].startsWith('--')&&names.includes(key)&&!Object.hasOwn(values,key)&&typeof args[i+1]==='string'&&args[i+1].length>0,'invalid-or-duplicate-argument');values[key]=args[i+1];
 }ensure(names.every(n=>Object.hasOwn(values,n)),'missing-argument');return values;
}
export function verifyModules(root){
 root=noLinks(root);ensure(fs.statSync(root).isDirectory(),'module-root-not-directory');const hashes={};
 for(const [relative,expected] of Object.entries(MODULE_HASHES)){
  const file=readBound(path.join(root,relative),2*1024*1024);ensure(file.sha256===expected,'module-hash:'+relative);hashes[relative]=file.sha256;
  if(relative.endsWith('package.json'))ensure(parseJSON(file.bytes,8192,'package').version==='0.43.1','module-version');
 }
 const core=path.join(root,'@recast-navigation/core/dist/index.mjs'),generators=path.join(root,'@recast-navigation/generators/dist/index.mjs');
 const wasm=path.join(root,'@recast-navigation/wasm/dist/recast-navigation.wasm-compat.js');
 ensure(noLinks(createRequire(pathToFileURL(generators)).resolve('@recast-navigation/core'))===core,'unexpected-core-resolution');
 ensure(noLinks(createRequire(pathToFileURL(core)).resolve('@recast-navigation/wasm'))===wasm,'unexpected-wasm-resolution');
 return {root,core,generators,wasm,hashes};
}
export function preflight(args){
 const output=newOutput(args.output);
 ensure(/^[0-9a-f]{64}$/.test(args['manifest-sha256']),'expected-manifest-hash');
 const manifestFile=readBound(args.manifest,LIMITS.manifestBytes);
 ensure(manifestFile.sha256===args['manifest-sha256'],'manifest-hash-mismatch');
 const manifest=parseJSON(manifestFile.bytes,LIMITS.manifestBytes,'manifest'),grid=validateManifest(manifest);
 const geometryFile=readBound(args.geometry,LIMITS.geometryBytes);
 ensure(geometryFile.sha256===manifest.geometrySha256,'geometry-hash-mismatch');
 const geometry=parseJSON(geometryFile.bytes,LIMITS.geometryBytes,'geometry');validateGeometry(geometry,manifest);
 const sitesFile=readBound(args.sites,LIMITS.sitesBytes),sites=validateSites(parseJSON(sitesFile.bytes,LIMITS.sitesBytes,'sites'),manifest,grid);
 const modules=verifyModules(args.modules);
 for(const directory of [modules.root,path.dirname(manifestFile.path),path.dirname(geometryFile.path)]){
  const relative=path.relative(directory,output);ensure(relative.startsWith('..'+path.sep)||relative==='..'||path.isAbsolute(relative),'output-overlaps-input-directory');
 }
 return {output,manifest,geometry,grid,sites,modules,inputs:[manifestFile,geometryFile,sitesFile].map(({path,bytes,sha256})=>({path,bytes:bytes.length,sha256}))};
}
