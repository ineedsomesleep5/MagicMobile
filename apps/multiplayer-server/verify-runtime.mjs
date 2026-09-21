import { readFile, lstat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join } from 'node:path';

const root=resolve(process.argv[2]??'');
if(process.argv.length!==3)throw Error('Usage: node verify-runtime.mjs portable-runtime-directory');
const text=await readFile(join(root,'provenance.json'),'utf8'),manifest=JSON.parse(text);
if(text.includes('/Users/')||text.includes('/home/')||manifest.schema!==1)throw Error('Nonportable provenance');
const cp=(await readFile(join(root,'runtime-classpath.txt'),'utf8')).trim().split(':');
if(JSON.stringify(cp)!==JSON.stringify(manifest.classpath)||cp[0]!=='cp/000-server')throw Error('Classpath order differs from receipt');
let checked=0;
for(const [name,expected] of Object.entries(manifest.files)){
  if(name.startsWith('/')||name.split('/').includes('..'))throw Error('Unsafe manifest path');
  const file=join(root,name),stat=await lstat(file);
  if(!stat.isFile()||stat.isSymbolicLink())throw Error('Non-file or linked payload');
  if(stat.size!==expected.bytes||createHash('sha256').update(await readFile(file)).digest('hex')!==expected.sha256)throw Error('Changed payload '+name);
  if(name.startsWith('cp/')&&/\/(ServerTests|FailureRegressions|ConfigurationTests|RealEngineSmoke)(\$|\.class)/.test(name))throw Error('Diagnostic class in production classpath');
  checked++;
}
for(const name of ['run.sh','start.sh','NOTICE.txt','notices/licenses/XMAGE-MIT.txt','dependency-inventory.json'])if(!manifest.files[name])throw Error('Missing portable runtime input '+name);
if(manifest.files['diagnostics/deck-provenance.json']){
  const proof=await readFile(join(root,'diagnostics/deck-provenance.json'),'utf8');
  if(proof.includes('/Users/')||proof.includes('/home/'))throw Error('Nonportable diagnostic provenance');
}
console.log(`PASS: ${checked} exact packaged files; ${cp.length} ordered relative classpath entries; production excludes test classes; notices and sanitized provenance present`);
