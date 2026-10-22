// Exercises the security boundaries found by the system audit.
import { createUser, createProfile, follow, commit, get, write, s, n, b, m, a,
  documentName, allowed, denied, assert, adminToken, storage } from './emulator_test_support.mjs';

const owner = await createUser(), member = await createUser(), outsider = await createUser();
for (const user of [owner, member, outsider]) await createProfile(user);
const suffix = Date.now();
const post = `posts/audit_${suffix}`;
const postFields = {
  userId: s(owner.uid), authorName: s('Owner'), content: s('Audit post'), tags: a([s('linko')]),
  visibility: s('public'), authorIsPrivate: b(false), mediaType: s('none'),
};
denied(await commit(owner.token, [write(post, { ...postFields, tags: a([n(123)]) }, {
  timestamps: ['createdAt', 'updatedAt'],
})]), 'Reject non-string tags');
denied(await commit(owner.token, [write(post, { ...postFields, content: s('') }, {
  timestamps: ['createdAt', 'updatedAt'],
})]), 'Reject empty text-only post');
allowed(await commit(owner.token, [write(post, postFields, { timestamps: ['createdAt', 'updatedAt'] })]), 'Valid post');
for (const reaction of ['like', 'love', 'haha', 'wow', 'sad', 'angry', 'dislike']) {
  allowed(await commit(member.token, [write(`${post}/reactions/${member.uid}`, {
    uid: s(member.uid), reaction: s(reaction),
  }, { timestamps: ['updatedAt'] })]), `Reaction ${reaction}`);
}
denied(await commit(member.token, [write(`${post}/reactions/${member.uid}`, {
  uid: s(member.uid), reaction: s('invalid'),
}, { timestamps: ['updatedAt'] })]), 'Reject unknown reaction');
const commentId = `comment_${suffix}`;
allowed(await commit(member.token, [write(`${post}/comments/${commentId}`, {
  authorId: s(member.uid), authorName: s('Member'), content: s('Comment'),
}, { timestamps: ['createdAt'] })]), 'Comment');
const followers = await Promise.all(Array.from({ length: 25 }, () => createUser()));
for (const user of followers) await follow(user, owner);
const deliveries = await Promise.all(followers.map(user => commit(member.token, [write(
  `notifications/comment_${commentId}_${user.uid}`, {
    recipientId: s(user.uid), actorId: s(member.uid), actorName: s('Member'), type: s('comment'),
    body: s('Comment'), postId: s(post.split('/')[1]), commentId: s(commentId), isRead: b(false),
  }, { timestamps: ['createdAt'] },
)])));
for (const delivery of deliveries) allowed(delivery, 'Independent follower notification');
denied(await commit(member.token, [write(`notifications/comment_${commentId}_${outsider.uid}`, {
  recipientId: s(outsider.uid), actorId: s(member.uid), actorName: s('Member'), type: s('comment'),
  body: s('Comment'), postId: s(post.split('/')[1]), commentId: s(commentId), isRead: b(false),
}, { timestamps: ['createdAt'] })]), 'Non-follower must not receive a comment notification');
allowed(await commit(owner.token, [write(post, { isDeleting: b(true) }, {
  mask: ['isDeleting'], timestamps: ['updatedAt'],
})]), 'Begin resumable post deletion');
denied(await commit(owner.token, [write(post, { content: s('Changed during deletion') }, {
  mask: ['content'], timestamps: ['updatedAt', 'editedAt'],
})]), 'Deleting post rejects edits');
denied(await commit(member.token, [write(`${post}/comments/late`, {
  authorId: s(member.uid), authorName: s('Member'), content: s('Too late'),
}, { timestamps: ['createdAt'] })]), 'Closed post rejects new comments');
allowed(await commit(owner.token, [
  { delete: documentName(`${post}/comments/${commentId}`) },
  { delete: documentName(`${post}/reactions/${member.uid}`) },
]), 'Post owner can clean other users child documents');
allowed(await commit(owner.token, [{ delete: documentName(post) }]), 'Delete cleaned post');
console.log('PASS post schema, 7 reactions, 25 follower notifications and owner child cleanup');

const mediaPost = `posts/media_${suffix}`;
allowed(await commit(owner.token, [write(mediaPost, { ...postFields, content: s(''),
  mediaType: s('image'), mediaPath: s(`post_media/${owner.uid}/media_${suffix}/photo.png`),
}, { timestamps: ['createdAt', 'updatedAt'] })]), 'Create media-only post');
allowed(await commit(owner.token, [write(mediaPost, { tags: a([s('updated')]) }, {
  mask: ['tags'], timestamps: ['updatedAt', 'editedAt'],
})]), 'Edit media-only post while keeping its existing attachment');
denied(await commit(owner.token, [write(mediaPost, { mediaType: s('none') }, {
  mask: ['mediaType', 'mediaPath'], timestamps: ['updatedAt', 'editedAt'],
})]), 'Removing the last attachment cannot create an empty post');
console.log('PASS existing-media editing and empty post prevention');

const group = `groups/audit_${suffix}`;
function membership(user) {
  return write(`${group}/members/${user.uid}`, { uid: s(user.uid), displayName: s('Member') }, { timestamps: ['createdAt'] });
}
allowed(await commit(owner.token, [
  write(group, { name: s('Audit'), description: s(''), ownerId: s(owner.uid), visibility: s('public'), memberCount: n(1) }, { timestamps: ['createdAt', 'updatedAt'] }),
  membership(owner),
]), 'Create group');
allowed(await commit(member.token, [write(group, { memberCount: n(2) }, { mask: ['memberCount'] }), membership(member)]), 'Join group');
const path = `group_media/${group.split('/')[1]}/post/${member.uid}/test.png`;
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6wSIAAAAASUVORK5CYII=', 'base64');
allowed(await storage(member.token, path, { method: 'POST', bytes: png }), 'Member upload');
allowed(await commit(member.token, [write(`${group}/posts/post`, {
  authorId: s(member.uid), authorName: s('Member'), content: s(''), mediaType: s('image'), mediaPath: s(path),
}, { timestamps: ['createdAt'] })]), 'Member media post');
denied(await storage(outsider.token, path, { method: 'DELETE' }), 'Outsider cannot delete group media');
allowed(await commit(owner.token, [write(group, { isDeleting: b(true) }, { mask: ['isDeleting'], timestamps: ['updatedAt'] })]), 'Begin group cleanup');
denied(await commit(owner.token, [write(group, { name: s('Changed during deletion') }, {
  mask: ['name'], timestamps: ['updatedAt'],
})]), 'Deleting group rejects metadata edits');
denied(await storage(owner.token, `group_images/${group.split('/')[1]}/${owner.uid}/late.png`, {
  method: 'POST', bytes: png,
}), 'Deleting group rejects new avatars');
denied(await commit(outsider.token, [write(group, { memberCount: n(3) }, { mask: ['memberCount'] }), membership(outsider)]), 'Deleting group rejects joins');
denied(await storage(member.token, path, { method: 'POST', bytes: png }), 'Deleting group rejects uploads');
allowed(await storage(owner.token, path, { method: 'DELETE' }), 'Owner deletes another member media during cleanup');
console.log('PASS group media owner cleanup and deletion write barrier');

const privateGroup = `groups/admin_${suffix}`;
const admin = await createUser();
const token = adminToken(admin);
allowed(await commit(owner.token, [
  write(privateGroup, { name: s('Private'), description: s(''), ownerId: s(owner.uid), visibility: s('private'), memberCount: n(1) }, { timestamps: ['createdAt', 'updatedAt'] }),
  write(`${privateGroup}/members/${owner.uid}`, { uid: s(owner.uid), displayName: s('Owner') }, { timestamps: ['createdAt'] }),
]), 'Private group');
allowed(await commit(member.token, [write(`${privateGroup}/join_requests/${member.uid}`, {
  uid: s(member.uid), displayName: s('Member'),
}, { timestamps: ['createdAt'] })]), 'Join request');
assert((await get(token, `${privateGroup}/members/${member.uid}`)).status === 404, 'Admin can read missing membership before approval');
allowed(await commit(token, [
  write(privateGroup, { memberCount: n(2) }, { mask: ['memberCount'] }),
  write(`${privateGroup}/members/${member.uid}`, { uid: s(member.uid), displayName: s('Member') }, { timestamps: ['createdAt'] }),
  { delete: documentName(`${privateGroup}/join_requests/${member.uid}`) },
]), 'Non-member admin approves private join request');
console.log('PASS non-member admin private group approval');

const recoveryUser = await createUser();
denied(await commit(recoveryUser.token, [write(`users/${recoveryUser.uid}`, { displayName: a([]) })]), 'Reject malformed profile creation');
allowed(await commit('owner', [write(`users/${recoveryUser.uid}`, { displayName: s('Legacy') })]), 'Seed a legacy profile in emulator');
allowed(await commit(recoveryUser.token, [write(`users/${recoveryUser.uid}`, {
  uid: s(recoveryUser.uid), displayName: s('Legacy'), displayNameLower: s('legacy'), bio: s(''), isPrivate: b(false),
}, { mask: ['uid', 'displayName', 'displayNameLower', 'bio', 'isPrivate'], timestamps: ['createdAt', 'updatedAt'] })]), 'Repair incomplete legacy profile');
console.log('PASS strict profile creation and owner legacy recovery');
