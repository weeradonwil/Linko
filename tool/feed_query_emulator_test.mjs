import { createUser, createProfile, follow, commit, request, write, s, b, a,
  documentName, allowed, denied, assert } from './emulator_test_support.mjs';

const viewer = await createUser(), outsider = await createUser();
await createProfile(viewer); await createProfile(outsider);
const authors = await Promise.all(Array.from({ length: 5 }, () => createUser()));
const suffix = Date.now();
for (const [index, author] of authors.entries()) {
  await createProfile(author);
  await follow(viewer, author);
  allowed(await commit(author.token, [write(`users/${author.uid}`, { isPrivate: b(true) }, {
    mask: ['isPrivate'], timestamps: ['updatedAt'],
  })]), 'Make followed author private');
  allowed(await commit(author.token, [write(`posts/feed_${suffix}_${index}`, {
    userId: s(author.uid), authorName: s('Author'), content: s('Follower post'),
    tags: a([]), visibility: s('followers'), authorIsPrivate: b(true), mediaType: s('none'),
  }, { timestamps: ['createdAt', 'updatedAt'] })]), 'Create follower-only post');
}
const structuredQuery = {
  from: [{ collectionId: 'posts' }],
  where: { compositeFilter: { op: 'AND', filters: [
    { fieldFilter: { field: { fieldPath: 'userId' }, op: 'IN', value: a(authors.map(u => s(u.uid))) } },
    { fieldFilter: { field: { fieldPath: 'visibility' }, op: 'EQUAL', value: s('followers') } },
  ] } }, orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }], limit: 30,
};
const followed = await request(':runQuery', { token: viewer.token, method: 'POST', body: { structuredQuery } });
allowed(followed, 'Grouped query for five approved authors');
assert(followed.body.filter(r => r.document).length === 5, 'All five author posts visible');
denied(await request(':runQuery', { token: outsider.token, method: 'POST', body: { structuredQuery } }), 'Outsider grouped query');

// Seed deterministic legacy timestamps to check actual newest-first query and
// a document cursor when multiple documents have the same creation time.
const timestamp = { timestampValue: '2026-10-22T00:00:00Z' };
allowed(await commit('owner', Array.from({ length: 61 }, (_, i) => write(`posts/page_${suffix}_${String(i).padStart(3, '0')}`, {
  userId: s(viewer.uid), authorName: s('Viewer'), content: s('Page post'), tags: a([]),
  visibility: s('private'), authorIsPrivate: b(false), mediaType: s('none'),
  createdAt: timestamp, updatedAt: timestamp,
}))), 'Seed pagination documents');
const ownQuery = {
  from: [{ collectionId: 'posts' }],
  where: { fieldFilter: { field: { fieldPath: 'userId' }, op: 'EQUAL', value: s(viewer.uid) } },
  orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' },
    { field: { fieldPath: '__name__' }, direction: 'DESCENDING' }], limit: 30,
};
const ids = new Set(); let cursor;
for (let page = 0; page < 3; page++) {
  const result = await request(':runQuery', { token: viewer.token, method: 'POST', body: {
    structuredQuery: { ...ownQuery, ...(cursor ? { startAt: { values: [timestamp, { referenceValue: cursor }], before: false } } : {}) },
  } });
  allowed(result, 'Cursor page');
  const docs = result.body.filter(r => r.document).map(r => r.document);
  assert(docs.length === (page < 2 ? 30 : 1), 'Correct page size with equal timestamps');
  for (const doc of docs) { assert(!ids.has(doc.name), 'No duplicate page document'); ids.add(doc.name); }
  cursor = docs.at(-1)?.name;
}
assert(ids.size === 61 && ids.has(documentName(`posts/page_${suffix}_000`)), 'All older posts reachable');
console.log('PASS grouped follower query, outsider denial and 61 posts across cursor pages');
