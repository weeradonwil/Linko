// REST helpers restricted to local demo projects, never production.
export const projectId = process.env.GCLOUD_PROJECT ?? 'demo-linko';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const storageHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '127.0.0.1:9199';
if (!projectId.startsWith('demo-') || [authHost, firestoreHost, storageHost].some(host => !/^(127\.0\.0\.1|localhost):\d+$/.test(host))) {
  throw new Error('Tests require a local Firebase Emulator and a demo-* project.');
}
export const s = value => ({ stringValue: value });
export const n = value => ({ integerValue: String(value) });
export const b = value => ({ booleanValue: value });
export const m = fields => ({ mapValue: { fields } });
export const a = values => ({ arrayValue: { values } });
export const stamp = fieldPath => ({ fieldPath, setToServerValue: 'REQUEST_TIME' });
export const field = (name, uid) => `${name}.\`${uid}\``;
export const documentName = path => `projects/${projectId}/databases/(default)/documents/${path}`;
const firestoreBase = `http://${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents`;
export function assert(condition, message) { if (!condition) throw new Error(message); }
export function allowed(result, message) { assert(result.ok, `${message}: ${JSON.stringify(result.body)}`); }
export function denied(result, message) {
  assert(result.status === 403, `${message}: expected 403, got ${result.status}: ${JSON.stringify(result.body)}`);
}
export async function request(path, { token, method = 'GET', body } = {}) {
  const response = await fetch(firestoreBase + path, {
    method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await response.text();
  return { ok: response.ok, status: response.status, body: text ? JSON.parse(text) : null };
}
export const commit = (token, writes) => request(':commit', { token, method: 'POST', body: { writes } });
export const get = (token, path) => request('/' + path, { token });
export function write(path, fields, { timestamps = [], mask, exists, increments = [] } = {}) {
  return {
    update: { name: documentName(path), fields },
    ...(mask ? { updateMask: { fieldPaths: mask } } : {}),
    ...((timestamps.length || increments.length) ? { updateTransforms: [...timestamps.map(stamp), ...increments] } : {}),
    ...(exists === undefined ? {} : { currentDocument: { exists } }),
  };
}
export async function createUser() {
  const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator-api-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = await response.json();
  assert(response.ok, `Create emulator user: ${JSON.stringify(body)}`);
  return { uid: body.localId, token: body.idToken };
}
export async function createProfile(user, name = 'Emulator member', isPrivate = false) {
  allowed(await commit(user.token, [write(`users/${user.uid}`, {
    uid: s(user.uid), displayName: s(name), displayNameLower: s(name.toLowerCase()), bio: s(''), isPrivate: b(isPrivate),
  }, { timestamps: ['createdAt', 'updatedAt'], exists: false })]), 'Create profile');
}
export async function follow(user, target) {
  allowed(await commit(user.token, [
    write(`users/${target.uid}/followers/${user.uid}`, { uid: s(user.uid) }, { timestamps: ['createdAt'] }),
    write(`users/${user.uid}/following/${target.uid}`, { uid: s(target.uid) }, { timestamps: ['createdAt'] }),
  ]), 'Follow');
}
// Unsigned claims below are accepted only by the Emulator.
export function adminToken(user) {
  const parts = user.token.split('.');
  const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
  payload.admin = true;
  return `${parts[0]}.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.${parts[2]}`;
}
export async function storage(token, path, { method = 'GET', bytes, contentType = 'image/png' } = {}) {
  const base = `http://${storageHost}/v0/b/${projectId}.appspot.com/o`;
  const url = method === 'POST' ? `${base}?name=${encodeURIComponent(path)}` : `${base}/${encodeURIComponent(path)}`;
  const response = await fetch(url, {
    method, headers: { Authorization: `Firebase ${token}`, ...(bytes ? { 'Content-Type': contentType } : {}) }, ...(bytes ? { body: bytes } : {}),
  });
  const text = await response.text();
  let body;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  return { ok: response.ok, status: response.status, body };
}
