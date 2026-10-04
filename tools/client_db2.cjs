// Decode current local DB2 inputs using the separately acquired MIT wow.export reader.
// No online table fallback or client-build defaults.
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const crypto = require('node:crypto');
const [readerRoot, input, build, definitionsRevision, ...tables] = process.argv.slice(2);
if (!readerRoot || !input || !/^1\.\d+\.\d+\.\d+$/.test(build || '') ||
    !/^[a-f0-9]{40}$/.test(definitionsRevision || '') || !tables.length ||
    tables.some(t => !/^[A-Za-z][A-Za-z0-9]+$/.test(t))) throw Error('Explicit current DB2 inputs required');
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
const quote = value => '"' + String(value ?? '').replaceAll('"', '""') + '"';
(async () => {
  const receipt = {build, definitionsRevision, readerSHA256:hash(path.join(root,'db/WDCReader.js')), tables:{}};
  for (const table of tables) {
    const reader = new Reader(table + '.db2'); await reader.parse();
    const rows = [];
    for (const [id, entity] of reader.getAllRows()) {
      const row = {ID: id};
      for (const [key, value] of Object.entries(entity)) {
        if (Array.isArray(value)) value.forEach((v, index) => row[key + '_' + index] = v);
        else row[key] = value;
      }
      rows.push(row);
    }
    if (!rows.length || rows.length > 250000) throw Error('Empty or unsupported table inventory: ' + table);
    const columns = [...new Set(rows.flatMap(row => Object.keys(row)))];
    const target = path.join(input, table + '-' + build + '.csv');
    const csv = columns.map(quote).join(',') + '\n' +
      rows.map(row => columns.map(key => quote(row[key])).join(',')).join('\n') + '\n';
    fs.writeFileSync(target, csv, {flag:'wx'});
    receipt.tables[table] = {records:rows.length, db2SHA256:hash(path.join(input,table+'.db2')),
      dbdSHA256:hash(path.join(input,table+'.dbd')), csvSHA256:hash(target)};
  }
  fs.writeFileSync(path.join(input, 'db2-inputs.json'), JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify(receipt));
})().catch(error => {console.error(error); process.exitCode=1;});
