// รัน regression ของสิทธิ์โพสต์ต่อเนื่องใน Emulator ชุดเดียว โดยไม่แตะ production
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scripts = ['post_privacy_access_emulator_test.mjs', 'privacy_rules_emulator_test.mjs',
  'feed_query_emulator_test.mjs', 'social_features_emulator_test.mjs'];
for (const script of scripts) {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL(script, import.meta.url))], {
    stdio: 'inherit', env: process.env, cwd: fileURLToPath(new URL('..', import.meta.url)),
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
console.log('PASS all 4 post-privacy Emulator suites');
