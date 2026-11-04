import test from 'node:test';
import assert from 'node:assert/strict';
import { canReadPostAudience, profileIsPrivate } from '../post_access.mjs';

// เมทริกซ์สิทธิ์ฝั่งเซิร์ฟเวอร์: บัญชีส่วนตัวต้องอนุมัติ แต่โพสต์เฉพาะฉันไม่เปิดให้ผู้ติดตาม
for (const isPrivate of [false, true]) {
  for (const visibility of ['public', 'private', 'followers']) {
    for (const isFollower of [false, true]) {
      test(`${isPrivate ? 'private' : 'public'} account / ${visibility} post / follower=${isFollower}`, () => {
        const post = { visibility, authorIsPrivate: isPrivate };
        const profile = { isPrivate };
        const expected = visibility !== 'private' && (isFollower || (!isPrivate && visibility === 'public'));
        assert.equal(canReadPostAudience(post, profile, { isFollower }), expected);
        assert.equal(canReadPostAudience(post, profile, { isOwner: true }), true);
      });
    }
  }
}
test('private transition blocks outsiders while keeping approved follower access', () => {
  const post = { visibility: 'public', authorIsPrivate: false };
  const profile = { isPrivate: false, privacyMigrationTarget: true };
  assert.equal(canReadPostAudience(post, profile), false);
  assert.equal(canReadPostAudience(post, profile, { isFollower: true }), true);
});
test('an old private snapshot stays restricted until the public transition finishes', () => {
  const post = { visibility: 'public', authorIsPrivate: true };
  const profile = { isPrivate: false };
  assert.equal(canReadPostAudience(post, profile), false);
  assert.equal(canReadPostAudience(post, profile, { isFollower: true }), true);
  assert.equal(profileIsPrivate({ isPrivate: true, privacyMigrationTarget: false }), false);
});
