// Own Flutter server and headless Chrome; all chat data stays in local emulators.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';

assert.equal(process.env.GCLOUD_PROJECT, 'demo-linko');
assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^(127\.0\.0\.1|localhost):8080$/);
assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '', /^(127\.0\.0\.1|localhost):9099$/);
const root = resolve('build/chat_diagnostics');
await mkdir(root, { recursive: true });
const profile = await mkdtemp(resolve(root, 'chrome-'));
const log = createWriteStream(resolve(root, 'chat_service_browser.log'));
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let flutter;
let chrome;
let ws;
let nextId = 0;
const pending = new Map();

async function waitFor(action, timeoutMs) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    const result = await action().catch(() => null);
    if (result) return result;
    await delay(500);
  }
  throw new Error('Timed out waiting for the Flutter/Chrome test process. See chat_service_browser.log.');
}

function command(method, params = {}) {
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(method + ' timed out')); }, 10000);
    pending.set(id, (result) => { clearTimeout(timer); resolve(result); });
    ws.send(JSON.stringify({ id, method, params }));
  });
}

try {
  const flutterArgs = [
    'run', '--release', '--no-pub', '-d', 'web-server', '--target=tool/chat_service_smoke.dart',
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
  await waitFor(async () => {
    const response = await fetch('http://127.0.0.1:18090/main.dart.js', { signal: AbortSignal.timeout(2000) });
    return response.ok && !response.headers.get('content-type')?.includes('text/html');
  }, 180000);
  console.log('Flutter service-check page ready; starting isolated headless Chrome.');
  chrome = spawn(process.env.CHROME_EXECUTABLE, [
    '--headless=new', '--no-first-run', '--no-default-browser-check', '--disable-extensions',
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
  const results = await waitFor(async () => {
    const response = await command('Runtime.evaluate', {
      expression: 'globalThis.linkoChatTestResults ?? null', returnByValue: true,
    });
    return response.result?.result?.value;
  }, 180000);
  await writeFile(resolve(root, 'chat_service_results.json'), JSON.stringify(results, null, 2));
  for (const result of results) console.log(`${result.passed ? 'PASS' : 'FAIL'} [real ChatService/Chrome] ${result.name}${result.error ? ': ' + result.error : ''}`);
  assert(results.every((result) => result.passed), 'Real ChatService browser checks failed.');
  console.log(`Real ChatService/Chrome: ${results.length}/${results.length} passed`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
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
}
