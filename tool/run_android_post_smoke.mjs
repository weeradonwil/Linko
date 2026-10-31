// ใช้ emulators:exec พร้อม demo-linko เท่านั้น และคืนแอปปกติให้เสมอหลังทดสอบ
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {existsSync, mkdirSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';

assert.equal(process.env.GCLOUD_PROJECT, 'demo-linko');
assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^(127\.0\.0\.1|localhost):8080$/);
const adb = process.env.LINKO_ADB ?? 'C:/Users/Admin/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const serial = process.env.LINKO_ANDROID_SERIAL ?? 'emulator-5554';
assert.match(serial, /^emulator-\d+$/, 'Use only a local Android emulator');
const smoke = resolve('build/system_review/Linko-native-smoke.apk');
const normal = resolve('build/system_review/Linko-main-debug.apk');
assert(existsSync(smoke) && existsSync(normal), 'Build both smoke and normal APKs before starting');
// เตรียมเฉพาะ flags ของ demo fixture จึงรันชุด Android เดี่ยวๆ ได้ด้วย
const setup = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-linko/databases/(default)/documents/app_config/security?updateMask.fieldPaths=verificationRequired&updateMask.fieldPaths=writeTicketsRequired`, {
  method:'PATCH', headers:{Authorization:'Bearer owner','Content-Type':'application/json'},
  body:JSON.stringify({fields:{verificationRequired:{booleanValue:true},writeTicketsRequired:{booleanValue:true}}}),
  signal:AbortSignal.timeout(30000),
});
assert(setup.ok, `Local Android fixture setup failed: ${setup.status}`);
const run = args => execFileSync(adb, ['-s', serial, ...args], {
  encoding:'utf8', windowsHide:true, timeout:120000,
});
const launch = () => {
  run(['shell','am','force-stop','com.example.social_app']);
  run(['shell','am','start','-W','-n','com.example.social_app/.MainActivity']);
};
let results;
try {
  assert.match(run(['install','-r',smoke]), /Success/);
  launch();
  const pid = run(['shell','pidof','-s','com.example.social_app']).trim();
  assert.match(pid, /^\d+$/);
  const deadline = Date.now()+600000;
  while (Date.now()<deadline) {
    const log = run(['logcat','-d','--pid',pid,'-s','flutter:I']);
    const marker = log.split(/\r?\n/).findLast(line => line.includes('LINKO_ANDROID_RESULT '));
    if (marker) {
      results = JSON.parse(marker.slice(marker.indexOf('LINKO_ANDROID_RESULT ')+21));
      break;
    }
    await new Promise(done=>setTimeout(done,1000));
  }
  assert(results, 'Native Android test timed out');
  mkdirSync('build/system_review',{recursive:true});
  writeFileSync('build/system_review/android-results.json',JSON.stringify(results,null,2)+'\n');
  for(const item of results) console.log(`${item.passed?'PASS':'FAIL'} [native Android] ${item.name}${item.error ? ': '+item.error : ''}`);
  assert(results.length===5 && results.every(item=>item.passed),'Some native Android checks failed');
} finally {
  // install -r รักษาข้อมูลบัญชีเดิม ไม่ uninstall และไม่ใช้ pm clear
  assert.match(run(['install','-r',normal]), /Success/);
  launch();
  console.log('RESTORED normal Linko build; existing app data preserved');
}
