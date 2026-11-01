import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { scanWork } from './workers.mjs';
import { getStorage } from 'firebase-admin/storage';
import { randomUUID } from 'node:crypto';
import { setGlobalOptions } from 'firebase-functions/v2';
import { readPolicy, caseId, contentHash, needsWarning, suspensionEnd, reserveRate } from './policy.mjs';

initializeApp();
setGlobalOptions({ region: 'asia-southeast1', maxInstances: 5 });
const db = getFirestore();
// งานหลังบ้านใช้ worker มี checkpoint เพราะ Functions API ยังไม่รับ trigger จาก Bangkok
const workerSchedule = {schedule:'* * * * *',timeoutSeconds:300,maxInstances:1,concurrency:1};
const stamp = () => FieldValue.serverTimestamp();
const fail = (code, message) => { throw new HttpsError(code, message); };
const id = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value) ? value : fail('invalid-argument', 'รหัสรายการไม่ถูกต้อง');

async function member(request) {
  const uid = request.auth?.uid;
  if (!uid) fail('unauthenticated', 'กรุณาเข้าสู่ระบบก่อน');
  if (request.auth.token.email_verified !== true) {
    const state = (await db.doc(`account_state/${uid}`).get()).data();
    if (!(state?.verificationGraceUntil?.toMillis() > Date.now())) fail('failed-precondition', 'กรุณายืนยันอีเมลก่อน');
  }
  return uid;
}
const policy = async () => readPolicy((await db.doc('app_config/moderation').get()).data());
async function blocked(a, b) {
  const edges = await db.getAll(db.doc(`users/${a}/blocks/${b}`), db.doc(`users/${b}/blocks/${a}`));
  return edges.some(doc => doc.exists);
}
function sourcePath(postId, groupId) { return groupId ? `groups/${id(groupId)}/posts/${id(postId)}` : `posts/${id(postId)}`; }
async function source(uid, postId, groupId) {
  const path = sourcePath(postId, groupId);
  const snap = await db.doc(path).get();
  if (!snap.exists || snap.data().isDeleting) fail('not-found', 'โพสต์นี้ไม่พร้อมใช้งาน');
  const post = snap.data();
  const ownerId = post.userId ?? post.authorId;
  if (await blocked(uid, ownerId)) fail('permission-denied', 'ไม่สามารถโต้ตอบกับบัญชีนี้ได้');
  let groupOwnerId = null;
  if (groupId) {
    const [group, membership] = await db.getAll(db.doc(`groups/${groupId}`), db.doc(`groups/${groupId}/members/${uid}`));
    groupOwnerId = group.data()?.ownerId;
    if (!membership.exists && groupOwnerId !== uid) fail('permission-denied', 'เฉพาะสมาชิกกลุ่มเท่านั้น');
  } else if (ownerId !== uid && post.visibility !== 'public') {
    const follower = await db.doc(`users/${ownerId}/followers/${uid}`).get();
    if (post.visibility !== 'followers' || !follower.exists) fail('permission-denied', 'ไม่มีสิทธิ์ดูโพสต์นี้');
  }
  return { path, post, ownerId, groupOwnerId };
}

// ticket ผูกกับ path จริง และต้องถูกใช้ทิ้งพร้อมสร้างข้อมูล จึงนำใบเดิมมาโพสต์รัวไม่ได้
export const reserveWrite = onCall(async request => {
  const uid = await member(request);
  const path = String(request.data?.path ?? '');
  const postMatch = path.match(/^posts\/([\w-]+)$/);
  const groupMatch = path.match(/^groups\/([\w-]+)\/posts\/([\w-]+)$/);
  const messageMatch = path.match(/^conversations\/([\w-]+)\/messages\/([\w-]+)$/);
  if (!postMatch && !groupMatch && !messageMatch) fail('invalid-argument', 'ตำแหน่งข้อมูลไม่ถูกต้อง');
  if (groupMatch) {
    if (!(await db.doc(`groups/${groupMatch[1]}/members/${uid}`).get()).exists) fail('permission-denied', 'ยังไม่ได้เป็นสมาชิกกลุ่ม');
  }
  if (messageMatch) {
    const room = (await db.doc(`conversations/${messageMatch[1]}`).get()).data();
    if (!room?.participantIds?.includes(uid)) fail('permission-denied', 'ไม่ใช่สมาชิกแชท');
    const peer = room.participantIds.find(value => value !== uid);
    if (peer && await blocked(uid, peer)) fail('permission-denied', 'ส่งข้อความไม่ได้ เพราะมีการบล็อกกัน');
  }
  const kind = messageMatch ? 'message' : 'post';
  const now = Date.now();
  const targetId = path.split('/').at(-1);
  const ticketRef = db.doc(`write_tickets/${uid}_${targetId}`);
  const limitRef = db.doc(`rate_limits/${uid}_${kind}`);
  await db.runTransaction(async tx => {
    const refs = [ticketRef, limitRef, db.doc(`account_state/${uid}`), db.doc(path)];
    if (groupMatch) refs.push(db.doc(`group_account_state/${groupMatch[1]}_${uid}`));
    const [ticket, limit, state, existing, groupState] = await tx.getAll(...refs);
    if (existing.exists) fail('already-exists', 'รายการนี้ถูกสร้างแล้ว');
    if (kind === 'post' && [state, groupState].some(doc => doc?.data()?.postingSuspendedUntil?.toMillis() > now)) fail('permission-denied', 'บัญชีนี้อยู่ระหว่างพักสิทธิ์โพสต์');
    if (ticket.exists && ticket.data().targetPath === path && ticket.data().expiresAt.toMillis() > now) return;
    const next = reserveRate(limit.data(), now, kind === 'post' ? 60000 : 10000, kind === 'post' ? 5 : 15);
    if (!next) fail('resource-exhausted', 'ส่งเร็วไปนิด รอสักครู่แล้วลองใหม่นะ');
    tx.set(limitRef, next);
    tx.set(ticketRef, { uid, targetPath: path, expiresAt: Timestamp.fromMillis(now + 300000) });
  });
  return { ticketId: ticketRef.id };
});

async function submitReportImpl(request, legacyRef = null) {
  const uid = await member(request);
  const postId = id(request.data?.postId);
  const groupId = request.data?.groupId == null ? null : id(request.data.groupId);
  const reason = String(request.data?.reason ?? '');
  const reasons = ['สแปม', 'คุกคามหรือกลั่นแกล้ง', 'เนื้อหารุนแรง', 'เนื้อหาทางเพศ', 'ข้อมูลเท็จ', 'อื่น ๆ'];
  if (!reasons.includes(reason)) fail('invalid-argument', 'เลือกเหตุผลที่รองรับก่อนนะ');
  const details = String(request.data?.details ?? '').trim();
  if (details.length > 300) fail('invalid-argument', 'รายละเอียดต้องไม่เกิน 300 ตัวอักษร');
  const target = await source(uid, postId, groupId);
  if (target.ownerId === uid) fail('permission-denied', 'รายงานโพสต์ตัวเองไม่ได้');
  const rules = await policy();
  const actor = await getAuth().getUser(uid);
  if (Date.now() - Date.parse(actor.metadata.creationTime) < rules.minimumAccountHours * 3600000) fail('failed-precondition', `บัญชีใหม่ต้องรอให้ครบ ${rules.minimumAccountHours} ชั่วโมงก่อนรายงาน`);
  // hash รวมตำแหน่งเต็ม กันชื่อโพสต์ Feed ไปชนกับ ID รายงานในกลุ่ม
  const reportRef = db.doc(`post_reports/${caseId(target.path)}_${uid}`);
  const caseRef = db.doc(`moderation_cases/${caseId(target.path)}`);
  const notificationRef = db.doc(`notifications/warning_${caseRef.id}`);
  const now = Date.now();
  const result = await db.runTransaction(async tx => {
    const [existing, current, fresh, rate] = await tx.getAll(reportRef, caseRef, db.doc(target.path), db.doc(`rate_limits/${uid}_report`));
    if (existing.exists) { if (legacyRef) tx.update(legacyRef, {processed:true}); return { alreadyReported: true }; }
    if (!fresh.exists || fresh.data().isDeleting) fail('not-found', 'โพสต์นี้ไม่พร้อมใช้งาน');
    const nextRate = reserveRate(rate.data(), now, 3600000, 10);
    if (!nextRate) fail('resource-exhausted', 'รายงานหลายรายการแล้ว ลองใหม่ภายหลังนะ');
    const hash = contentHash(fresh.data());
    const sameRound = current.data()?.contentHash === hash;
    const count = (sameRound ? current.data()?.reportCount ?? 0 : 0) + 1;
    const alreadyWarned = sameRound && ['warned', 'contested', 'removed'].includes(current.data()?.status);
    const warn = !alreadyWarned && needsWarning(count, rules, target.ownerId === target.groupOwnerId ? null : groupId);
    tx.create(reportRef, { postId, groupId, postOwnerId: target.ownerId, reporterUid: uid, reason, details, contentHash: hash, status: 'open', processed: true, createdAt: stamp() });
    if (legacyRef) tx.update(legacyRef, {processed:true});
    tx.set(db.doc(`rate_limits/${uid}_report`), nextRate);
    const base = { sourcePath: target.path, postId, groupId, groupOwnerId: target.groupOwnerId, ownerId: target.ownerId, reason, details, reportCount: count, contentHash: hash, updatedAt: stamp(), snapshot: fresh.data() };
    if (!sameRound) base.createdAt = stamp();
    if (warn) {
      base.status = 'warned';
      base.deadline = Timestamp.fromMillis(now + rules.warningHours * 3600000);
      tx.set(notificationRef, { recipientId: target.ownerId, actorId: target.ownerId, actorName: 'Linko', type: 'moderation', body: 'มีรายงานโพสต์ของคุณ เปิดดูเหตุผลและแก้ไขก่อนหมดเวลา', caseId: caseRef.id, isRead: false, createdAt: stamp() });
    } else if (!sameRound) base.status = 'queued';
    tx.set(caseRef, base, { merge: true });
    if (groupId && target.groupOwnerId !== target.ownerId) {
      tx.set(db.doc(`notifications/group_report_${caseRef.id}`), { recipientId: target.groupOwnerId, actorId: target.groupOwnerId, actorName: 'Linko', type: 'moderation_group', body: `มีรายงานโพสต์ในกลุ่ม ${count} บัญชี เปิดดูเพื่อจัดการได้เลย`, caseId: caseRef.id, groupId, isRead: false, createdAt: stamp() });
    }
    return { alreadyReported: false };
  });
  // คัดลอกก่อนตอบกลับ เพื่อลดช่วงที่ภาพต้นฉบับอาจถูกแก้/ลบ; worker ลองต่อหาก Storage ขัดข้อง
  try { await copyEvidence(caseRef); }
  catch (error) { console.warn('Evidence copy deferred to worker', {code:error.code ?? 'unknown'}); }
  return result;
}

export const submitReport = onCall(request => submitReportImpl(request));

// แอปรุ่นเก่ายังส่งรายงานได้ในช่วงผ่อนผัน ระบบจะนำเข้าคิวเดียวกับแอปรุ่นใหม่
async function ingestReportEvent(event) {
  const data = event.data?.data();
  if (!data || data.processed === true) return;
  try {
    const user = await getAuth().getUser(data.reporterUid);
    await submitReportImpl({auth:{uid:user.uid,token:{email_verified:user.emailVerified}},data:{postId:data.postId,groupId:data.groupId ?? null,reason:data.reason,details:data.details ?? ''}}, event.data.ref);
  } catch (error) {
    // บัญชีอาจถูกลบระหว่างส่งกับประมวลผล ไม่ต้อง retry รายงานที่ทำต่อไม่ได้แล้ว
    if (!['permission-denied','failed-precondition','invalid-argument','not-found','resource-exhausted','auth/user-not-found'].includes(error.code)) throw error;
    await event.data.ref.update({processed:true,status:'ignored',processingReason:error.code});
  }
}

// เจ้าของกลุ่มตัดสินได้เฉพาะกลุ่มตัวเอง และไม่มีสิทธิ์พักบัญชีทั้งแอป
export const reviewGroupReport = onCall(async request => {
  const uid = await member(request);
  const ref = db.doc(`moderation_cases/${id(request.data?.caseId)}`);
  const decision = request.data?.decision;
  if (!['dismiss', 'warn', 'remove'].includes(decision)) fail('invalid-argument', 'ไม่รองรับการตัดสินนี้');
  const rules = await policy();
  await db.runTransaction(async tx => {
    const current = await tx.get(ref);
    const data = current.data();
    if (!data?.groupId) fail('not-found', 'ไม่พบรายงานกลุ่ม');
    const [group, post] = await tx.getAll(db.doc(`groups/${data.groupId}`), db.doc(data.sourcePath));
    if (group.data()?.ownerId !== uid || data.ownerId === uid) fail('permission-denied', 'จัดการได้เฉพาะกลุ่มตัวเอง และตรวจรายงานของตัวเองไม่ได้');
    if (!['queued', 'warned', 'contested'].includes(data.status)) fail('failed-precondition', 'เรื่องนี้ถูกดำเนินการแล้ว');
    // กดเตือนซ้ำหรือเน็ตส่งซ้ำต้องไม่ต่อเวลาให้เรื่อยๆ
    if (decision === 'warn' && data.status === 'warned') return;
    if (decision !== 'dismiss' && (!post.exists || contentHash(post.data()) !== data.contentHash)) {
      tx.update(ref, {status:'changed',updatedAt:stamp()});
      return;
    }
    const now = Date.now();
    const update = { reviewedBy: uid, reviewedAt: stamp(), updatedAt: stamp() };
    if (decision === 'dismiss') update.status = 'dismissed';
    if (decision === 'warn') { update.status = 'warned'; update.deadline = Timestamp.fromMillis(now + rules.warningHours * 3600000); }
    if (decision === 'remove') {
      update.status = 'removed';
      if (post.exists) { tx.set(db.doc(`moderation_archives/${ref.id}`), { ...data, snapshot: post.data(), archivedAt: stamp() }); tx.delete(post.ref); }
    }
    tx.update(ref, update);
    tx.set(db.doc(`notifications/moderation_${ref.id}_${decision}`), { recipientId: data.ownerId, actorId: uid, actorName: 'ผู้ดูแลกลุ่ม', type: 'moderation', body: decision === 'warn' ? 'โพสต์ในกลุ่มได้รับคำเตือน เปิดดูรายละเอียดและกำหนดแก้ไข' : decision === 'remove' ? 'เจ้าของกลุ่มนำโพสต์ของคุณออกแล้ว' : 'ปิดรายงานโพสต์ในกลุ่มแล้ว', caseId: ref.id, isRead: false, createdAt: stamp() });
  });
  return { ok: true };
});

export const respondToWarning = onCall(async request => {
  const uid = await member(request);
  const ref = db.doc(`moderation_cases/${id(request.data?.caseId)}`);
  const action = request.data?.action;
  if (!['edited', 'delete', 'contest'].includes(action)) fail('invalid-argument', 'เลือกวิธีตอบคำเตือนก่อนนะ');
  await db.runTransaction(async tx => {
    const current = await tx.get(ref);
    const data = current.data();
    if (!data || data.ownerId !== uid) fail('permission-denied', 'ไม่ใช่เจ้าของโพสต์');
    const post = await tx.get(db.doc(data.sourcePath));
    if (action === 'edited' && (!post.exists || contentHash(post.data()) === data.contentHash)) fail('failed-precondition', 'ยังไม่พบการเปลี่ยนเนื้อหา ลองแก้โพสต์ก่อนนะ');
    if (!['warned', 'queued', 'contested'].includes(data.status)) fail('failed-precondition', 'เรื่องนี้ถูกดำเนินการแล้ว');
    const update = { status: action === 'edited' ? 'changed' : action === 'delete' ? 'resolved' : 'contested', respondedAt: stamp(), updatedAt: stamp(), deadline: FieldValue.delete() };
    if (action === 'delete' && post.exists) { tx.set(db.doc(`moderation_archives/${ref.id}`), { ...data, snapshot: post.data(), archivedAt: stamp() }); tx.delete(post.ref); }
    // โต้แย้งแล้วพักการลงโทษอัตโนมัติไว้ก่อน ระบบไม่นับยอด Report เป็นหลักฐานว่าผิดจริง
    tx.update(ref, update);
  });
  return { ok: true };
});

export async function processExpiredWarnings() {
  const rules = await policy();
  if (!rules.autoEnforce) return;
  const due = await db.collection('moderation_cases').where('status', '==', 'warned').where('deadline', '<=', Timestamp.now()).limit(100).get();
  for (const entry of due.docs) {
    await db.runTransaction(async tx => {
      const current = await tx.get(entry.ref);
      const data = current.data();
      const now = Date.now();
      if (data?.status !== 'warned' || data.deadline?.toMillis() > now) return;
      const stateRef = db.doc(data.groupId ? `group_account_state/${data.groupId}_${data.ownerId}` : `account_state/${data.ownerId}`);
      const [post, state] = await tx.getAll(db.doc(data.sourcePath), stateRef);
      // โพสต์ถูกแก้/ลบไปแล้ว จะไม่ลงโทษจากภาพเก่า และไม่รีเซ็ตเวลาจาก report ซ้ำ
      if (!post.exists || contentHash(post.data()) !== data.contentHash) { tx.update(entry.ref, { status: 'changed', updatedAt: stamp() }); return; }
      tx.set(db.doc(`moderation_archives/${entry.id}`), { ...data, snapshot: post.data(), archivedAt: stamp() });
      tx.delete(post.ref);
      const until = Math.max(state.data()?.postingSuspendedUntil?.toMillis() ?? 0, suspensionEnd(now, rules.suspensionHours));
      tx.set(stateRef, { uid: data.ownerId, postingSuspendedUntil: Timestamp.fromMillis(until), lastCaseId: entry.id }, { merge: true });
      tx.update(entry.ref, { status: 'removed', removedAt: stamp(), updatedAt: stamp(), suspensionUntil: Timestamp.fromMillis(until) });
      tx.set(db.doc(`notifications/removed_${entry.id}`), { recipientId: data.ownerId, actorId: data.ownerId, actorName: 'Linko', type: 'moderation', body: `นำโพสต์ออกและพักสิทธิ์โพสต์ ${rules.suspensionHours} ชั่วโมงแล้ว เปิดดูรายละเอียดได้ที่นี่`, caseId: entry.id, isRead: false, createdAt: stamp() });
    });
  }
}
export const enforceWarnings = onSchedule('every 5 minutes', processExpiredWarnings);

// การบล็อกต้องทำให้แชทเดิมส่งต่อไม่ได้ด้วย ไม่ลบข้อความเก่าของใคร
async function cleanupBlock(uid, peer) {
  if (!(await db.doc(`users/${uid}/blocks/${peer}`).get()).exists) return;
  const batch = db.batch();
  for (const path of [`users/${uid}/following/${peer}`, `users/${peer}/followers/${uid}`, `users/${peer}/following/${uid}`, `users/${uid}/followers/${peer}`, `users/${uid}/follow_requests/${peer}`, `users/${peer}/follow_requests/${uid}`]) batch.delete(db.doc(path));
  await batch.commit();
}

// เก็บไฟล์หลักฐานคนละ object กับต้นฉบับ ผู้ใช้แก้ภาพเดิมทีหลังจะไม่เปลี่ยนหลักฐานตาม
async function copyEvidence(ref) {
  const event = {data:{after:await ref.get()},params:{caseKey:ref.id}};
  const data = event.data?.after.data();
  if (!data?.contentHash || data.evidenceReadyHash === data.contentHash) return;
  if ((await db.doc('app_config/security').get()).data()?.evidenceCopiesEnabled !== true) return;
  const paths = {};
  const bucket = getStorage().bucket();
  const prefix = data.groupId ? `group_media/${data.groupId}/${data.postId}/${data.ownerId}/` : `post_media/${data.ownerId}/${data.postId}/`;
  for (const [key, field] of [['media', 'mediaPath'], ['thumbnail', 'thumbnailPath']]) {
    const path = data.snapshot?.[field];
    if (typeof path !== 'string' || !path.startsWith(prefix)) continue;
    const destination = `moderation_evidence/${event.params.caseKey}/${data.contentHash}/${key}`;
    try {
      await bucket.file(path).copy(bucket.file(destination), { preconditionOpts: { ifGenerationMatch: 0 }, metadata: { cacheControl: 'private,no-store', metadata: { firebaseStorageDownloadTokens: randomUUID() } } });
    } catch (error) {
      if (error.code === 404) continue;
      if (error.code !== 412) throw error;
    }
    paths[key] = destination;
  }
  await db.runTransaction(async tx => {
    const fresh = await tx.get(event.data.after.ref);
    if (fresh.data()?.contentHash !== data.contentHash) return;
    tx.update(fresh.ref, { evidencePaths: paths, evidenceReadyHash: data.contentHash });
  });
 }

// ใช้ handler เดียวกันทั้ง scheduler และ integration test ไม่จำลองผลทำงานของ worker
export const processLegacyReports = () => scanWork(db,'legacy_reports','post_reports','createdAt',doc => ingestReportEvent({data:doc}));
export const processBlockChanges = () => scanWork(db,'block_cleanup','block_edges','createdAt',doc => cleanupBlock(doc.data().actorId,doc.data().targetId));
export const processEvidenceCopies = () => scanWork(db,'evidence_copies','moderation_cases','updatedAt',doc => copyEvidence(doc.ref));
export const legacyReportWorker = onSchedule(workerSchedule,processLegacyReports);
export const blockCleanupWorker = onSchedule(workerSchedule,processBlockChanges);
export const evidenceCopyWorker = onSchedule(workerSchedule,processEvidenceCopies);

// แชร์เก็บแค่รหัสต้นฉบับ ไม่คัดลอกไฟล์หรือข้อความลับไปแปะในที่ใหม่
export const sharePost = onCall(async request => {
  const uid = await member(request);
  const postId = id(request.data?.postId);
  const destination = request.data?.destination;
  const targetId = request.data?.targetId == null ? null : id(request.data.targetId);
  const requestId = id(request.data?.requestId);
  const caption = String(request.data?.caption ?? '').trim();
  if (caption.length > 1000 || !['feed', 'group', 'chat'].includes(destination)) fail('invalid-argument', 'ข้อมูลการแชร์ไม่ถูกต้อง');
  const original = await source(uid, postId, null);
  if (original.post.visibility !== 'public' || original.post.sharedPostId) fail('permission-denied', 'ตอนนี้แชร์ได้เฉพาะโพสต์ต้นฉบับสาธารณะใน Feed');
  const me = (await db.doc(`users/${uid}`).get()).data();
  let path = `posts/${requestId}`;
  let peer = null;
  if (destination === 'group') {
    if (!targetId || !(await db.doc(`groups/${targetId}/members/${uid}`).get()).exists) fail('permission-denied', 'ต้องเป็นสมาชิกกลุ่มก่อน');
    path = `groups/${targetId}/posts/${requestId}`;
  }
  if (destination === 'chat') {
    const room = targetId ? (await db.doc(`conversations/${targetId}`).get()).data() : null;
    if (!room?.participantIds?.includes(uid)) fail('permission-denied', 'ไม่ใช่สมาชิกแชท');
    peer = room.participantIds.find(value => value !== uid);
    if (!peer || await blocked(uid, peer) || await blocked(peer, original.ownerId)) fail('permission-denied', 'ผู้รับเปิดโพสต์นี้ไม่ได้');
    const recipient = await getAuth().getUser(peer);
    const recipientState = !recipient.emailVerified ? (await db.doc(`account_state/${peer}`).get()).data() : null;
    if (!recipient.emailVerified && !(recipientState?.verificationGraceUntil?.toMillis() > Date.now())) fail('permission-denied', 'ผู้รับยังไม่ได้ยืนยันอีเมล');
    path = `conversations/${targetId}/messages/${requestId}`;
  }
  return db.runTransaction(async tx => {
    const stateRef = db.doc(`account_state/${uid}`);
    const refs = [db.doc(path), stateRef, db.doc(`rate_limits/${uid}_share`), db.doc(original.path)];
    if (destination === 'group') refs.push(db.doc(`group_account_state/${targetId}_${uid}`), db.doc(`groups/${targetId}`), db.doc(`groups/${targetId}/members/${uid}`));
    if (destination === 'chat') refs.push(db.doc(`conversations/${targetId}`));
    const [exists, state, rate, fresh, groupState, group, membership] = await tx.getAll(...refs);
    if (exists.exists) return { id: requestId };
    if (!fresh.exists || fresh.data().visibility !== 'public' || fresh.data().isDeleting) fail('permission-denied', 'ต้นฉบับไม่พร้อมให้แชร์แล้ว');
    const now = Date.now();
    if (destination !== 'chat' && [state, groupState].some(value => value?.data()?.postingSuspendedUntil?.toMillis() > now)) fail('permission-denied', 'อยู่ระหว่างพักสิทธิ์โพสต์');
    if (destination === 'group' && (!membership?.exists || !group?.exists || group.data().isDeleting)) fail('permission-denied', 'กลุ่มไม่พร้อมรับโพสต์');
    // เช็กขอบบล็อกอีกครั้งใน transaction กันการบล็อกระหว่างเลือกผู้รับ
    const blockRefs = [db.doc(`users/${uid}/blocks/${original.ownerId}`), db.doc(`users/${original.ownerId}/blocks/${uid}`)];
    if (peer) blockRefs.push(db.doc(`users/${uid}/blocks/${peer}`), db.doc(`users/${peer}/blocks/${uid}`), db.doc(`users/${peer}/blocks/${original.ownerId}`), db.doc(`users/${original.ownerId}/blocks/${peer}`));
    if ((await tx.getAll(...blockRefs)).some(value => value.exists)) fail('permission-denied', 'แชร์ไม่ได้เพราะมีการบล็อกกัน');
    const next = reserveRate(rate.data(), now, 60000, 5);
    if (!next) fail('resource-exhausted', 'แชร์เร็วไป รอสักครู่แล้วลองใหม่');
    tx.set(db.doc(`rate_limits/${uid}_share`), next);
    const common = { content: caption, sharedPostId: postId, createdAt: stamp(), mediaType: 'none', tags: [] };
    if (destination === 'feed') tx.create(db.doc(path), { ...common, userId: uid, authorName: me?.displayName ?? 'สมาชิก', visibility: 'public', authorIsPrivate: me?.privacyTarget ?? me?.isPrivate ?? false });
    if (destination === 'group') tx.create(db.doc(path), { ...common, authorId: uid, authorName: me?.displayName ?? 'สมาชิก' });
    if (destination === 'chat') {
      tx.create(db.doc(path), { senderId: uid, type: 'post', text: caption, sharedPostId: postId, createdAt: stamp() });
      tx.update(db.doc(`conversations/${targetId}`), { lastMessageText: 'แชร์โพสต์ให้คุณ', lastMessageType: 'post', lastMessageSenderId: uid, lastMessageId: requestId, lastMessageAt: stamp(), updatedAt: stamp(), [`unreadCounts.${peer}`]: FieldValue.increment(1), [`hiddenFor.${uid}`]: false, [`hiddenFor.${peer}`]: false });
    }
    return { id: requestId };
  });
});
