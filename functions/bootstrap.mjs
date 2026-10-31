import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { readPolicy } from './policy.mjs';

// เริ่มแบบ dry-run เสมอ ต้องระบุ project และ --apply เอง จึงไม่แก้โปรเจกต์ผิดโดยเผลอ
const args = process.argv.slice(2);
const project = args[args.indexOf('--project') + 1];
if (!args.includes('--project') || !project || project.startsWith('--')) throw new Error('Usage: node bootstrap.mjs --project PROJECT_ID [--apply] [--enable-moderation]');
if (args.includes('--firebase-cli')) { await import('./bootstrap-cli.mjs'); process.exit(0); }
initializeApp({projectId:project});
const db = getFirestore();
const apply = args.includes('--apply');
const previous = await db.doc('app_config/security').get();
const cutoff = previous.data()?.rolloutAt ?? Timestamp.now();
const grace = Timestamp.fromMillis(cutoff.toMillis() + 14 * 86400000);
if (apply && !previous.data()?.rolloutAt) await db.doc('app_config/security').set({rolloutAt:cutoff},{merge:true});
let token;
let eligible = 0;
let migrated = 0;
do {
  const page = await getAuth().listUsers(500, token);
  for (const user of page.users) {
    if (!user.email || Date.parse(user.metadata.creationTime) > cutoff.toMillis()) continue;
    eligible++;
    if (apply) {
      const ref = db.doc(`account_state/${user.uid}`);
      await db.runTransaction(async tx => {
        const current = await tx.get(ref);
        // รันซ้ำแล้วต้องไม่ต่อช่วงผ่อนผันหรือเขียนทับโทษที่มีอยู่
        const change = {uid:user.uid};
        if (!user.emailVerified && !current.data()?.verificationGraceUntil) change.verificationGraceUntil=grace;
        if (!current.data()?.clientUpgradeGraceUntil) change.clientUpgradeGraceUntil=grace;
        if (Object.keys(change).length>1) { tx.set(ref,change,{merge:true}); migrated++; }
      });
    }
  }
  token = page.pageToken;
} while(token);
if (apply) {
  const oldPolicy = (await db.doc('app_config/moderation').get()).data();
  const selected = readPolicy({...oldPolicy,reportThreshold:2,warningHours:24,suspensionHours:72,autoEnforce:args.includes('--enable-moderation')});
  await db.doc('app_config/moderation').set(selected);
  await db.doc('app_config/security').set({verificationRequired:true,writeTicketsRequired:true,reportBackendRequired:true,evidenceCopiesEnabled:true,rolloutAt:cutoff},{merge:true});
}
console.log(JSON.stringify({project,mode:apply?'applied':'dry-run',legacyEligible:eligible,legacyMigrated:migrated,graceUntil:grace.toDate().toISOString(),autoEnforce:apply&&args.includes('--enable-moderation')}));
