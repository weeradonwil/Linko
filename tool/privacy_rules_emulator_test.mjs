import { createUser, createProfile, follow, commit, get, request, write, s, b, a,
  allowed, denied, assert } from './emulator_test_support.mjs';

const owner = await createUser(), follower = await createUser(), outsider = await createUser();
await createProfile(owner);
await follow(follower, owner);
const prefix = 'privacy_' + Date.now() + '_';
const fields = {
  userId: s(owner.uid), authorName: s('Owner'), content: s('Privacy regression'),
  tags: a([]), visibility: s('public'), authorIsPrivate: b(false), mediaType: s('none'),
};
// More posts than the former 499-post limit, including one explicitly private post.
// Keep the batch below the Rules expression budget after each post also checks its owner's privacy.
for (let start = 0; start < 501; start += 50) {
  const writes = [];
  for (let i = start; i < Math.min(start + 50, 501); i++) {
    writes.push(write('posts/' + prefix + String(i).padStart(4, '0'), {
      ...fields, ...(i === 0 ? { visibility: s('private') } : {}),
    }, { timestamps: ['createdAt', 'updatedAt'] }));
  }
  allowed(await commit(owner.token, writes), 'Seed privacy posts');
}
const publicFeed = await request(':runQuery', {
  token: follower.token,
  method: 'POST',
  body: { structuredQuery: {
    from: [{ collectionId: 'posts' }],
    where: { compositeFilter: { op: 'AND', filters: [
      { fieldFilter: { field: { fieldPath: 'visibility' }, op: 'EQUAL', value: s('public') } },
      { fieldFilter: { field: { fieldPath: 'authorIsPrivate' }, op: 'EQUAL', value: b(false) } },
    ] } },
    orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
    limit: 30,
  } },
});
allowed(publicFeed, 'Chronological public feed query');
assert(publicFeed.body.some(item => item.document), 'Public feed query should return posts');
const userPath = 'users/' + owner.uid;
allowed(await commit(owner.token, [write(userPath, { privacyMigrationTarget: b(true) }, { mask: ['privacyMigrationTarget'] })]), 'Start private transition');
denied(await get(follower.token, 'posts/' + prefix + '0001'), 'Private transition hides stale public snapshots from followers');
denied(await get(outsider.token, 'posts/' + prefix + '0001'), 'Private transition hides stale public snapshots from everyone else');
denied(await commit(outsider.token, [write(`users/${owner.uid}/followers/${outsider.uid}`, {
  uid: s(outsider.uid),
}, { timestamps: ['createdAt'] })]), 'Pending private profile cannot be followed without approval');
denied(await commit(owner.token, [write('posts/' + prefix + 'new_bad', fields, {
  timestamps: ['createdAt', 'updatedAt'],
})]), 'New public writes cannot race the private transition');

async function migrate(isPrivate) {
  let cursor;
  let count = 0;
  while (true) {
    const result = await request(':runQuery', {
      token: owner.token, method: 'POST', body: { structuredQuery: {
        from: [{ collectionId: 'posts' }],
        where: { fieldFilter: { field: { fieldPath: 'userId' }, op: 'EQUAL', value: s(owner.uid) } },
        orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }], limit: 200,
        ...(cursor ? { startAt: { values: [{ referenceValue: cursor }], before: false } } : {}),
      } },
    });
    allowed(result, 'Read privacy page');
    const docs = result.body.filter(item => item.document).map(item => item.document);
    if (!docs.length) break;
    for (let start = 0; start < docs.length; start += 40) {
      const page = docs.slice(start, start + 40);
      allowed(await commit(owner.token, page.map(doc => write(doc.name.split('/documents/')[1], {
        authorIsPrivate: b(isPrivate),
      }, { mask: ['authorIsPrivate'] }))), 'Migrate page');
      count += page.length;
    }
    if (count === 200 && isPrivate) {
      const pending = await get(owner.token, userPath);
      assert(pending.body.fields.isPrivate.booleanValue === false, 'Private flag cannot complete before the remaining pages');
      assert(pending.body.fields.privacyMigrationTarget.booleanValue === true, 'Interrupted job must retain its target');
    }
    cursor = docs.at(-1).name;
  }
  assert(count === 501, 'Every post must be migrated exactly once');
  allowed(await commit(owner.token, [write(userPath, { isPrivate: b(isPrivate) }, {
    mask: ['isPrivate', 'privacyMigrationTarget'],
  })]), 'Complete transition');
}
await migrate(true);
const regularPost = 'posts/' + prefix + '0001';
denied(await get(follower.token, regularPost), 'Approved follower cannot see posts from private account');
denied(await get(outsider.token, regularPost), 'Outsider cannot read completed private posts');
denied(await get(follower.token, 'posts/' + prefix + '0000'), 'Explicit private post stays private');
allowed(await commit(owner.token, [write(userPath, { isPrivate: b(false), privacyMigrationTarget: b(false) }, {
  mask: ['isPrivate', 'privacyMigrationTarget'],
})]), 'Broaden profile before posts');
await migrate(false);
allowed(await get(outsider.token, regularPost), 'Posts become public after public transition');
denied(await get(outsider.token, 'posts/' + prefix + '0000'), 'Explicit private post never becomes public');
console.log('PASS privacy: 501 posts, cursor pages, interruption marker, concurrent-write barrier, follower/private/public access');
