import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { firebaseRest } from '../functions/firebase-cli-token.mjs';

// สำรองเฉพาะ Rules กับชื่อ Functions ไม่มีการดึงโพสต์ แชท หรือข้อมูลสมาชิกมาเก็บ
const args=process.argv.slice(2);
const project=args[args.indexOf('--project')+1];
if (!args.includes('--project') || !/^[a-z][a-z0-9-]{4,29}$/.test(project ?? '')) throw new Error('A valid --project is required');
const target=resolve('build/social-validation/firebase-backup');
await mkdir(target,{recursive:true});
const releases=await firebaseRest(`https://firebaserules.googleapis.com/v1/projects/${project}/releases`);
const metadata=[];
for(const release of releases.releases ?? []) {
  const ruleset=await firebaseRest(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  const label=release.name.split('/releases/').at(-1).replaceAll('/','_');
  for(const [index,file] of (ruleset.source?.files ?? []).entries()) await writeFile(resolve(target,`${label}_${index}.rules`),file.content,'utf8');
  metadata.push({name:release.name,rulesetName:release.rulesetName});
}
await writeFile(resolve(target,'releases.json'),JSON.stringify(metadata,null,2));
let functions;
let functionsApi='enabled';
try {
  functions=await firebaseRest(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/-/functions`,{optional:true});
} catch(error) {
  if(error.reason !== 'SERVICE_DISABLED') throw error;
  functionsApi='not-enabled';
}
console.log(JSON.stringify({project,backedUpReleases:metadata.length,functionsApi,existingFunctions:(functions?.functions ?? []).map(item=>({name:item.name,codebase:item.labels?.['firebase-codebase']}))}));
