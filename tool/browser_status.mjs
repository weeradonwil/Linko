// อ่านสถานะหน้า Chrome ทดสอบในเครื่องเพื่อวินิจฉัยเมื่อโหลดแอปหรือรอผลทดสอบนานผิดปกติ
const targets = await (await fetch('http://127.0.0.1:18091/json/list')).json();
const target = targets.find(item => item.type === 'page' && item.url.startsWith('http://127.0.0.1:18090/'));
if (!target) throw new Error('No local Flutter test page');
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
ws.onmessage = event => {
  console.log(event.data);
  ws.close();
};
ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { returnByValue: true,
  expression: `({ready: document.readyState, text: document.body.innerText, chat: globalThis.linkoChatTestResults,
    social: globalThis.linkoSocialTestResults, progress: globalThis.linkoSocialTestProgress,
    resources: performance.getEntriesByType('resource').map(r => ({name:r.name,duration:r.duration,size:r.transferSize})).slice(-4)})`,
} }));
