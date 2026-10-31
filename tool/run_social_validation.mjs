import { mkdirSync, appendFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
// เรียงให้ชุดเดิมทดสอบก่อน แล้วค่อยเปิด enforcement สำหรับชุดใหม่ใน Emulator เท่านั้น
mkdirSync('build/social-validation', {recursive:true});
const log = 'build/social-validation/firebase-tests.txt';
writeFileSync(log, '');
for (const script of [...(process.env.LINKO_INCLUDE_BROWSER === 'true' ? ['tool/run_service_checks.mjs'] : []), 'tool/run_emulator_tests.mjs', 'tool/social_features_emulator_test.mjs']) {
  const result = spawnSync(process.execPath, [script], { env: process.env, encoding:'utf8', windowsHide:true });
  appendFileSync(log, (result.stdout ?? '') + (result.stderr ?? ''));
  process.stdout.write(result.stdout ?? '');
  if (result.status !== 0) process.stderr.write(result.stderr ?? '');
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
