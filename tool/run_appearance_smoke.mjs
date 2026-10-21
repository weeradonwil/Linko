// เปิดหน้า Flutter ทดสอบธีมบน Chrome จริง เก็บผล/ภาพ และปิดเฉพาะ process ที่สร้างเอง
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { basename, dirname, resolve } from 'node:path';

const root = resolve('build/appearance_diagnostics');
await mkdir(root, { recursive: true });
const profile = await mkdtemp(resolve(root, 'chrome-'));
const log = createWriteStream(resolve(root, 'browser.log'));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let flutter, chrome, ws, results;
let serverReady = false;
let startupOutput = '';
let serial = 0;
const pending = new Map();

// รอ asset/เบราว์เซอร์/ผลทดสอบตามสถานะจริง พร้อมเวลาสิ้นสุดเพื่อไม่ค้างไม่มีกำหนด
async function waitFor(action, timeoutMs) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    const result = await action().catch(() => null);
    if (result) return result;
    await delay(500);
  }
  throw new Error('Appearance smoke check timed out; see build/appearance_diagnostics/browser.log');
}

// จับคู่คำสั่ง Chrome DevTools กับคำตอบผ่าน ID เพื่ออ่านผลและถ่ายภาพหน้า Flutter
function command(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++serial;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(method + ' timed out')); }, 15000);
    pending.set(id, response => { clearTimeout(timer); resolve(response); });
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function screenshot(name) {
  const response = await command('Page.captureScreenshot', { format: 'png' });
  assert(response.result?.data, 'Chrome screenshot must be available');
  await writeFile(resolve(root, name), Buffer.from(response.result.data, 'base64'));
}

try {
  // web-server แบบ release โหลดได้โดยไม่พึ่ง Flutter debug extension
  const args = ['run', '--release', '--no-pub', '-d', 'web-server', '--target=tool/appearance_smoke.dart', '--web-hostname=127.0.0.1', '--web-port=18110'];
  flutter = spawn(process.platform === 'win32' ? process.env.ComSpec : 'flutter',
    process.platform === 'win32' ? ['/d', '/c', 'flutter ' + args.join(' ')] : args,
    { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  flutter.stdout.pipe(log, { end: false });
  flutter.stderr.pipe(log, { end: false });
  flutter.stdout.on('data', chunk => {
    startupOutput = (startupOutput + chunk.toString()).slice(-8192);
    serverReady ||= startupOutput.includes('is being served at http://127.0.0.1:18110');
  });
  await waitFor(async () => {
    if (!serverReady) return false;
    const response = await fetch('http://127.0.0.1:18110/main.dart.js', { signal: AbortSignal.timeout(2000) });
    // Flutter อาจเสิร์ฟ build/web เก่าระหว่าง compile; ต้องรอ asset ของ entry point นี้จริง
    return response.ok && !response.headers.get('content-type')?.includes('text/html') && (await response.text()).includes('LINKO_APPEARANCE_SMOKE ');
  }, 240000);
  chrome = spawn(process.env.CHROME_EXECUTABLE, ['--headless=new', '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--remote-debugging-port=18111', '--user-data-dir=' + profile, 'about:blank'], { windowsHide: true, stdio: 'ignore' });
  const target = await waitFor(async () => (await (await fetch('http://127.0.0.1:18111/json/list')).json()).find(item => item.type === 'page'), 20000);
  ws = new WebSocket(target.webSocketDebuggerUrl);
  ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    } else if (message.method === 'Runtime.consoleAPICalled') {
      const text = message.params.args.map(arg => arg.value ?? '').join(' ');
      log.write(text + '\n');
      const marker = 'LINKO_APPEARANCE_SMOKE ';
      if (text.includes(marker)) results = JSON.parse(text.slice(text.indexOf(marker) + marker.length));
    } else if (message.method === 'Runtime.exceptionThrown') {
      log.write(JSON.stringify(message.params.exceptionDetails) + '\n');
    }
  };
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  await command('Runtime.enable');
  await command('Emulation.setDeviceMetricsOverride', { width: 393, height: 852, deviceScaleFactor: 1, mobile: true });
  await command('Page.navigate', { url: 'http://127.0.0.1:18110/' });
  await waitFor(async () => results, 90000);
  await writeFile(resolve(root, 'chrome_results.json'), JSON.stringify(results, null, 2));
  for (const result of results) console.log(`${result.passed ? 'PASS' : 'FAIL'} [Chrome] ${result.name}`);
  assert(results.every(result => result.passed), 'Chrome appearance checks failed');
  await delay(500);
  await screenshot('chrome_dark.png');
  // เปิดเมนูจริงด้วยตำแหน่งปุ่มบน viewport โทรศัพท์ เพื่อบันทึกภาพตรวจด้วยสายตา
  await command('Input.dispatchMouseEvent', { type: 'mousePressed', x: 365, y: 28, button: 'left', clickCount: 1 });
  await command('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 365, y: 28, button: 'left', clickCount: 1 });
  await delay(500);
  await screenshot('chrome_settings.png');
  console.log(`Chrome appearance: ${results.length}/${results.length} passed`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (ws?.readyState === WebSocket.OPEN) { await command('Browser.close').catch(() => {}); ws.close(); }
  if (flutter && flutter.exitCode === null) {
    flutter.stdin.write('q\n');
    await Promise.race([new Promise(resolve => flutter.once('exit', resolve)), delay(3000)]);
  }
  for (const child of [chrome, flutter]) {
    if (child && child.exitCode === null) {
      if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
      else child.kill();
    }
  }
  log.end();
  // ตรวจขอบเขตก่อนลบโปรไฟล์ชั่วคราว; ไม่ลบโฟลเดอร์ Chrome หรือไฟล์ของผู้ใช้
  assert.equal(dirname(profile), root);
  assert(basename(profile).startsWith('chrome-'));
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 });
}
