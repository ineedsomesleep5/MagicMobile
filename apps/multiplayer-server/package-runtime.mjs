import { readFile, writeFile, mkdir, readdir, lstat, copyFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve, relative, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const server=dirname(fileURLToPath(import.meta.url)), repo=resolve(server,'../..');
const args=process.argv.slice(2);let name='portable-runtime',deckDirectory;
while(args.length){const flag=args.shift(),value=args.shift();if(flag==='--name'&&value&&/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(value))name=value;else if(flag==='--decks'&&value)deckDirectory=resolve(value);else throw Error('Usage: node package-runtime.mjs [--name unique-output-name] [--decks resolved-included-decks-directory]');}
const output=join(server,'build',name);
const hash=data=>createHash('sha256').update(data).digest('hex');
const sources={},files={},classpath=[];
const sourceCommit=execFileSync('git',['rev-parse','HEAD'],{cwd:repo,encoding:'utf8'}).trim();
const changed=execFileSync('git',['status','--porcelain','--','apps/multiplayer-server','packages/ondevice-engine'],{cwd:repo,encoding:'utf8'}).trim().split('\n').filter(Boolean);
const upstream=JSON.parse(await readFile(join(repo,'packages/ondevice-engine/upstream.lock.json'),'utf8')).commit;
const entries=(await readFile(join(repo,'packages/ondevice-engine/build/runtime-classpath.txt'),'utf8')).trim().split(':');
// Recompile only the small HTTP adapter, never XMage/native engine dependencies.
execFileSync('bash',[join(server,'build.sh')],{cwd:repo,stdio:'inherit'});
await mkdir(join(server,'build'),{recursive:true});await mkdir(output); // Refuses overwrite.
async function copied(from,to){
  const stat=await lstat(from);if(stat.isSymbolicLink())throw Error('Runtime symlinks are not accepted');
  if(stat.isDirectory()){
    await mkdir(to,{recursive:true});
    for(const entry of (await readdir(from)).sort()){
      if(entry==='.DS_Store')continue;
      await copied(join(from,entry),join(to,entry));
    }
  }else if(stat.isFile()){
    const path=relative(output,to).replaceAll('\\','/');
    if(/(^|\/)(\.env|[^/]*\.(p8|pem|key|keystore|jks))$/i.test(path))throw Error('Unexpected sensitive runtime file');
    await mkdir(dirname(to),{recursive:true});await copyFile(from,to);
    files[path]={sha256:hash(await readFile(to)),bytes:stat.size};
  }else throw Error('Unsupported runtime input type');
}
// test.sh compiles fixtures into build/classes. Select production server classes
// explicitly so no synthetic EnginePort implementation enters this image.
const names=(await readdir(join(server,'src/main/java/io/magicmobile/server'))).filter(n=>n.endsWith('.java')).map(n=>n.slice(0,-5));
const compiled=join(server,'build/classes/io/magicmobile/server');
for(const name of names){
  const source='apps/multiplayer-server/src/main/java/io/magicmobile/server/'+name+'.java';
  sources[source]=hash(await readFile(join(repo,source)));
  if(!(await readdir(compiled)).includes(name+'.class'))throw Error('Missing compiled server class: '+name);
}
for(const file of await readdir(compiled))if(file.endsWith('.class')&&names.some(name=>file===name+'.class'||file.startsWith(name+'$'))){
  await copied(join(compiled,file),join(output,'cp/000-server/io/magicmobile/server',file));
}
classpath.push('cp/000-server');
for(let i=0;i<entries.length;i++){
  const stat=await lstat(entries[i]);const dest=`cp/${String(i+1).padStart(3,'0')}${stat.isDirectory()?'-classes':'.jar'}`;
  if(!stat.isDirectory()&&!entries[i].endsWith('.jar'))throw Error('Unexpected non-JAR classpath file');
  await copied(entries[i],join(output,dest));classpath.push(dest);
}
await copied(join(server,'run.sh'),join(output,'run.sh'));
await copied(join(server,'start.sh'),join(output,'start.sh'));
await copied(join(repo,'packages/ondevice-engine/THIRD_PARTY_NOTICES.md'),join(output,'notices/THIRD_PARTY_NOTICES.md'));
await copied(join(repo,'packages/ondevice-engine/licenses/XMAGE-MIT.txt'),join(output,'notices/licenses/XMAGE-MIT.txt'));
const dependencyInventory=entries.map((entry,i)=>({classpath:classpath[i+1],name:entry.endsWith('.jar')?entry.split('/').at(-1):'compiled-classes',sha256:entry.endsWith('.jar')?files[classpath[i+1]].sha256:null}));
async function generated(path,value){const bytes=Buffer.from(value);await writeFile(join(output,path),bytes);files[path]={sha256:hash(bytes),bytes:bytes.length};}
await generated('dependency-inventory.json',JSON.stringify(dependencyInventory,null,2)+'\n');
await generated('NOTICE.txt','XMage upstream source: https://github.com/magefree/mage/tree/'+upstream+'\nXMage MIT terms: notices/licenses/XMAGE-MIT.txt\nDependency JARs are preserved byte-for-byte, including embedded META-INF licenses, notices and Maven metadata. See dependency-inventory.json for exact redistributed versions and SHA-256 values. See notices/THIRD_PARTY_NOTICES.md for the project notice. This artifact contains no card artwork.\n');
if(deckDirectory){
  const deckFiles=['chaos-incarnate','draconic-destruction','token-triumph','first-flight','grave-danger'].map(n=>n+'.json');
  const deckProof=JSON.parse(await readFile(join(deckDirectory,'provenance.json'),'utf8'));
  const diagnosticBuild=join(server,'build/diagnostic-classes');await mkdir(diagnosticBuild,{recursive:true});
  const javac=process.env.JAVA_HOME?join(process.env.JAVA_HOME,'bin/javac'):'javac';
  execFileSync(javac,['--release','17','-cp',join(server,'build/classes'),'-d',diagnosticBuild,join(server,'src/test/java/io/magicmobile/server/RealEngineSmoke.java')],{stdio:'inherit'});
  await copied(diagnosticBuild,join(output,'diagnostics/classes'));
  for(let i=0;i<deckFiles.length;i++){
    const data=JSON.parse(await readFile(join(deckDirectory,deckFiles[i]),'utf8'));
    if(!Array.isArray(data.main)||!Array.isArray(data.commanders))throw Error('Diagnostic deck is not resolved engine input');
    if(deckProof.decks.find(d=>d.id===deckFiles[i].slice(0,-5))?.sha256!==hash(await readFile(join(deckDirectory,deckFiles[i]))))throw Error('Resolved included-deck provenance mismatch');
    await copied(join(deckDirectory,deckFiles[i]),join(output,`diagnostics/decks/${i}.json`));
  }
  await generated('diagnostics/deck-provenance.json',JSON.stringify({preconSource:'apps/ios/MagicMobile/PreconCatalog.swift',preconSourceSHA256:deckProof.preconSourceSHA256,catalogueSHA256:deckProof.catalogueSHA256,resolverSHA256:deckProof.resolverSHA256,decks:deckFiles.map((file,i)=>({id:file.slice(0,-5),path:`diagnostics/decks/${i}.json`,sha256:files[`diagnostics/decks/${i}.json`].sha256}))},null,2)+'\n');
}
const cpText=classpath.join(':')+'\n';await writeFile(join(output,'runtime-classpath.txt'),cpText);
files['runtime-classpath.txt']={sha256:hash(cpText),bytes:Buffer.byteLength(cpText)};
await writeFile(join(output,'provenance.json'),JSON.stringify({schema:1,sourceCommit,upstreamCommit:upstream,sourceChanges:changed,serverSources:sources,classpath,files,scope:'Exact packaged bytes and source labels. Does not prove source-to-binary reproducibility, Linux execution, cloud memory fit, or device multiplayer.'},null,2)+'\n');
const provenance=await readFile(join(output,'provenance.json'));
const checksums=Object.entries(files).sort(([a],[b])=>a.localeCompare(b)).map(([path,file])=>`${file.sha256}  ${path}`);
checksums.push(`${hash(provenance)}  provenance.json`);await writeFile(join(output,'SHA256SUMS'),checksums.join('\n')+'\n');
const archive=output+'.tar.gz';
execFileSync('tar',['-czf',archive,'-C',output,'.'],{env:{...process.env,COPYFILE_DISABLE:'1'},stdio:'inherit'});
console.log(JSON.stringify({output:relative(repo,output),archive:relative(repo,archive),archiveSHA256:hash(await readFile(archive)),classpathEntries:classpath.length,files:Object.keys(files).length,bytes:Object.values(files).reduce((sum,f)=>sum+f.bytes,0),sourceCommit,dirty:changed.length>0}));
