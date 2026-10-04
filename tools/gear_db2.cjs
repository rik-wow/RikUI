// Read locally extracted current-client DB2 tables with the external MIT wow.export reader.
// No source/cache from another build is consulted. Outputs stay in the external input directory.
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const crypto = require('node:crypto');
const [readerRoot, input, build, definitionsRevision] = process.argv.slice(2);
if (!readerRoot || !input || !/^1\.\d+\.\d+\.\d+$/.test(build || '') || !/^[a-f0-9]{40}$/.test(definitionsRevision || '')) throw Error('Reader root, input directory, current build and resolved definitions revision required');
const root = path.resolve(readerRoot, 'src/js');
const original = Module._load;
const core = { view: { casc: {
  getBuildName: () => build,
  getVirtualFileByName: async name => new BufferWrapper(fs.readFileSync(path.join(input, path.basename(name)))),
  cache: { getFile: async name => new BufferWrapper(fs.readFileSync(path.join(input, name))) },
} } };
Module._load = function(request, parent, ...args) {
  const full = request.startsWith('.') ? path.resolve(path.dirname(parent.filename), request) : request;
  if (full === path.join(root, 'core')) return core;
  if (full === path.join(root, 'log')) return {write: () => {}};
  if (full === path.join(root, 'generics')) return {};
  if (full === path.join(root, 'constants')) return {CACHE:{DIR_DBD:'unused'}};
  if (full === path.join(root, 'casc/export-helper')) return {replaceExtension: name => name.replace(/\.[^.]+$/, '')};
  if (request === 'webp-wasm') return {};
  return original.call(this, request, parent, ...args);
};
const BufferWrapper = require(path.join(root, 'buffer.js'));
const Reader = require(path.join(root, 'db/WDCReader.js'));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
(async () => {
  const receipt = {build, definitionsRevision, readerSHA256:hash(path.join(root,'db/WDCReader.js')), tables:{}};
  for (const table of process.env.RIK_GEAR_TABLES ? process.env.RIK_GEAR_TABLES.split(',') : ['Item', 'ItemSparse']) {
    const reader = new Reader(table + '.db2'); await reader.parse();
    const rows = Object.fromEntries(reader.getAllRows());
    const target = path.join(input, table + '.json');
    fs.writeFileSync(target, JSON.stringify(rows, (_, value) => typeof value === 'bigint' ? value.toString() : value) + '\n');
    receipt.tables[table] = {records:Object.keys(rows).length, db2SHA256:hash(path.join(input,table+'.db2')), dbdSHA256:hash(path.join(input,table+'.dbd')), jsonSHA256:hash(target)};
  }
  fs.writeFileSync(path.join(input, 'item-inputs.json'), JSON.stringify(receipt,null,2)+'\n');
  console.log(JSON.stringify(receipt));
})().catch(error => {console.error(error); process.exitCode=1;});
