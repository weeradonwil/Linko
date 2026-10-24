// เปิด Flutter test entry point และ Chrome แบบ headless เพื่อทดสอบบริการแชทหรือ Social ตัวจริง
// เก็บผล JSON/log ใน build/chat_diagnostics และปิดเฉพาะ process ที่สคริปต์นี้สร้าง
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { mkdir, mkdtemp, writeFile, readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { resolve, join, extname, sep } from 'node:path';

// ให้เริ่มผ่าน emulators:exec ของ demo-linko เพื่อรับรองว่าชี้ Auth/Firestore ไปเครื่องนี้
assert.equal(process.env.GCLOUD_PROJECT, 'demo-linko');
assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^(127\.0\.0\.1|localhost):8080$/);
assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '', /^(127\.0\.0\.1|localhost):9099$/);
const root = resolve(process.env.LINKO_SMOKE_OUTPUT ?? 'build/chat_diagnostics');
const targetFile = process.env.LINKO_SMOKE_TARGET ?? 'tool/chat_service_smoke.dart';
const resultKey = process.env.LINKO_SMOKE_RESULT_KEY ?? 'linkoChatTestResults';
const label = process.env.LINKO_SMOKE_LABEL ?? 'ChatService';
assert.match(resultKey, /^[A-Za-z_$][A-Za-z0-9_$]*$/);
await mkdir(root, { recursive: true });
const profile = await mkdtemp(resolve(root, 'chrome-'));
const log = createWriteStream(resolve(root, 'chat_service_browser.log'));
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let flutter;
let chrome;
let ws;
let serverReady = false;
let fixtureServer;
let staticServer;
let nextId = 0;
const pending = new Map();

// รอ server/ผลทดสอบพร้อมภายในเวลาที่กำหนด โดยตรวจสถานะซ้ำแทนการเดาเวลาเปิดโปรแกรม
async function waitFor(action, timeoutMs) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    if (flutter && flutter.exitCode !== null) throw new Error(`Flutter exited with code ${flutter.exitCode}; see browser log`);
    const result = await action().catch(() => null);
    if (result) return result;
    await delay(500);
  }
  throw new Error('Timed out waiting for the Flutter/Chrome test process. See chat_service_browser.log.');
}

// จับคู่คำสั่ง Chrome DevTools กับผลตอบกลับด้วย ID และยกเลิกการรอเมื่อหมดเวลา
function command(method, params = {}) {
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(method + ' timed out')); }, 10000);
    pending.set(id, (result) => { clearTimeout(timer); resolve(result); });
    ws.send(JSON.stringify({ id, method, params }));
  });
}

try {
  if (resultKey === 'linkoSocialTestResults') {
    // ใช้วิดีโอตัวอย่างจากเอกสาร Flutter และ cache ใน build; ไม่แนบไฟล์ทดสอบในแอปจริง
    const fixturePath = resolve('build/social_diagnostics/butterfly.mp4');
    let bytes;
    try { bytes = await readFile(fixturePath); }
    catch {
      const response = await fetch('https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4', { signal: AbortSignal.timeout(30000) });
      assert(response.ok, 'Cannot download official Flutter video fixture');
      bytes = Buffer.from(await response.arrayBuffer());
      await mkdir(resolve('build/social_diagnostics'), { recursive: true });
      await writeFile(fixturePath, bytes);
    }
    assert(bytes.length > 0 && bytes.length <= 50 * 1024 * 1024, 'Invalid fixture size');
    fixtureServer = createServer((request, response) => {
      if (request.url !== '/fixture.mp4') { response.writeHead(404).end(); return; }
      response.writeHead(200, { 'Content-Type': 'video/mp4', 'Content-Length': bytes.length,
        'Access-Control-Allow-Origin': 'http://127.0.0.1:18090' });
      response.end(bytes);
    });
    await new Promise((resolve, reject) => {
      fixtureServer.once('error', reject); fixtureServer.listen(18092, '127.0.0.1', resolve);
    });
  }
  if (process.env.LINKO_SMOKE_PREBUILT) {
    // เสิร์ฟ build ที่ตรวจไว้แล้วได้ เพื่อแยกข้อผิดพลาดของ compiler ออกจากบริการที่กำลังทดสอบ
    const directory = resolve(process.env.LINKO_SMOKE_PREBUILT);
    const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html',
      '.json': 'application/json', '.ttf': 'font/ttf', '.png': 'image/png' };
    staticServer = createServer(async (request, response) => {
      const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
      const file = resolve(directory, '.' + (pathname === '/' ? '/index.html' : pathname));
      if (!file.startsWith(directory + sep)) { response.writeHead(403).end(); return; }
      try {
        const data = await readFile(file);
        response.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
        response.end(data);
      } catch { response.writeHead(404).end(); }
    });
    await new Promise((resolve, reject) => { staticServer.once('error', reject); staticServer.listen(18090, '127.0.0.1', resolve); });
  } else {
  // ใช้ web-server แบบ release เพื่อให้ Chrome โหลด main.dart.js ได้โดยไม่ใช้ debug extension
  const flutterArgs = [
    'run', '--release', '--no-pub', '-d', 'web-server', '--target=' + targetFile,
    '--web-hostname=127.0.0.1', '--web-port=18090',
  ];
  // An explicit SDK avoids PATH ambiguity and shell wrappers on Windows.
  const sdk = process.env.LINKO_FLUTTER_SDK;
  const executable = sdk
    ? join(sdk, 'bin', 'cache', 'dart-sdk', 'bin', process.platform === 'win32' ? 'dart.exe' : 'dart')
    : process.platform === 'win32' ? process.env.ComSpec : 'flutter';
  const args = sdk
    ? [join(sdk, 'bin', 'cache', 'flutter_tools.snapshot'), '--suppress-analytics', ...flutterArgs]
    : process.platform === 'win32' ? ['/d', '/c', 'flutter ' + flutterArgs.join(' ')] : flutterArgs;
  flutter = spawn(executable, args,
    { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  flutter.stdout.pipe(log, { end: false });
  flutter.stderr.pipe(log, { end: false });
  // รอ Flutter ยืนยันว่า build ใหม่พร้อม ก่อนอ่าน main.dart.js ที่อาจยังเป็นของรอบก่อน
  flutter.stdout.on('data', chunk => {
    if (chunk.toString().includes('is being served at http://127.0.0.1:18090')) serverReady = true;
  });
  await waitFor(async () => {
    if (!serverReady) return false;
    const response = await fetch('http://127.0.0.1:18090/main.dart.js', { signal: AbortSignal.timeout(2000) });
    return response.ok && !response.headers.get('content-type')?.includes('text/html');
  }, 240000);
  }
  console.log('Flutter service-check page ready; starting isolated headless Chrome.');
  // ใช้โปรไฟล์ชั่วคราวแยก เพื่อไม่ใช้เซสชันหรือการตั้งค่าของ Chrome ที่ผู้ใช้เปิดอยู่
  chrome = spawn(process.env.CHROME_EXECUTABLE, [
    '--headless=new', '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    '--autoplay-policy=no-user-gesture-required',
    '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
    '--disable-backgrounding-occluded-windows',
    '--remote-debugging-port=18091', '--user-data-dir=' + profile, 'http://127.0.0.1:18090/',
  ], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  chrome.stdout.pipe(log, { end: false });
  chrome.stderr.pipe(log, { end: false });
  const target = await waitFor(async () => {
    const targets = await (await fetch('http://127.0.0.1:18091/json/list')).json();
    return targets.find((item) => item.type === 'page' && item.url.startsWith('http://127.0.0.1:18090/'));
  }, 20000);
  ws = new WebSocket(target.webSocketDebuggerUrl);
  ws.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    } else if (message.method === 'Runtime.exceptionThrown' || message.method === 'Log.entryAdded') {
      log.write(JSON.stringify(message) + '\n');
    }
  };
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  await command('Runtime.enable');
  await command('Log.enable');
  // อ่านค่าที่หน้า Flutter ส่งออกหลังจบทุกกรณี แล้วให้ process ล้มเหลวหากมีกรณีใดไม่ผ่าน
  const results = await waitFor(async () => {
    const response = await command('Runtime.evaluate', {
      expression: `globalThis.${resultKey} ?? null`, returnByValue: true,
    });
    return response.result?.result?.value;
  }, 600000);
  await writeFile(resolve(root, 'chat_service_results.json'), JSON.stringify(results, null, 2));
  for (const result of results) console.log(`${result.passed ? 'PASS' : 'FAIL'} [real ${label}/Chrome] ${result.name}${result.error ? ': ' + result.error : ''}`);
  assert(results.every((result) => result.passed), `Real ${label} browser checks failed.`);
  console.log(`Real ${label}/Chrome: ${results.length}/${results.length} passed`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  // ขอปิดตามปกติก่อน; หากยังค้างให้หยุดเฉพาะ process tree ที่สคริปต์นี้เป็นผู้เปิด
  if (ws?.readyState === WebSocket.OPEN) {
    await command('Browser.close').catch(() => {});
    ws.close();
  }
  if (flutter && flutter.exitCode === null) {
    flutter.stdin.write('q\n');
    await Promise.race([new Promise((resolve) => flutter.once('exit', resolve)), delay(5000)]);
  }
  for (const child of [chrome, flutter]) {
    if (child && child.exitCode === null) {
      if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
      else child.kill('SIGTERM');
    }
  }
  log.end();
  if (staticServer) await new Promise(resolve => staticServer.close(resolve));
  if (fixtureServer) await new Promise(resolve => fixtureServer.close(resolve));
}
