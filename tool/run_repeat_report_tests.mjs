// รันระบบเดิมก่อนเปิด flag ใหม่ เพื่อยืนยันว่า opt-in ไม่เปลี่ยนพฤติกรรมเดิม
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
for (const script of ['social_features_emulator_test.mjs', 'repeat_report_emulator_test.mjs']) {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL(script, import.meta.url))], {
    stdio: 'inherit', env: process.env, cwd: fileURLToPath(new URL('..', import.meta.url)),
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
