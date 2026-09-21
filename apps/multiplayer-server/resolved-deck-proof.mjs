import { readFile, writeFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Receipt for freshly exported Swift-resolved decks, not an alternative deck resolver.
const repo=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const output=process.argv[2];
if(process.argv.length!==3)throw Error('Usage: node resolved-deck-proof.mjs freshly-exported-deck-directory');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const bytes=path=>readFile(join(repo,path));
const cataloguePath='apps/ios/MagicMobile/Resources/ondevice-catalogue.json';
const catalogueBytes=await bytes(cataloguePath),catalogue=JSON.parse(catalogueBytes);
const lock=JSON.parse(await bytes('packages/ondevice-engine/upstream.lock.json'));
const rawHash=hash(await bytes('packages/ondevice-engine/build/generated/catalogue.jsonl'));
const registryHash=hash(await bytes('packages/ondevice-engine/build/generated/registry-report.json'));
const factory=await bytes('packages/ondevice-engine/build/generated/java/io/magicmobile/generated/GeneratedCardFactory.java');
const compiledHash=factory.toString().match(/CATALOGUE_HASH\s*=\s*"([a-f0-9]{64})"/)?.[1];
if(!compiledHash||catalogue.upstreamCommit!==lock.commit||catalogue.catalogueHash!==compiledHash||catalogue.sourceCatalogueSHA256!==rawHash||catalogue.sourceRegistrySHA256!==registryHash)throw Error('Committed app catalogue does not match freshly built engine; review engine/catalogue integration before packaging');
const ids=['chaos-incarnate','draconic-destruction','token-triumph','first-flight','grave-danger'];
if(JSON.stringify((await readdir(output)).sort())!==JSON.stringify(ids.map(id=>id+'.json').sort()))throw Error('Expected exactly five fresh resolved decks and no old proof');
const decks=[];
for(const id of ids){
  const data=await readFile(join(output,id+'.json')),deck=JSON.parse(data);
  if(!Array.isArray(deck.main)||!Array.isArray(deck.commanders)||deck.commanders.length!==1)throw Error('Invalid resolved precon '+id);
  const rows=[...deck.main,...deck.commanders,...(deck.companions??[])];
  if(rows.some(row=>!Number.isInteger(row.count)||row.count<1||!row.name||!row.setCode||!row.collectorNumber)||rows.reduce((n,row)=>n+row.count,0)!==100)throw Error('Resolved precon counts/printing identities changed: '+id);
  decks.push({id,sha256:hash(data)});
}
const preconSource='apps/ios/MagicMobile/PreconCatalog.swift',resolverSource='apps/ios/MagicMobile/OnDeviceDeckResolver.swift';
await writeFile(join(output,'provenance.json'),JSON.stringify({schema:1,sourceCommit:execFileSync('git',['rev-parse','HEAD'],{cwd:repo,encoding:'utf8'}).trim(),upstreamCommit:lock.commit,preconSource,preconSourceSHA256:hash(await bytes(preconSource)),resolverSource,resolverSHA256:hash(await bytes(resolverSource)),catalogueSHA256:rawHash,bundledCatalogueSHA256:hash(catalogueBytes),registrySHA256:registryHash,catalogueHash:compiledHash,decks},null,2)+'\n',{flag:'wx'});
console.log('PASS: five fresh Swift-resolved decks match committed source and freshly generated engine/catalogue identity');
