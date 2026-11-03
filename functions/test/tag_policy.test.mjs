import test from 'node:test';
import assert from 'node:assert/strict';
import { isValidTaggedUserIds, newlyTaggedUserIds } from '../tag_policy.mjs';

test('tagged accounts accept a short, unique list without the author', () => {
  assert.equal(isValidTaggedUserIds('author', ['friend-a', 'friend-b']), true);
});

test('tag list rejects self tags, duplicates, invalid ids and more than ten accounts', () => {
  assert.equal(isValidTaggedUserIds('author', ['author']), false);
  assert.equal(isValidTaggedUserIds('author', ['friend', 'friend']), false);
  assert.equal(isValidTaggedUserIds('author', ['bad/id']), false);
  assert.equal(isValidTaggedUserIds('author', Array.from({ length: 11 }, (_, i) => `friend-${i}`)), false);
});

test('only newly added tagged accounts get a notification event', () => {
  assert.deepEqual(
    newlyTaggedUserIds({ taggedUserIds: ['old', 'removed'] }, { taggedUserIds: ['old', 'new', 'new'] }),
    ['new'],
  );
});

test('untagging everyone does not create a tag notification', () => {
  assert.deepEqual(newlyTaggedUserIds({ taggedUserIds: ['old'] }, { taggedUserIds: [] }), []);
});
