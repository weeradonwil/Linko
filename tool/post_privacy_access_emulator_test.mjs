// ทดสอบสิทธิ์จริงผ่าน Rules ของ Firestore/Storage เฉพาะ Firebase Emulator แบบ demo-*
import { createUser, createProfile, follow, commit, get, request, write, s, b, a,
  storage, documentName, allowed, denied, assert } from './emulator_test_support.mjs';

const [owner, follower, outsider, pending] = await Promise.all(Array.from({ length: 4 }, () => createUser()));
for (const user of [owner, follower, outsider, pending]) await createProfile(user);
await follow(follower, owner);
const suffix = Date.now();
const posts = [];
for (const visibility of ['public', 'private', 'followers']) {
  for (const mediaType of ['image', 'video']) {
    const id = `access_${suffix}_${visibility}_${mediaType}`;
    const path = `post_media/${owner.uid}/${id}/media.${mediaType === 'image' ? 'png' : 'mp4'}`;
    allowed(await commit(owner.token, [write(`posts/${id}`, {
      userId: s(owner.uid), authorName: s('Owner'), content: s('Audience matrix'),
      tags: a([]), visibility: s(visibility), authorIsPrivate: b(false),
      mediaType: s(mediaType), mediaPath: s(path),
    }, { timestamps: ['createdAt', 'updatedAt'] })]), 'Create audience fixture');
    allowed(await storage(owner.token, path, { method: 'POST', bytes: Buffer.from('rules-media-fixture'),
      contentType: mediaType === 'image' ? 'image/png' : 'video/mp4' }), 'Upload Rules fixture');
    posts.push({ id, path, visibility });
  }
}
let checks = 0;
async function access(user, post, expected, label) {
  const verify = expected ? allowed : denied;
  verify(await get(user.token, `posts/${post.id}`), `${label}: document`);
  const media = await storage(user.token, post.path, { download: true });
  verify(media, `${label}: media`);
  if (expected) assert(media.body === 'rules-media-fixture', `${label}: media bytes must match`);
  checks += 2;
}
const ordinary = posts.find(post => post.visibility === 'public');
for (const isPrivate of [false, true]) {
  if (isPrivate) {
    allowed(await commit(owner.token, [write(`users/${owner.uid}`, { isPrivate: b(true) }, { mask: ['isPrivate'] })]), 'Make account private');
    allowed(await commit(owner.token, posts.map(post => write(`posts/${post.id}`, { authorIsPrivate: b(true) }, { mask: ['authorIsPrivate'] }))), 'Update privacy snapshots');
    allowed(await commit(pending.token, [write(`users/${owner.uid}/follow_requests/${pending.uid}`, {
      uid: s(pending.uid),
    }, { timestamps: ['createdAt'] })]), 'Request follow without approval');
  }
  for (const post of posts) {
    await access(owner, post, true, 'Owner always reads own posts');
    await access(follower, post, post.visibility !== 'private', 'Approved follower audience');
    await access(outsider, post, !isPrivate && post.visibility === 'public', 'Outsider audience');
    await access(pending, post, !isPrivate && post.visibility === 'public', 'Pending request grants no access');
  }
}
// อนุมัติคำขอแล้วอ่านได้ทันที โดยไม่แก้ visibility ของโพสต์
allowed(await commit(owner.token, [
  write(`users/${owner.uid}/followers/${pending.uid}`, { uid: s(pending.uid) }, { timestamps: ['createdAt'] }),
  write(`users/${pending.uid}/following/${owner.uid}`, { uid: s(owner.uid) }, { timestamps: ['createdAt'] }),
  { delete: documentName(`users/${owner.uid}/follow_requests/${pending.uid}`) },
]), 'Approve pending follower');
await access(pending, ordinary, true, 'Newly approved follower reads existing ordinary post');
await access(pending, posts.find(post => post.visibility === 'private'), false, 'Approval never reveals only-me post');

const query = { from: [{ collectionId: 'posts' }], where: { compositeFilter: { op: 'AND', filters: [
  { fieldFilter: { field: { fieldPath: 'userId' }, op: 'EQUAL', value: s(owner.uid) } },
  { fieldFilter: { field: { fieldPath: 'visibility' }, op: 'IN', value: a([s('public'), s('followers')]) } },
] } }, orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }], limit: 30 };
const result = await request(':runQuery', { token: follower.token, method: 'POST', body: { structuredQuery: query } });
allowed(result, 'Profile query for approved follower');
assert(result.body.filter(item => item.document).length === 4, 'Profile exposes both ordinary audiences but never only-me posts');
denied(await request(':runQuery', { token: outsider.token, method: 'POST', body: { structuredQuery: query } }), 'Outsider cannot run follower profile query');
const unfiltered = { ...query, where: query.where.compositeFilter.filters[0] };
denied(await request(':runQuery', { token: follower.token, method: 'POST', body: { structuredQuery: unfiltered } }), 'Follower cannot fetch only-me posts with an unfiltered query');
checks += 3;

// ยกเลิกสิทธิ์ฝั่งเจ้าของ แม้ following เก่ายังค้างอยู่ ต้องอ่านโพสต์และไฟล์ไม่ได้
allowed(await commit(owner.token, [{ delete: documentName(`users/${owner.uid}/followers/${follower.uid}`) }]), 'Revoke follower access');
await access(follower, ordinary, false, 'Revoked follower loses document and media access');
denied(await request(':runQuery', { token: follower.token, method: 'POST', body: { structuredQuery: query } }), 'Revoked follower loses query access');
checks++;
// เปิดบัญชีอีกครั้งยังคงซ่อนโพสต์เฉพาะฉัน
allowed(await commit(owner.token, [write(`users/${owner.uid}`, { isPrivate: b(false) }, { mask: ['isPrivate'] })]), 'Open account');
allowed(await commit(owner.token, posts.map(post => write(`posts/${post.id}`, { authorIsPrivate: b(false) }, { mask: ['authorIsPrivate'] }))), 'Restore public snapshots');
for (const post of posts) await access(outsider, post, post.visibility === 'public', 'Public transition preserves post audience');
console.log(`PASS post privacy: ${checks} document/media/query checks, both account modes, approval, revocation and only-me protection`);
