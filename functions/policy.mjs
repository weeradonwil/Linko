import { createHash } from 'node:crypto';

// เปลี่ยนกติกาใน app_config/moderation ได้ โดยไม่ต้อง build แอปใหม่
export const defaults = Object.freeze({ reportThreshold: 2, warningHours: 24, suspensionHours: 72, minimumAccountHours: 24, autoEnforce: false });
export function readPolicy(data = {}) {
  const integer = (key, min, max) => Number.isInteger(data[key]) && data[key] >= min && data[key] <= max ? data[key] : defaults[key];
  return { reportThreshold: integer('reportThreshold', 1, 100), warningHours: integer('warningHours', 1, 168), suspensionHours: integer('suspensionHours', 1, 720), minimumAccountHours: integer('minimumAccountHours', 0, 720), autoEnforce: data.autoEnforce === true, repeatReportSuspensionEnabled: data.repeatReportSuspensionEnabled === true };
}
export const contentHash = post => createHash('sha256').update(JSON.stringify([String(post.content ?? '').trim(), post.mediaPath ?? null, post.sharedPostId ?? null])).digest('hex');
export const caseId = path => createHash('sha256').update(path).digest('hex');
export function needsWarning(count, policy, groupId) { return groupId == null && count >= policy.reportThreshold; }
export function expiredWarning(data, now) { return data.status === 'warned' && Number.isFinite(data.deadlineMs) && data.deadlineMs <= now; }
export function suspensionEnd(now, hours = 72) { return now + hours * 60 * 60 * 1000; }
export function isSuspended(until, now) { return Number.isFinite(until) && until > now; }
export function reserveRate(current, now, windowMs, maximum) {
  const started = Number.isFinite(current?.started) ? current.started : now;
  const fresh = now - started >= windowMs;
  const count = fresh ? 0 : (current?.count ?? 0);
  if (count >= maximum) return null;
  return { started: fresh ? now : started, count: count + 1 };
}
