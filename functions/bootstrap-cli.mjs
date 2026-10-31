import { mkdir, writeFile } from 'node:fs/promises';
import { firebaseRest } from './firebase-cli-token.mjs';
import { readPolicy } from './policy.mjs';

// ทางเลือกสำหรับเครื่องที่ใช้ Firebase CLI อยู่แล้ว ไม่ต้องสร้างกุญแจ service account
const args=process.argv.slice(2);
const project=args[args.indexOf('--project')+1];
if (!args.includes('--project') || !/^[a-z][a-z0-9-]{4,29}$/.test(project ?? '')) throw new Error('A valid --project is required');
if (process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.FIRESTORE_EMULATOR_HOST) throw new Error('CLI bootstrap cannot mix production credentials with emulator environment');
const apply=args.includes('--apply');
const base=`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const get = path => firebaseRest(`${base}/${path}`,{optional:true});
function value(input) {
  if (typeof input==='boolean') return {booleanValue:input};
  if (typeof input==='number') return {integerValue:String(input)};
  if (input instanceof Date) return {timestampValue:input.toISOString()};
  return {stringValue:String(input)};
}
async function patch(path, data) {
  const query=new URLSearchParams();
  for(const key of Object.keys(data)) query.append('updateMask.fieldPaths',key);
  return firebaseRest(`${base}/${path}?${query}`,{method:'PATCH',body:{fields:Object.fromEntries(Object.entries(data).map(([key,item])=>[key,value(item)]))}});
}
const security=await get('app_config/security');
const oldPolicy=await get('app_config/moderation');
const cutoff=new Date(security?.fields?.rolloutAt?.timestampValue ?? Date.now());
const grace=new Date(cutoff.getTime()+14*86400000);
if (apply) {
  await mkdir('build/social-validation',{recursive:true});
  await writeFile('build/social-validation/pre-rollout-config.json',JSON.stringify({project,security,moderation:oldPolicy},null,2));
  if (!security?.fields?.rolloutAt) await patch('app_config/security',{rolloutAt:cutoff});
}
let pageToken;
let eligible=0;
let migrated=0;
do {
  const params=new URLSearchParams({maxResults:'500',...(pageToken?{nextPageToken:pageToken}:{})});
  const page=await firebaseRest(`https://identitytoolkit.googleapis.com/v1/projects/${project}/accounts:batchGet?${params}`);
  for (const user of page.users ?? []) {
    if (!user.email || Number(user.createdAt)>cutoff.getTime()) continue;
    eligible++;
    if (!apply) continue;
    const path=`account_state/${encodeURIComponent(user.localId)}`;
    const current=await get(path);
    const change={uid:user.localId};
    if (!user.emailVerified && !current?.fields?.verificationGraceUntil) change.verificationGraceUntil=grace;
    if (!current?.fields?.clientUpgradeGraceUntil) change.clientUpgradeGraceUntil=grace;
    if(Object.keys(change).length>1) { await patch(path,change); migrated++; }
  }
  pageToken=page.nextPageToken;
} while(pageToken);
if(apply) {
  const previous={};
  for(const [key,field] of Object.entries(oldPolicy?.fields ?? {})) previous[key]=field.booleanValue ?? Number(field.integerValue);
  await patch('app_config/moderation',readPolicy({...previous,reportThreshold:2,warningHours:24,suspensionHours:72,autoEnforce:args.includes('--enable-moderation')}));
  await patch('app_config/security',{verificationRequired:true,writeTicketsRequired:true,reportBackendRequired:true,evidenceCopiesEnabled:true,rolloutAt:cutoff});
}
console.log(JSON.stringify({project,mode:apply?'applied':'dry-run',legacyEligible:eligible,legacyMigrated:migrated,graceUntil:grace.toISOString(),autoEnforce:apply&&args.includes('--enable-moderation')}));
