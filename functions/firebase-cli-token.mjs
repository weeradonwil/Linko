import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

let cached;
// ใช้บัญชีที่ firebase login ไว้แล้ว ไม่เขียน token หรือ service-account key ลงโปรเจกต์
export async function cliAccessToken() {
  if (cached?.until > Date.now()+60000) return cached.token;
  const globalModules = process.platform === 'win32' ? join(process.env.APPDATA, 'npm', 'node_modules') : execFileSync('npm',['root','-g'],{encoding:'utf8'}).trim();
  const require = createRequire(join(globalModules,'firebase-tools','package.json'));
  const auth = require(join(globalModules,'firebase-tools','lib','auth.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error('Run firebase login first, or use the ADC bootstrap mode');
  // ปิด output ภายใน CLI ขณะ refresh เพื่อไม่ให้ข้อมูล credential หลุดเข้า log ส่งงาน
  const stdout = process.stdout.write;
  const stderr = process.stderr.write;
  let tokens;
  try {
    process.stdout.write = () => true;
    process.stderr.write = () => true;
    tokens = await auth.getAccessToken(account.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform','https://www.googleapis.com/auth/firebase']);
  } finally { process.stdout.write=stdout; process.stderr.write=stderr; }
  if (!tokens.access_token) throw new Error('Firebase CLI authentication failed');
  cached={token:tokens.access_token,until:tokens.expires_at ?? Date.now()+300000};
  return cached.token;
}

export async function firebaseRest(url, {method='GET',body,optional=false}={}) {
  const parsed = new URL(url);
  if (!['firestore.googleapis.com','identitytoolkit.googleapis.com','firebaserules.googleapis.com','cloudfunctions.googleapis.com'].includes(parsed.hostname) || parsed.protocol!=='https:') throw new Error('Unexpected Firebase API host');
  const response = await fetch(url,{method,headers:{Authorization:`Bearer ${await cliAccessToken()}`,'Content-Type':'application/json'},...(body ? {body:JSON.stringify(body)} : {}),signal:AbortSignal.timeout(60000)});
  const data = await response.json();
  if (optional && response.status===404) return null;
  // แสดงแค่รหัสสาเหตุ ไม่ dump response ที่อาจมีข้อมูลบัญชีหรือ credential
  if (!response.ok) {
    const error = new Error(`Firebase ${method}: HTTP ${response.status} (${data.error?.status ?? 'request-failed'})`);
    error.reason = data.error?.details?.find(item => item.reason)?.reason;
    throw error;
  }
  return data;
}
