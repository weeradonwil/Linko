import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scripts = [
  'chat_rules_emulator_test.mjs', 'group_rules_emulator_test.mjs',
  'audit_rules_emulator_test.mjs', 'privacy_rules_emulator_test.mjs',
  'feed_query_emulator_test.mjs', 'chat_rules_diagnosis.mjs',
];
for (const script of scripts) {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL(script, import.meta.url))], {
    stdio: 'inherit', env: process.env,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
console.log(`PASS all ${scripts.length} Firebase Emulator suites`);
