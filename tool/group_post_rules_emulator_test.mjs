// ตรวจวงจรโพสต์กลุ่มจริง รวมสิทธิ์เจ้าของ/สมาชิก/คนนอก/แอดมินและการล้างข้อมูลย่อย
import { createUser, createProfile, commit, get, write, s, n, b, a,
  storage, adminToken, allowed, denied, assert } from './emulator_test_support.mjs';

const owner = await createUser(), author = await createUser(), reader = await createUser(), outsider = await createUser();
for (const user of [owner, author, reader, outsider]) await createProfile(user);
const groupId = 'post_parity_' + Date.now(), group = `groups/${groupId}`, postId = 'post';
const post = `${group}/posts/${postId}`;
const membership = user => write(`${group}/members/${user.uid}`, { uid: s(user.uid), displayName: s('Member') }, { timestamps: ['createdAt'] });
allowed(await commit(owner.token, [write(group, {
  name: s('Post parity'), description: s(''), visibility: s('public'), ownerId: s(owner.uid), memberCount: n(1),
}, { timestamps: ['createdAt', 'updatedAt'] }), membership(owner)]), 'Create group');
for (const [user, count] of [[author, 2], [reader, 3]]) {
  allowed(await commit(user.token, [write(group, { memberCount: n(count) }, { mask: ['memberCount'] }), membership(user)]), 'Join group');
}
allowed(await commit(author.token, [write(post, {
  authorId: s(author.uid), authorName: s('Author'), content: s('Original'), mediaType: s('none'), tags: a([s('linko')]),
}, { timestamps: ['createdAt'] })]), 'Create tagged group post');
const edit = (content, extra = {}) => write(post, { content: s(content), ...extra }, {
  mask: ['content', ...Object.keys(extra)], timestamps: ['updatedAt', 'editedAt'],
});
allowed(await commit(author.token, [edit('Edited', { tags: a([s('updated')]) })]), 'Author edits content and tags');
denied(await commit(reader.token, [edit('Stolen')]), 'Member cannot edit another author');
denied(await commit(author.token, [edit('Moved owner', { authorId: s(reader.uid) })]), 'Author cannot transfer ownership');
denied(await commit(author.token, [edit('')]), 'Text-only post cannot become empty');
denied(await get(outsider.token, post), 'Outsider cannot read group post');

const comment = (id, user, text = 'Comment') => write(`${post}/comments/${id}`, {
  authorId: s(user.uid), authorName: s('Member'), content: s(text),
}, { timestamps: ['createdAt'] });
allowed(await commit(reader.token, [comment('first', reader)]), 'Member comments');
const notice = (id, recipient = author.uid) => write(`notifications/${id}`, {
  recipientId: s(recipient), actorId: s(reader.uid), actorName: s('Member'), type: s('comment'),
  body: s('Comment'), groupId: s(groupId), postId: s(postId), commentId: s('first'), isRead: b(false),
}, { timestamps: ['createdAt'] });
allowed(await commit(reader.token, [notice(`group_comment_${groupId}_${postId}_first`)]), 'Comment notifies group post author');
denied(await commit(reader.token, [notice('forged_group_notice', owner.uid)]), 'Group comment cannot notify an unrelated recipient');
denied(await commit(outsider.token, [comment('outside', outsider)]), 'Outsider cannot comment');
denied(await commit(reader.token, [comment('too_long', reader, 'x'.repeat(1001))]), 'Reject long comment');
denied(await get(outsider.token, `${post}/comments/first`), 'Outsider cannot read comment');
allowed(await commit(author.token, [{ delete: `projects/${process.env.GCLOUD_PROJECT ?? 'demo-linko'}/databases/(default)/documents/${post}/comments/first` }]), 'Post author moderates comments');
allowed(await commit(reader.token, [comment('cleanup', reader)]), 'Comment for cleanup');
for (const reaction of ['like', 'love', 'haha', 'wow', 'sad', 'angry', 'dislike']) {
  allowed(await commit(reader.token, [write(`${post}/reactions/${reader.uid}`, {
    uid: s(reader.uid), reaction: s(reaction),
  }, { timestamps: ['updatedAt'] })]), 'Group reaction ' + reaction);
}
allowed(await commit(reader.token, [
  write(`${post}/reactions/${reader.uid}`, { uid: s(reader.uid), reaction: s('like') }, { timestamps: ['updatedAt'] }),
  write(`notifications/group_like_${groupId}`, {
    recipientId: s(author.uid), actorId: s(reader.uid), actorName: s('Member'), type: s('like'), body: s(''),
    groupId: s(groupId), postId: s(postId), isRead: b(false),
  }, { timestamps: ['createdAt'] }),
]), 'Group like and author notification commit atomically');
denied(await commit(outsider.token, [write(`${post}/reactions/${outsider.uid}`, {
  uid: s(outsider.uid), reaction: s('like'),
}, { timestamps: ['updatedAt'] })]), 'Outsider cannot react');

const report = (user, ownerId = author.uid) => write(`post_reports/group_${groupId}_${postId}_${user.uid}`, {
  groupId: s(groupId), postId: s(postId), postOwnerId: s(ownerId), reporterUid: s(user.uid),
  reason: s('ไม่เหมาะสม'), details: s('Review this group post'), status: s('open'),
}, { timestamps: ['createdAt'] });
allowed(await commit(reader.token, [report(reader)]), 'Member reports group post');
denied(await commit(reader.token, [report(reader)]), 'Duplicate report is denied');
denied(await commit(outsider.token, [report(outsider)]), 'Outsider cannot forge group report');
denied(await commit(author.token, [report(author)]), 'Cannot report own group post');
denied(await commit(owner.token, [report(owner, reader.uid)]), 'Report must match real author');
const reportPath = `post_reports/group_${groupId}_${postId}_${reader.uid}`;
denied(await get(reader.token, reportPath), 'Report queue is private to admin');
allowed(await get(adminToken(outsider), reportPath), 'Admin can review group report');

const media = `group_media/${groupId}/${postId}/${author.uid}/image.png`;
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6wSIAAAAASUVORK5CYII=', 'base64');
allowed(await storage(author.token, media, { method: 'POST', bytes: png }), 'Author uploads group media');
allowed(await commit(author.token, [edit('With media', { mediaType: s('image'), mediaPath: s(media) })]), 'Author replaces media');
allowed(await storage(reader.token, media), 'Member reads media');
allowed(await commit(reader.token, [
  write(group, { memberCount: n(2) }, { mask: ['memberCount'] }),
  { delete: `projects/${process.env.GCLOUD_PROJECT ?? 'demo-linko'}/databases/(default)/documents/${group}/members/${reader.uid}` },
]), 'Member leaves group');
denied(await storage(reader.token, media), 'Former member cannot read media again');
denied(await get(reader.token, `${post}/comments/cleanup`), 'Former member loses comment access');
denied(await commit(reader.token, [edit('After leaving')]), 'Former member cannot edit');
denied(await commit(owner.token, [edit('Owner cannot rewrite member text')]), 'Group owner moderates by deletion, not impersonation');
allowed(await commit(author.token, [write(post, { isDeleting: b(true) }, {
  mask: ['isDeleting'], timestamps: ['updatedAt'],
})]), 'Begin resumable post deletion');
denied(await commit(author.token, [comment('late', author)]), 'Deleting post rejects new comments');
denied(await commit(author.token, [edit('Too late')]), 'Deleting post rejects edits');
denied(await commit(author.token, [write(`${post}/reactions/${author.uid}`, {
  uid: s(author.uid), reaction: s('like'),
}, { timestamps: ['updatedAt'] })]), 'Deleting post rejects reactions');
const admin = adminToken(outsider);
const document = path => `projects/${process.env.GCLOUD_PROJECT ?? 'demo-linko'}/databases/(default)/documents/${path}`;
allowed(await commit(author.token, [{ delete: document(`${post}/reactions/${reader.uid}`) }]), 'Post author cleans another member reaction during deletion');
allowed(await commit(admin, [
  { delete: document(`${post}/comments/cleanup`) },
]), 'Admin cleans comments');
allowed(await storage(admin, media, { method: 'DELETE' }), 'Admin cleans group media');
allowed(await commit(admin, [{ delete: document(post) }]), 'Admin removes reported group post');
assert((await get(owner.token, post)).status === 404, 'Post must be gone');
denied(await commit(author.token, [comment('orphan', author)]), 'Missing post rejects orphan comment');
console.log('PASS group post parity: edits, 7 reactions, comments, reports, media revocation, moderation and deletion barrier');
