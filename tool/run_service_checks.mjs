// รันทดสอบบริการ Flutter สองชุดตามลำดับ ภายใต้ Emulator ชุดเดียวและใช้ Chrome แยกโปรไฟล์
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const cwd = fileURLToPath(new URL('..', import.meta.url));
for (const scenario of [
  { target: 'tool/chat_service_smoke.dart', key: 'linkoChatTestResults', label: 'ChatService', output: 'build/chat_diagnostics' },
  { target: 'tool/social_service_smoke.dart', key: 'linkoSocialTestResults', label: 'Social services', output: 'build/social_diagnostics' },
]) {
  if (process.env.LINKO_SMOKE_ONLY && !scenario.target.includes(process.env.LINKO_SMOKE_ONLY)) continue;
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('run_chat_service_smoke.mjs', import.meta.url))], {
    cwd, stdio: 'inherit', windowsHide: true, env: { ...process.env,
      LINKO_SMOKE_TARGET: scenario.target, LINKO_SMOKE_RESULT_KEY: scenario.key,
      LINKO_SMOKE_LABEL: scenario.label, LINKO_SMOKE_OUTPUT: scenario.output,
    },
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
console.log('PASS all Flutter service browser suites');
