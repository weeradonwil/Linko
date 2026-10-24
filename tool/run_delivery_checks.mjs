// จุดรันตรวจรับใน Emulator: บริการ Flutter/Chrome ก่อน แล้วตรวจ Rules ทั้งกรณีอนุญาตและปฏิเสธ
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
for (const script of ['run_service_checks.mjs', 'run_emulator_tests.mjs']) {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL(script, import.meta.url))], {
    cwd: fileURLToPath(new URL('..', import.meta.url)), env: process.env, stdio: 'inherit', windowsHide: true,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
console.log('PASS delivery browser and rules checks');
