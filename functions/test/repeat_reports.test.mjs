// ทดสอบขอบเขตเวลา 90 วันและโทษระดับสอง โดยไม่เชื่อมต่อ Firebase
import test from 'node:test';
import assert from 'node:assert/strict';
import { repeatReportDecision, REPEAT_REPORT_WINDOW_MS, REPEAT_REPORT_SUSPENSION_MS } from '../repeat_reports.mjs';
import { readPolicy } from '../policy.mjs';

const now = 180 * 24 * 3600000;
test('repeat report enforcement requires an explicit opt-in', () => {
  assert.equal(readPolicy().repeatReportSuspensionEnabled, false);
  assert.equal(readPolicy({ repeatReportSuspensionEnabled: true }).repeatReportSuspensionEnabled, true);
});
test('first qualifying case only warns', () => {
  assert.deepEqual(repeatReportDecision({ now }), { level: 1 });
});
test('second case within 90 days suspends for exactly 72 hours', () => {
  assert.deepEqual(repeatReportDecision({ now, previousAt: now - 1000 }), {
    level: 2, suspensionUntil: now + 72 * 3600000,
  });
});
test('the exact 90-day boundary still counts as a repeat', () => {
  assert.equal(repeatReportDecision({ now, previousAt: now - REPEAT_REPORT_WINDOW_MS }).level, 2);
});
test('a case older than 90 days starts with a warning again', () => {
  assert.deepEqual(repeatReportDecision({ now, previousAt: now - REPEAT_REPORT_WINDOW_MS - 1 }), { level: 1 });
});
test('a repeat never shortens an already longer suspension', () => {
  const currentUntil = now + 100 * 3600000;
  assert.equal(repeatReportDecision({ now, previousAt: now - 1, currentUntil }).suspensionUntil, currentUntil);
});
test('there are only two levels, with no seven-day or thirty-day penalty', () => {
  for (let index = 0; index < 10; index++) {
    const result = repeatReportDecision({ now: now + index, previousAt: now - 1 });
    assert.equal(result.level, 2);
    assert.equal(result.suspensionUntil - now - index, REPEAT_REPORT_SUSPENSION_MS);
  }
});
test('invalid/future history cannot create a repeat', () => {
  for (const previousAt of [NaN, Infinity, now + 1]) {
    assert.equal(repeatReportDecision({ now, previousAt }).level, 1);
  }
  assert.throws(() => repeatReportDecision({ now: NaN }), TypeError);
});
