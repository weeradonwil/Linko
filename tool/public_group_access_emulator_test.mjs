// ทดสอบอ่านกลุ่มสาธารณะก่อนเข้าร่วม และยืนยันว่ากลุ่มส่วนตัว/สิทธิ์เขียนไม่รั่ว
import { createRequire } from 'node:module';
import { syncGroupPostVisibility } from '../functions/index.mjs';
import { createUser, createProfile, commit, get, request, write, s, n, b,
  storage, allowed, denied, assert, documentName, projectId } from './emulator_test_support.mjs';
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { getFirestore } = require('firebase-admin/firestore');
const db = getFirestore();
let checks = 0;
const yes = (result, message) => { allowed(result, message); checks++; };
const no = (result, message) => { denied(result, message); checks++; };
const owner = await createUser(), reader = await createUser(), outsider = await createUser();
for (const user of [owner, reader, outsider]) await createProfile(user);
const suffix = Date.now();
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6wSIAAAAASUVORK5CYII=', 'base64');
const membership = (group, user) => write(`${group}/members/${user.uid}`, {
  uid: s(user.uid), displayName: s('Reader'),
}, { timestamps: ['createdAt'] });

for (const visibility of ['public', 'private']) {
  const groupId = `read_${visibility}_${suffix}`, group = `groups/${groupId}`;
  const post = `${group}/posts/image`;
  const media = `group_media/${groupId}/image/${owner.uid}/photo.png`;
  const thumb = `group_media/${groupId}/image/${owner.uid}/thumb.png`;
  yes(await commit(owner.token, [write(group, {
    name: s('Access test'), description: s(''), visibility: s(visibility), ownerId: s(owner.uid), memberCount: n(1),
  }, { timestamps: ['createdAt', 'updatedAt'] }), membership(group, owner)]), `Create ${visibility} group`);
  yes(await storage(owner.token, media, { method: 'POST', bytes: png }), 'Upload photo');
  no(await storage(outsider.token, media), 'Unpublished file cannot be read by outsider');
  yes(await commit(owner.token, [write(post, {
    authorId: s(owner.uid), authorName: s('Owner'), content: s('Public audience follows group'),
    mediaType: s('image'), mediaPath: s(media), groupVisibility: s(visibility),
  }, { timestamps: ['createdAt'] })]), 'Create image post with validated group visibility');
  yes(await commit(owner.token, [write(`${post}/comments/comment`, {
    authorId: s(owner.uid), authorName: s('Owner'), content: s('Existing comment'),
  }, { timestamps: ['createdAt'] })]), 'Create comment');
  yes(await commit(owner.token, [write(`${post}/reactions/${owner.uid}`, {
    uid: s(owner.uid), reaction: s('like'),
  }, { timestamps: ['updatedAt'] })]), 'Create reaction');
  const query = token => request(`/${group}:runQuery`, { token, method: 'POST', body: {
    structuredQuery: { from: [{ collectionId: 'posts' }], orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }], limit: 30 },
  } });
  for (const user of [reader, outsider]) {
    const expectRead = visibility === 'public' ? yes : no;
    expectRead(await get(user.token, post), `${visibility} nonmember reads post`);
    expectRead(await query(user.token), `${visibility} nonmember queries posts`);
    expectRead(await get(user.token, `${post}/comments/comment`), `${visibility} nonmember reads comment`);
    expectRead(await get(user.token, `${post}/reactions/${owner.uid}`), `${visibility} nonmember reads reaction`);
    expectRead(await storage(user.token, media, { download: true }), `${visibility} nonmember downloads image`);
  }
  no(await get(null, post), 'Signed-out viewer cannot read posts');
  no(await query(null), 'Signed-out viewer cannot query posts');
  no(await commit(outsider.token, [write(`${group}/posts/outside`, {
    authorId: s(outsider.uid), authorName: s('Outsider'), content: s('Cannot post'), mediaType: s('none'), groupVisibility: s(visibility),
  }, { timestamps: ['createdAt'] })]), 'Nonmember cannot publish');
  no(await commit(outsider.token, [write(`${post}/comments/outside`, {
    authorId: s(outsider.uid), authorName: s('Outsider'), content: s('Cannot comment'),
  }, { timestamps: ['createdAt'] })]), 'Nonmember cannot comment');
  no(await commit(outsider.token, [write(`${post}/reactions/${outsider.uid}`, {
    uid: s(outsider.uid), reaction: s('love'),
  }, { timestamps: ['updatedAt'] })]), 'Nonmember cannot react');
  no(await storage(outsider.token, `group_media/${groupId}/outside/${outsider.uid}/photo.png`, { method: 'POST', bytes: png }), 'Nonmember cannot upload');
  no(await commit(owner.token, [write(`${group}/posts/forged`, {
    authorId: s(owner.uid), authorName: s('Owner'), content: s('Wrong snapshot'), mediaType: s('none'),
    groupVisibility: s(visibility === 'public' ? 'private' : 'public'),
  }, { timestamps: ['createdAt'] })]), 'Reject visibility snapshot that differs from real group');

  if (visibility === 'private') {
    yes(await commit(reader.token, [write(`${group}/join_requests/${reader.uid}`, {
      uid: s(reader.uid), displayName: s('Reader'),
    }, { timestamps: ['createdAt'] })]), 'Request private membership');
    no(await get(reader.token, post), 'Pending requester cannot read');
    no(await storage(reader.token, media), 'Pending requester cannot read media');
    yes(await commit(owner.token, [write(group, { memberCount: n(2) }, { mask: ['memberCount'] }),
      membership(group, reader), { delete: documentName(`${group}/join_requests/${reader.uid}`) }]), 'Approve private membership');
  } else {
    yes(await commit(reader.token, [write(group, { memberCount: n(2) }, { mask: ['memberCount'] }), membership(group, reader)]), 'Join public group');
  }
  yes(await get(reader.token, post), 'Member reads post');
  yes(await query(reader.token), 'Member queries posts');
  yes(await storage(reader.token, media, { download: true }), 'Member downloads image');
  yes(await commit(reader.token, [write(`${post}/comments/member`, {
    authorId: s(reader.uid), authorName: s('Reader'), content: s('Member comment'),
  }, { timestamps: ['createdAt'] })]), 'Member comments');
  yes(await commit(reader.token, [write(`${post}/reactions/${reader.uid}`, {
    uid: s(reader.uid), reaction: s('love'),
  }, { timestamps: ['updatedAt'] })]), 'Member reacts');

  // รูปตัวอย่างวิดีโอและวิดีโอใช้สิทธิ์เดียวกับรูปจริง
  yes(await storage(owner.token, thumb, { method: 'POST', bytes: png }), 'Upload thumbnail');
  const video = `group_media/${groupId}/image/${owner.uid}/video.mp4`;
  yes(await storage(owner.token, video, { method: 'POST', bytes: Buffer.from('fixture-video'), contentType: 'video/mp4' }), 'Upload video fixture');
  yes(await commit(owner.token, [write(post, { mediaType: s('video'), mediaPath: s(video), thumbnailPath: s(thumb) }, {
    mask: ['mediaType', 'mediaPath', 'thumbnailPath'], timestamps: ['updatedAt', 'editedAt'],
  })]), 'Set video and thumbnail');
  const nonmemberRead = visibility === 'public' ? yes : no;
  nonmemberRead(await storage(outsider.token, thumb, { download: true }), 'Nonmember thumbnail access follows group');
  nonmemberRead(await storage(outsider.token, video, { download: true }), 'Nonmember video access follows group');

  // แอปรุ่นก่อนยังสร้างโพสต์ได้ worker เติม field โดยไม่เปลี่ยนเวลาเดิม
  const legacyPost = `${group}/posts/legacy`;
  const legacyMedia = `group_media/${groupId}/legacy/${owner.uid}/photo.png`;
  yes(await storage(owner.token, legacyMedia, { method: 'POST', bytes: png }), 'Legacy upload');
  yes(await commit(owner.token, [write(legacyPost, {
    authorId: s(owner.uid), authorName: s('Owner'), content: s('Legacy'), mediaType: s('image'), mediaPath: s(legacyMedia),
  }, { timestamps: ['createdAt'] })]), 'Legacy clients can still create posts');
  const before = (await db.doc(legacyPost).get()).data();
  await syncGroupPostVisibility(db.doc(legacyPost));
  const after = (await db.doc(legacyPost).get()).data();
  assert(after.groupVisibility === visibility && after.createdAt.isEqual(before.createdAt) && !after.updatedAt, 'Worker only fills group visibility'); checks++;
  await syncGroupPostVisibility(db.doc(legacyPost));
  nonmemberRead(await storage(outsider.token, legacyMedia, { download: true }), 'Legacy media reads after worker backfill');
  yes(await storage(reader.token, legacyMedia, { download: true }), 'Legacy member access remains available');

  // หลังออกจากกลุ่ม สาธารณะยังอ่านได้ แต่ส่วนตัวต้องถูกเพิกถอนทันที
  yes(await commit(reader.token, [write(group, { memberCount: n(1) }, { mask: ['memberCount'] }),
    { delete: documentName(`${group}/members/${reader.uid}`) }]), 'Leave group');
  nonmemberRead(await get(reader.token, post), 'Former member post access follows group');
  nonmemberRead(await storage(reader.token, media, { download: true }), 'Former member media access follows group');
  no(await commit(reader.token, [write(`${post}/comments/after_leave`, {
    authorId: s(reader.uid), authorName: s('Reader'), content: s('No longer member'),
  }, { timestamps: ['createdAt'] })]), 'Former member cannot comment');
  if (visibility === 'public') {
    // ปิดผ่าน Admin SDK จำลองการดูแลระบบ: snapshot สาธารณะเก่าต้องเปิดกลุ่มส่วนตัวไม่ได้
    await db.doc(group).update({ visibility: 'private' });
    no(await get(outsider.token, post), 'Live private group blocks stale public post snapshot');
    no(await storage(outsider.token, media), 'Live private group blocks stale public media snapshot');
  }
  await db.doc(post).delete();
  no(await storage(owner.token, media), 'Missing parent post blocks orphan media even for owner');
}
console.log(`PASS public group access: ${checks} checks, public/nonmember, private/approval/revocation, media, write guards and legacy worker (${projectId})`);
