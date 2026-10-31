import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { firebaseRest, cliAccessToken } from '../functions/firebase-cli-token.mjs';

// ตรวจ production แบบอ่านอย่างเดียว ไม่สร้างโพสต์/แชท/รายงานทดสอบใส่ผู้ใช้จริง
const args = process.argv.slice(2);
const project = args[args.indexOf('--project') + 1];
assert(args.includes('--project') && /^[a-z][a-z0-9-]{4,29}$/.test(project ?? ''), 'A valid --project is required');
const activated = args.includes('--activated');
const result = { project, checkedAt: new Date().toISOString(), phase: activated ? 'activated' : 'before-activation' };
const digest = value => createHash('sha256').update(value.replaceAll('\r\n', '\n')).digest('hex');

const releases = await firebaseRest(`https://firebaserules.googleapis.com/v1/projects/${project}/releases`);
result.rules = [];
for (const [file, suffix] of [['firestore.rules', '/releases/cloud.firestore'], ['storage.rules', '/releases/firebase.storage/']]) {
  const release = (releases.releases ?? []).find(item => suffix.endsWith('/') ? item.name.includes(suffix) : item.name.endsWith(suffix));
  assert(release, `Missing release: ${file}`);
  const ruleset = await firebaseRest(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  const local = digest(await readFile(file, 'utf8'));
  assert(ruleset.source.files.some(item => digest(item.content) === local), `Published ${file} differs from tested source`);
  result.rules.push({ file, matches: true, sha256: local, ruleset: release.rulesetName });
}
console.log('PASS production: published Firestore and Storage Rules match tested files');

// API เติม __name__ ให้ index เอง จึงตัดเฉพาะ field นี้ก่อนเทียบกับไฟล์ต้นทาง
const key = (group, item) => JSON.stringify([group, item.queryScope, item.fields.filter(field => field.fieldPath !== '__name__').map(field => [field.fieldPath, field.order ?? field.arrayConfig])]);
const wanted = JSON.parse(await readFile('firestore.indexes.json', 'utf8')).indexes;
const remote = [];
let pageToken;
do {
  // wildcard collectionGroups/- รองรับเฉพาะ page size ค่าเริ่มต้น
  const query = new URLSearchParams(pageToken ? { pageToken } : {});
  const page = await firebaseRest(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/-/indexes?${query}`);
  remote.push(...(page.indexes ?? []));
  pageToken = page.nextPageToken;
} while (pageToken);
const states = wanted.map(item => {
  const index = remote.find(candidate => key(candidate.name.split('/collectionGroups/')[1].split('/')[0], candidate) === key(item.collectionGroup, item));
  return { collectionGroup: item.collectionGroup, fields: item.fields, state: index?.state ?? 'MISSING' };
});
assert(states.every(item => item.state === 'READY'), `Indexes not ready: ${JSON.stringify(states.filter(item => item.state !== 'READY'))}`);
result.indexes = { ready: states.length, expected: wanted.length };
console.log(`PASS production: all ${states.length} required indexes are READY`);

const expected = ['enforceWarnings', 'legacyReportWorker', 'blockCleanupWorker', 'evidenceCopyWorker', 'reserveWrite', 'respondToWarning', 'reviewGroupReport', 'sharePost', 'submitReport'];
const functions = await firebaseRest(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/asia-southeast1/functions`);
const deployed = expected.map(name => (functions.functions ?? []).find(item => item.name.endsWith('/' + name)));
assert(deployed.every(item => item?.state === 'ACTIVE' && item.buildConfig?.runtime === 'nodejs22' && item.labels?.['firebase-functions-codebase'] === 'linko'), 'Some Linko functions are missing or not ACTIVE on Node22');
result.functions = deployed.map(item => ({ name: item.name.split('/').at(-1), state: item.state, runtime: item.buildConfig.runtime, generation: item.environment }));
result.retiredResources = (functions.functions ?? []).filter(item => ['ingestLegacyReport','onBlockChanged','preserveEvidence'].includes(item.name.split('/').at(-1))).map(item => ({name:item.name.split('/').at(-1),state:item.state}));
console.log('PASS production: all 9 Linko functions are ACTIVE in asia-southeast1');

// ไม่เก็บ Authorization header ลง log ใช้ token เดิมในหน่วยความจำเพื่ออ่าน Scheduler เท่านั้น
const schedulerResponse = await fetch(`https://cloudscheduler.googleapis.com/v1/projects/${project}/locations/asia-southeast1/jobs`, {
  headers: { Authorization: `Bearer ${await cliAccessToken()}` }, signal: AbortSignal.timeout(30000),
});
assert(schedulerResponse.ok, `Cannot inspect scheduler: HTTP ${schedulerResponse.status}`);
const scheduler = await schedulerResponse.json();
result.schedulers=[];
for(const [functionName,schedules] of [['enforceWarnings',['every 5 minutes','*/5 * * * *']],['legacyReportWorker',['* * * * *','every 1 minutes']],['blockCleanupWorker',['* * * * *','every 1 minutes']],['evidenceCopyWorker',['* * * * *','every 1 minutes']]]) {
  const job = (scheduler.jobs ?? []).find(item => item.name.includes(`firebase-schedule-${functionName}-`));
  assert(job?.state === 'ENABLED' && job.httpTarget?.oidcToken?.serviceAccountEmail, `${functionName} scheduler is not enabled with authenticated delivery`);
  assert(schedules.includes(job.schedule), `Unexpected ${functionName} schedule`);
  assert(!job.lastAttemptTime || !job.status?.code, `${functionName} last execution failed`);
  result.schedulers.push({name:functionName,state:job.state,schedule:job.schedule,timeZone:job.timeZone,lastAttemptTime:job.lastAttemptTime ?? null,lastAttemptCode:job.lastAttemptTime ? job.status?.code ?? 0 : null});
}
console.log('PASS production: 4 schedulers are enabled with OIDC; enforcement every 5 minutes, workers every minute');

// เรียกแบบไม่ล็อกอินต้องถูกปฏิเสธก่อนเขียนข้อมูล เป็น smoke check ที่ไม่มีข้อมูลผู้ใช้จริง
result.callableChecks = [];
for (const name of ['reserveWrite', 'respondToWarning', 'reviewGroupReport', 'sharePost', 'submitReport']) {
  // ใช้ URL เดียวกับ Flutter FirebaseFunctions SDK เพื่อตรวจ routing จริงด้วย
  const endpoint = `https://asia-southeast1-${project}.cloudfunctions.net/${name}`;
  const response = await fetch(endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ data: {} }), signal: AbortSignal.timeout(60000) });
  const body = await response.json();
  assert(response.status === 401 && body.error?.status === 'UNAUTHENTICATED', `${name} did not reject unauthenticated calls as expected`);
  result.callableChecks.push({ name, status: response.status, error: body.error.status, via: 'cloudfunctions.net' });
}
console.log('PASS production: 5 callable endpoints reject unauthenticated calls without test writes');
const preflight = await fetch(`https://asia-southeast1-${project}.cloudfunctions.net/submitReport`, {
  method: 'OPTIONS', headers: { Origin: `https://${project}.web.app`, 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'authorization,content-type' }, signal: AbortSignal.timeout(30000),
});
assert(preflight.status === 204 && preflight.headers.get('access-control-allow-origin'), 'Callable browser CORS preflight failed');
result.browserPreflight = { status: preflight.status, allowed: true };
console.log('PASS production: callable CORS preflight allows browser requests');

if (activated) {
  const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
  const security = (await firebaseRest(`${base}/app_config/security`)).fields;
  const policy = (await firebaseRest(`${base}/app_config/moderation`)).fields;
  assert(['verificationRequired', 'writeTicketsRequired', 'reportBackendRequired', 'evidenceCopiesEnabled'].every(field => security[field]?.booleanValue === true), 'Security flags are not enabled');
  assert(Number(policy.reportThreshold?.integerValue) === 2 && Number(policy.warningHours?.integerValue) === 24 && Number(policy.suspensionHours?.integerValue) === 72 && policy.autoEnforce?.booleanValue === true, 'Moderation policy differs from approved 2/24/72');
  const cutoff = Date.parse(security.rolloutAt.timestampValue);
  const expectedGrace = cutoff + 14 * 86400000;
  let legacyAccounts = 0;
  let nextPageToken;
  do {
    const query = new URLSearchParams({ maxResults: '500', ...(nextPageToken ? { nextPageToken } : {}) });
    const page = await firebaseRest(`https://identitytoolkit.googleapis.com/v1/projects/${project}/accounts:batchGet?${query}`);
    for (const user of page.users ?? []) {
      if (!user.email || Number(user.createdAt) > cutoff) continue;
      const state = (await firebaseRest(`${base}/account_state/${encodeURIComponent(user.localId)}`)).fields;
      const clientGrace = Date.parse(state.clientUpgradeGraceUntil?.timestampValue);
      assert(Number.isFinite(clientGrace) && clientGrace <= expectedGrace, 'Missing or extended legacy client grace');
      if (!user.emailVerified) {
        const verificationGrace = Date.parse(state.verificationGraceUntil?.timestampValue);
        assert(Number.isFinite(verificationGrace) && verificationGrace <= expectedGrace, 'Missing or extended verification grace');
      }
      legacyAccounts++;
    }
    nextPageToken = page.nextPageToken;
  } while (nextPageToken);
  result.activation = { reportThreshold: 2, warningHours: 24, suspensionHours: 72, autoEnforce: true, legacyAccounts, rolloutAt: new Date(cutoff).toISOString(), graceUntil: new Date(expectedGrace).toISOString() };
  console.log(`PASS production: policy 2/24/72 enabled and grace verified for ${legacyAccounts} legacy accounts`);
  // ดูรอบงานจริงหลังเปิดระบบ โดยไม่เปิดเผย lastId ซึ่งอาจมีรหัสผู้รายงาน
  result.workerExecutions=[];
  for(const [name,cursor] of [['legacyReportWorker','legacy_reports'],['blockCleanupWorker','block_cleanup'],['evidenceCopyWorker','evidence_copies']]) {
    const state=await firebaseRest(`${base}/backend_cursors/${cursor}`,{optional:true});
    const job=result.schedulers.find(item=>item.name===name);
    result.workerExecutions.push({name,cursorExists:state!==null,ranAfterActivation:Date.parse(job.lastAttemptTime ?? '')>=cutoff,firestoreWriteObserved:Date.parse(state?.updateTime ?? '')>=cutoff});
  }
  if(result.workerExecutions.every(item=>item.cursorExists && item.ranAfterActivation && item.firestoreWriteObserved)) console.log('PASS production: all 3 workers executed after activation and wrote protected cursor state');
  else console.log('INFO production: waiting for the first scheduled worker runs after activation');
}
await mkdir('build/social-validation', { recursive: true });
await writeFile(`build/social-validation/production-${result.phase}.json`, JSON.stringify(result, null, 2) + '\n');
console.log('PASS production readiness checks complete');
