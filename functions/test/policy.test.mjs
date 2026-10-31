import test from 'node:test';
import assert from 'node:assert/strict';
import { readPolicy, contentHash, caseId, needsWarning, expiredWarning, suspensionEnd, isSuspended, reserveRate } from '../policy.mjs';

// ทดสอบกติกาล้วนๆ ไม่มีการต่อ Firebase จริงและไม่มีค่าใช้จ่าย
test('default policy matches two reporters and 24/72 hours', () => {
  const policy = readPolicy();
  assert.equal(policy.reportThreshold, 2); assert.equal(policy.warningHours, 24); assert.equal(policy.suspensionHours, 72);
});
test('invalid policy cannot produce an immediate or indefinite ban', () => {
  const value = readPolicy({ reportThreshold: 0, warningHours: -1, suspensionHours: Infinity });
  assert.equal(value.reportThreshold, 2); assert.equal(value.warningHours, 24); assert.equal(value.suspensionHours, 72);
});
test('auto enforcement requires an explicit server configuration', () => { assert.equal(readPolicy().autoEnforce, false); assert.equal(readPolicy({autoEnforce:true}).autoEnforce, true); });
test('one reporter cannot reach the selected public threshold', () => assert.equal(needsWarning(1, readPolicy(), null), false));
test('second reporter reaches the selected public threshold', () => assert.equal(needsWarning(2, readPolicy(), null), true));
test('ordinary group reports wait for the owner', () => assert.equal(needsWarning(20, readPolicy(), 'group'), false));
test('warning is not expired before its deadline', () => assert.equal(expiredWarning({status:'warned',deadlineMs:200},199), false));
test('warning expires at the exact deadline', () => assert.equal(expiredWarning({status:'warned',deadlineMs:200},200), true));
test('contested reports cannot be automatically expired', () => assert.equal(expiredWarning({status:'contested',deadlineMs:100},200), false));
test('suspension lasts exactly 72 hours and expires without a client clock', () => { const end = suspensionEnd(1000); assert.equal(end, 1000 + 72*3600000); assert.equal(isSuspended(end,end-1), true); assert.equal(isSuspended(end,end), false); });
test('whitespace-only edits do not change the evidence hash', () => assert.equal(contentHash({content:'Hello'}), contentHash({content:' Hello '})));
test('changing media or text changes the evidence hash', () => { assert.notEqual(contentHash({content:'A'}), contentHash({content:'B'})); assert.notEqual(contentHash({content:'A',mediaPath:'one'}), contentHash({content:'A',mediaPath:'two'})); });
test('post locations cannot collide across groups and feed', () => assert.notEqual(caseId('posts/p'), caseId('groups/g/posts/p')));
test('rate limiter rejects a burst and opens a fresh window', () => { const current = {started:100,count:5}; assert.equal(reserveRate(current,101,1000,5),null); assert.deepEqual(reserveRate(current,1100,1000,5),{started:1100,count:1}); });
