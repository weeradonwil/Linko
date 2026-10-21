// Run only against local emulators; this script refuses production projects/hosts.
// firebase.cmd --config firebase.emulator.test.json emulators:exec --only auth,firestore --project demo-linko "node tool/chat_rules_emulator_test.mjs --diagnose"
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';

const projectId = process.env.GCLOUD_PROJECT ?? 'demo-linko';
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
assert(projectId.startsWith('demo-'), 'A demo- project is required.');
for (const host of [firestoreHost, authHost]) {
  assert(/^(127\.0\.0\.1|localhost):\d+$/.test(host), 'Only loopback emulators are allowed.');
}
const root = `projects/${projectId}/databases/(default)/documents`;
const base = `http://${firestoreHost}/v1/${root}`;
const diagnostic = process.argv.includes('--diagnose');
const s = (value) => ({ stringValue: value });
const n = (value) => ({ integerValue: String(value) });
const b = (value) => ({ booleanValue: value });
const map = (fields) => ({ mapValue: { fields } });
const stamp = { timestampValue: '2026-01-01T00:00:00Z' };
const path = (...parts) => parts.map((part) => '`' + part.replaceAll('`', '\\`') + '`').join('.');
const time = (fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' });

async function request(url, { token, body, method = 'GET' } = {}) {
  const response = await fetch(url, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(20000),
  });
  const text = await response.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  return { status: response.status, data };
}

const commit = (token, writes) => request(`${base}:commit`, { token, method: 'POST', body: { writes } });
const read = (token, name) => request(`${base}/${name}`, { token });
function ok(result, context) {
  assert.equal(result.status, 200, `${context}: ${JSON.stringify(result.data)}`);
}

async function user() {
  const response = await request(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator-only`, {
    method: 'POST', body: { returnSecureToken: true },
  });
  ok(response, 'Create emulator user');
  return { uid: response.data.localId, token: response.data.idToken };
}

async function loadRules(content) {
  const result = await request(`http://${firestoreHost}/emulator/v1/projects/${projectId}:securityRules`, {
    method: 'PUT', token: 'owner', body: { rules: { files: [{ name: 'firestore.rules', content }] } },
  });
  ok(result, 'Load rules in emulator');
}

const [alice, bob, outsider] = await Promise.all([user(), user(), user()]);
for (const account of [alice, bob, outsider]) {
  ok(await commit('owner', [{ update: {
    name: `${root}/users/${account.uid}`, fields: { displayName: s('Emulator user') },
  } }]), 'Seed emulator profile');
}

let sequence = 0;
let legacy = false;
function conversationFields({ previousType, previousSender = alice, previousText = 'Earlier message', hidden = false } = {}) {
  const fields = {
    participantIds: { arrayValue: { values: [alice.uid, bob.uid].sort().map(s) } },
    participantNames: map({ [alice.uid]: s('Alice'), [bob.uid]: s('Bob') }),
    unreadCounts: map({ [alice.uid]: n(0), [bob.uid]: n(2) }),
    lastReadAt: map({ [alice.uid]: stamp, [bob.uid]: stamp }),
    createdAt: stamp, updatedAt: stamp,
  };
  if (!legacy) fields.hiddenFor = map({ [alice.uid]: b(hidden), [bob.uid]: b(false) });
  if (previousType) Object.assign(fields, {
    lastMessageText: s(previousText), lastMessageType: s(previousType),
    lastMessageSenderId: s(previousSender.uid), lastMessageAt: stamp,
    ...(!legacy ? { lastMessageId: s('previous') } : {}),
  });
  return fields;
}

async function fixture(options = {}) {
  const id = `chat_diagnostic_${++sequence}`;
  const writes = [{ update: { name: `${root}/conversations/${id}`, fields: conversationFields(options) } }];
  if (options.previousType) writes.push({ update: {
    name: `${root}/conversations/${id}/messages/previous`,
    fields: {
      senderId: s((options.previousSender ?? alice).uid), type: s(options.previousType),
      text: s(options.previousText ?? 'Earlier message'), createdAt: stamp,
    },
  } });
  ok(await commit('owner', writes), 'Seed conversation');
  return id;
}

// Same fields/transforms as ChatService.sendMessage (no Storage or real network).
function sendWrites(id, sender = alice, { text = 'New message', type = 'text', spoofSender, increment = 1,
  changePeerRead = false, changeParticipants = false, omitMessage = false } = {}) {
  const peer = sender.uid === alice.uid ? bob : alice;
  const messageId = `message_${++sequence}`;
  const preview = text || (type === 'image' ? 'ส่งรูปภาพให้คุณ' : 'ส่งวิดีโอให้คุณ');
  const fields = {
    lastMessageText: s(preview), lastMessageType: s(type), lastMessageSenderId: s(sender.uid),
    unreadCounts: map({ [sender.uid]: n(0) }),
    ...(!legacy ? { lastMessageId: s(messageId), hiddenFor: map({ [sender.uid]: b(false) }) } : {}),
    ...(changeParticipants ? { participantIds: { arrayValue: { values: [sender.uid, outsider.uid].map(s) } } } : {}),
  };
  const updateMask = { fieldPaths: [
    'lastMessageText', 'lastMessageType', 'lastMessageSenderId', path('unreadCounts', sender.uid),
    ...(!legacy ? ['lastMessageId', path('hiddenFor', sender.uid)] : []),
    ...(changeParticipants ? ['participantIds'] : []),
  ] };
  const updateTransforms = [
    time('lastMessageAt'), time('updatedAt'),
    { fieldPath: path('unreadCounts', peer.uid), increment: n(increment) },
    time(path('lastReadAt', sender.uid)),
    ...(changePeerRead ? [time(path('lastReadAt', peer.uid))] : []),
  ];
  const message = { update: {
    name: `${root}/conversations/${id}/messages/${messageId}`,
    fields: { senderId: s(spoofSender?.uid ?? sender.uid), type: s(type), text: s(text),
      ...(type !== 'text' ? { mediaPath: s(`chat_media/${id}/${sender.uid}/image.jpg`) } : {}),
    },
  }, updateTransforms: [time('createdAt')], currentDocument: { exists: false } };
  const summary = { update: { name: `${root}/conversations/${id}`, fields }, updateMask, updateTransforms,
    currentDocument: { exists: true } };
  return { writes: [...(!omitMessage ? [message] : []), summary], messageId };
}

const reports = [];
async function suite(label, rules, oldClient = false) {
  legacy = oldClient;
  await loadRules(rules);
  const results = [];
  async function check(name, action, expected = 200) {
    const response = await action();
    const passed = response.status === expected;
    results.push({ name, passed, expected, actual: response.status,
      ...(!passed ? { error: response.data?.error?.message ?? response.data } : {}) });
    console.log(`${passed ? 'PASS' : 'FAIL'} [${label}] ${name}: HTTP ${response.status} (expected ${expected})`);
  }
  async function sendCase(name, before, sending = {}, sender = alice, expected = 200) {
    const id = await fixture(before);
    const { writes, messageId } = sendWrites(id, sender, sending);
    await check(name, async () => {
      const result = await commit(sender.token, writes);
      const savedMessage = await read('owner', `conversations/${id}/messages/${messageId}`);
      // A denied batch must not leave an orphan message behind.
      assert.equal(savedMessage.status, result.status === 200 ? 200 : 404, `${name}: batch atomicity`);
      if (result.status === 200) {
        const room = await read('owner', `conversations/${id}`);
        const peer = sender.uid === alice.uid ? bob : alice;
        assert.equal(Number(room.data.fields.unreadCounts.mapValue.fields[peer.uid].integerValue),
          (peer.uid === bob.uid ? 2 : 0) + 1, `${name}: recipient unread count`);
      }
      return result;
    }, expected);
  }
  const createdId = `created_${++sequence}`;
  const createdFields = conversationFields();
  delete createdFields.hiddenFor;
  delete createdFields.createdAt;
  delete createdFields.updatedAt;
  createdFields.unreadCounts = map({ [alice.uid]: n(0), [bob.uid]: n(0) });
  createdFields.lastReadAt = map({});
  await check('create conversation', () => commit(alice.token, [{
    update: { name: `${root}/conversations/${createdId}`, fields: createdFields },
    updateTransforms: [time('createdAt'), time('updatedAt'), time(path('lastReadAt', alice.uid))],
  }]));
  const firstSend = sendWrites(createdId);
  await check('first text in newly created conversation', () => commit(alice.token, firstSend.writes));
  const secondSend = sendWrites(createdId, alice, { text: 'Second message in same conversation' });
  await check('actual first-then-second send sequence', async () => {
    const response = await commit(alice.token, secondSend.writes);
    const saved = await read(bob.token, `conversations/${createdId}/messages/${secondSend.messageId}`);
    assert.equal(saved.status, response.status === 200 ? 200 : 404, 'Peer sees only successfully committed messages');
    return response;
  });
  await sendCase('second text, same sender/type', { previousType: 'text' });
  await sendCase('identical text, same sender/type', { previousType: 'text', previousText: 'New message' });
  await sendCase('reply from other user, same type', { previousType: 'text', previousSender: bob });
  await sendCase('text after unsend, same sender', { previousType: 'deleted', previousText: 'ยกเลิกข้อความนี้' });
  await sendCase('text after unsend, different sender', { previousType: 'deleted', previousSender: bob, previousText: 'ยกเลิกข้อความนี้' });
  await sendCase('different type, same sender', { previousType: 'image', previousText: 'ส่งรูปภาพให้คุณ' });
  await sendCase('consecutive image metadata', { previousType: 'image', previousText: 'ส่งรูปภาพให้คุณ' }, { type: 'image', text: '' });
  await sendCase('nonparticipant cannot send', {}, {}, outsider, 403);
  await sendCase('sender cannot impersonate peer', {}, { spoofSender: bob }, alice, 403);
  await sendCase('text length 2000', {}, { text: 'x'.repeat(2000) });
  await sendCase('text length 2001 rejected', {}, { text: 'x'.repeat(2001) }, alice, 403);
  if (!oldClient) {
    await sendCase('recipient unread count must increment', {}, { increment: 0 }, alice, 403);
    await sendCase('cannot change peer lastReadAt', {}, { changePeerRead: true }, alice, 403);
    await sendCase('cannot change participants', {}, { changeParticipants: true }, alice, 403);
    await sendCase('summary without message rejected', {}, { omitMessage: true }, alice, 403);
    const roomId = await fixture();
    await check('mark own messages read', () => commit(alice.token, [{
      update: { name: `${root}/conversations/${roomId}`, fields: { unreadCounts: map({ [alice.uid]: n(0) }) } },
      updateMask: { fieldPaths: [path('unreadCounts', alice.uid)] },
      updateTransforms: [time('updatedAt'), time(path('lastReadAt', alice.uid))],
    }]));
    for (const hidden of [true, false]) {
      const id = await fixture({ hidden });
      await check(hidden ? 'reopen hidden conversation' : 'reopen already visible conversation', () => commit(alice.token, [{
        update: { name: `${root}/conversations/${id}`, fields: { hiddenFor: map({ [alice.uid]: b(false) }) } },
        updateMask: { fieldPaths: [path('hiddenFor', alice.uid)] }, updateTransforms: [time('updatedAt')],
      }]));
    }
    for (const previousText of ['Earlier message', 'ยกเลิกข้อความนี้']) {
      const id = await fixture({ previousType: 'text', previousText });
      await check(`unsend latest: ${previousText}`, () => commit(alice.token, [{
        update: { name: `${root}/conversations/${id}/messages/previous`, fields: { type: s('deleted'), text: s('ยกเลิกข้อความนี้') } },
        updateMask: { fieldPaths: ['type', 'text', 'mediaPath'] }, updateTransforms: [time('deletedAt')],
      }, {
        update: { name: `${root}/conversations/${id}`, fields: { lastMessageText: s('ยกเลิกข้อความนี้'), lastMessageType: s('deleted') } },
        updateMask: { fieldPaths: ['lastMessageText', 'lastMessageType'] }, updateTransforms: [time('updatedAt')],
      }]));
    }
  }
  const readId = await fixture({ previousType: 'text' });
  await check('peer can read chat messages', () => read(bob.token, `conversations/${readId}/messages`));
  await check('nonparticipant cannot read chat messages', () => read(outsider.token, `conversations/${readId}/messages`), 403);
  console.log(`${label}: ${results.filter((r) => r.passed).length}/${results.length} passed\n`);
  reports.push({ label, results });
}

const current = await readFile('firestore.rules', 'utf8');
if (diagnostic) {
  const brokenRules = execFileSync('git', ['show', '7f50d79:firestore.rules'], { encoding: 'utf8' });
  await suite('regression in commit 7f50d79', brokenRules);
  const oldRules = execFileSync('git', ['show', '778fe86:firestore.rules'], { encoding: 'utf8' });
  await suite('previous commit 778fe86 + previous send fields', oldRules, true);
}
await suite('current working tree', current);
await mkdir('build/chat_diagnostics', { recursive: true });
await writeFile('build/chat_diagnostics/results.json', JSON.stringify({ projectId, reports }, null, 2));
// Restore emulator's original rules even in diagnostic mode.
await loadRules(current);
const selected = reports.at(-1);
process.exitCode = selected.results.some((r) => !r.passed) ? 1 : 0;
