// ทดสอบเฉพาะโทษระดับสองบน demo Emulator ไม่แตะบัญชีหรือโพสต์ production
import { createRequire } from 'node:module';
import { processExpiredWarnings, processLegacyReports } from '../functions/index.mjs';
import { caseId } from '../functions/policy.mjs';
import { REPEAT_REPORT_WINDOW_MS } from '../functions/repeat_reports.mjs';
import { projectId, s, b, a, write, commit, get, allowed, denied, assert, documentName, createProfile } from './emulator_test_support.mjs';
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const db = getFirestore();
let passed = 0;
const pass = message => { passed++; console.log(`PASS repeat report ${passed}: ${message}`); };
const suffix = Date.now().toString(36);
async function user() {
  const email = `repeat-${suffix}-${Math.random().toString(36).slice(2)}@example.test`;
  const account = await getAuth().createUser({ email, password: 'Test-only-password123!', emailVerified: true });
  const response = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=test`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: 'Test-only-password123!', returnSecureToken: true }),
  });
  const result = await response.json();
  assert(response.ok, 'Emulator login failed');
  const member = { uid: account.uid, token: result.idToken };
  await createProfile(member);
  return member;
}
async function rpc(member, name, data, success = true) {
  const response = await fetch(`http://127.0.0.1:5001/${projectId}/asia-southeast1/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${member.token}` },
    body: JSON.stringify({ data }), signal: AbortSignal.timeout(30000),
  });
  const body = await response.json();
  assert(success ? response.ok && !body.error : !response.ok, `${name}: ${response.status} ${JSON.stringify(body)}`);
  return body.result ?? body.error;
}
await db.doc('app_config/security').set({ verificationRequired: true, writeTicketsRequired: true,
  reportBackendRequired: true, evidenceCopiesEnabled: false, rolloutAt: Timestamp.now() });
await db.doc('app_config/moderation').set({ reportThreshold: 2, warningHours: 24, suspensionHours: 72,
  minimumAccountHours: 0, autoEnforce: true, repeatReportSuspensionEnabled: true });
const [author, first, second, third, owner, freshAuthor] = await Promise.all(Array.from({ length: 6 }, user));
const report = (reporter, postId, groupId = null) => rpc(reporter, 'submitReport', { postId, groupId, reason: 'สแปม', details: '' });
const seedPost = async (member, id, groupId = null) => {
  const path = groupId ? `groups/${groupId}/posts/${id}` : `posts/${id}`;
  await db.doc(path).set({ [groupId ? 'authorId' : 'userId']: member.uid, authorName: 'Member', content: `Original ${id}`,
    mediaType: 'none', tags: [], visibility: 'public', authorIsPrivate: false, createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
  return db.doc(`moderation_cases/${caseId(path)}`);
};
const one = `one_${suffix}`, two = `two_${suffix}`;
const firstCase = await seedPost(author, one);
const secondCase = await seedPost(author, two);
await report(first, one);
assert((await firstCase.get()).data().status === 'queued', 'One reporter must not count as an offense');
assert(!(await db.doc(`account_state/${author.uid}`).get()).data()?.lastQualifyingReportAt, 'One report recorded an offense');
pass('one reporter is not a first or second case');
await report(second, one);
const firstData = (await firstCase.get()).data();
assert(firstData.status === 'warned' && firstData.repeatReportLevel === 1, 'First case must warn');
assert(Math.abs(firstData.deadline.toMillis() - Date.now() - 24 * 3600000) < 10000, 'First deadline is not 24 hours');
assert(!(await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil, 'First case must not suspend');
pass('first qualifying case warns for 24 hours without suspending');
await report(third, one);
assert((await firstCase.get()).data().deadline.isEqual(firstData.deadline), 'A third reporter renewed the first deadline');
assert((await firstCase.get()).data().repeatReportLevel === 1, 'Multiple reporters counted as multiple offenses');
assert((await report(first, one)).alreadyReported === true, 'Duplicate report was accepted');
pass('extra and duplicate reporters do not count another offense or renew time');
await db.doc(`posts/${one}`).update({ content: 'Edited after warning' });
await rpc(author, 'respondToWarning', { caseId: firstCase.id, action: 'edited' });
assert((await firstCase.get()).data().status === 'changed', 'First case did not close after edit');
const heldTicket = await rpc(author, 'reserveWrite', { path: `posts/direct_${suffix}` });
const heldWrite = () => [write(`posts/direct_${suffix}`, { userId: s(author.uid), authorName: s('Member'), content: s('Valid reserved post'),
  tags: a([]), visibility: s('public'), authorIsPrivate: b(false), mediaType: s('none') }, { timestamps: ['createdAt', 'updatedAt'] }),
  { delete: documentName(`write_tickets/${heldTicket.ticketId}`) }];
await report(first, two);
assert(!(await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil, 'One report on second post suspended');
await Promise.all([report(second, two), report(third, two)]);
const secondData = (await secondCase.get()).data();
assert(secondData.status === 'suspended' && secondData.repeatReportLevel === 2 && !secondData.deadline, 'Second case must suspend directly');
const until = (await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil.toMillis();
assert(Math.abs(until - Date.now() - 72 * 3600000) < 10000, 'Second penalty is not 72 hours');
assert((await db.doc(`posts/${two}`).get()).exists, 'Second-case feature unexpectedly deleted post');
assert((await db.collection(`account_state/${author.uid}/report_cases`).get()).size === 2, 'Concurrent reports counted duplicate cases');
pass('new qualifying case after correction suspends for 72 hours exactly once');
await report(first, two);
await processExpiredWarnings();
assert((await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil.toMillis() === until, 'Retry/worker extended suspension');
await rpc(author, 'respondToWarning', { caseId: secondCase.id, action: 'edited' }, false);
assert((await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil.toMillis() === until, 'Edit response lifted suspension');
pass('retries, background jobs and edit responses cannot reset or lift the penalty');

await rpc(author, 'reserveWrite', { path: `posts/blocked_${suffix}` }, false);
denied(await commit(author.token, heldWrite()), 'Even a ticket reserved before the ban cannot bypass it');
denied(await commit(author.token, [write(`account_state/${author.uid}`, {}, { mask: ['postingSuspendedUntil'] })]), 'Cannot clear suspension');
denied(await commit(author.token, [write(`account_state/${author.uid}/report_cases/forged`, { level: s('1') })]), 'Cannot forge private case ledger');
allowed(await get(author.token, `posts/${two}`), 'Suspended author can still read');
await rpc(author, 'sharePost', { postId: two, destination: 'feed', requestId: `blocked_share_${suffix}` }, false);
const room = `repeat_room_${suffix}`;
await db.doc(`conversations/${room}`).set({ participantIds: [author.uid, first.uid] });
await rpc(author, 'reserveWrite', { path: `conversations/${room}/messages/allowed_${suffix}` });
pass('posting/sharing are blocked server-side and the owner cannot erase history');

// โทษหมดแล้วคืนสิทธิ์จากเวลาเซิร์ฟเวอร์ ไม่ต้องลบประวัติหรือรอ job มาปลด
await db.doc(`account_state/${author.uid}`).update({ postingSuspendedUntil: Timestamp.fromMillis(Date.now() - 1) });
allowed(await commit(author.token, heldWrite()), 'The same valid ticket/post can commit once the ban expires');
await rpc(author, 'reserveWrite', { path: `posts/restored_${suffix}` });
pass('expiry restores posting automatically');

// รอบใหม่ของโพสต์เดิม ผู้รายงานเดิมใช้ได้อีก แต่ไม่เพิ่มยอดซ้ำในรอบนั้น
await db.doc(`posts/${one}`).update({ content: 'A new revision after correction' });
await report(first, one);
await report(second, one);
assert((await firstCase.get()).data().reportRound === 2, 'Edited post did not open another round');
assert((await firstCase.get()).data().repeatReportLevel === 2, 'Edited post escaped repeated-case penalty');
const againUntil = (await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil.toMillis();
assert(Math.abs(againUntil - Date.now() - 72 * 3600000) < 10000, 'Unexpected third-level escalation');
pass('same reporters can report a new revision; the maximum level remains 72 hours');

const oldCase = await seedPost(freshAuthor, `old_${suffix}`);
await db.doc(`account_state/${freshAuthor.uid}`).set({ lastQualifyingReportAt: Timestamp.fromMillis(Date.now() - REPEAT_REPORT_WINDOW_MS - 60000) });
await report(first, `old_${suffix}`); await report(second, `old_${suffix}`);
assert((await oldCase.get()).data().repeatReportLevel === 1 && (await oldCase.get()).data().status === 'warned', 'Old history was not expired');
pass('history older than 90 days starts with a first warning');

const groupId = `repeat_group_${suffix}`;
await db.doc(`groups/${groupId}`).set({ name: 'Group', ownerId: owner.uid, visibility: 'private', memberCount: 5, createdAt: Timestamp.now() });
for (const member of [owner, author, first, second, freshAuthor]) await db.doc(`groups/${groupId}/members/${member.uid}`).set({ uid: member.uid });
const g1 = `g1_${suffix}`, g2 = `g2_${suffix}`;
const groupFirst = await seedPost(freshAuthor, g1, groupId), groupSecond = await seedPost(freshAuthor, g2, groupId);
await report(first, g1, groupId); await report(second, g1, groupId);
assert((await groupFirst.get()).data().status === 'queued', 'Group-owner review was bypassed');
await rpc(owner, 'reviewGroupReport', { caseId: groupFirst.id, decision: 'warn' });
assert((await groupFirst.get()).data().repeatReportLevel === 1, 'Feed history incorrectly counted as a group case');
await report(first, g2, groupId);
await rpc(owner, 'reviewGroupReport', { caseId: groupSecond.id, decision: 'warn' });
assert((await groupSecond.get()).data().status === 'suspended', 'Second group review did not suspend');
assert((await db.doc(`group_account_state/${groupId}_${freshAuthor.uid}`).get()).data().postingSuspendedUntil.toMillis() > Date.now(), 'Group suspension missing');
assert(!(await db.doc(`account_state/${freshAuthor.uid}`).get()).data().postingSuspendedUntil, 'Group case globally suspended account');
await rpc(freshAuthor, 'reserveWrite', { path: `groups/${groupId}/posts/blocked_${suffix}` }, false);
await rpc(freshAuthor, 'reserveWrite', { path: `posts/group_only_${suffix}` });
pass('group review and group-only suspension keep their existing scope');

// การส่งรายงานจากแอปรุ่นเก่าต้องนำเข้ารอบเดียวกันโดยไม่คิดโทษซ้ำ
const beforeLegacy = (await db.collection(`account_state/${author.uid}/report_cases`).get()).size;
await db.doc(`post_reports/legacy_repeat_${suffix}`).set({ postId: two, reporterUid: first.uid, reason: 'สแปม', details: '', createdAt: Timestamp.now() });
await processLegacyReports();
assert((await db.doc(`post_reports/legacy_repeat_${suffix}`).get()).data().processed === true, 'Legacy report was not processed');
assert((await db.collection(`account_state/${author.uid}/report_cases`).get()).size === beforeLegacy, 'Legacy replay duplicated a case');
pass('legacy ingestion does not duplicate counted cases');

// รายงานเก่าก่อนเปิด flag ต้องไม่นับบัญชีเดิมซ้ำเมื่อเปลี่ยนรูปแบบ ID
await db.doc('app_config/moderation').update({ repeatReportSuspensionEnabled: false });
const migrationAuthor = await user(), migrationPost = `migration_${suffix}`;
const migrationCase = await seedPost(migrationAuthor, migrationPost);
await report(first, migrationPost);
await db.doc('app_config/moderation').update({ repeatReportSuspensionEnabled: true });
assert((await report(first, migrationPost)).alreadyReported === true, 'Old-format reporter counted twice on activation');
assert((await migrationCase.get()).data().reportCount === 1, 'Migration inflated reporter count');
await report(second, migrationPost);
assert((await migrationCase.get()).data().repeatReportLevel === 1, 'First newly qualified case must warn');
pass('enabling the feature cannot count an existing old-format reporter twice');
console.log(`PASS all ${passed} repeat report integration cases`);
