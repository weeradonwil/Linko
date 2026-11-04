// มีเพียงสองระดับ: เตือนครั้งแรก และพัก 72 ชั่วโมงเมื่อมีเคสใหม่ซ้ำภายใน 90 วัน
// ใช้เวลาจากเซิร์ฟเวอร์ และไม่ลดโทษเดิมหากบัญชียังมีเวลาพักที่นานกว่า
export const REPEAT_REPORT_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;
export const REPEAT_REPORT_SUSPENSION_MS = 72 * 60 * 60 * 1000;

export function repeatReportDecision({ now, previousAt, currentUntil = 0 }) {
  if (!Number.isFinite(now)) throw new TypeError('Server time is required');
  const repeated = Number.isFinite(previousAt) && previousAt <= now &&
    previousAt >= now - REPEAT_REPORT_WINDOW_MS;
  return {
    level: repeated ? 2 : 1,
    ...(repeated ? { suspensionUntil: Math.max(
      Number.isFinite(currentUntil) ? currentUntil : 0,
      now + REPEAT_REPORT_SUSPENSION_MS,
    ) } : {}),
  };
}
