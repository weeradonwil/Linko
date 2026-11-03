import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { cliAccessToken, firebaseRest } from '../functions/firebase-cli-token.mjs';

// One-time migration for old avatars. Dry-run is the default. It never changes
// avatarPath, names or account privacy and writes only missing small previews.
const [project, mode] = process.argv.slice(2);
if (!/^[a-z0-9-]+$/.test(project ?? '') || ![undefined, '--apply'].includes(mode)) {
  throw Error('Usage: node tool/backfill_profile_thumbnails.mjs PROJECT [--apply]');
}
const apply = mode === '--apply';
const bucket = `${project}.firebasestorage.app`;
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const token = await cliAccessToken();
const auth = { Authorization: `Bearer ${token}` };
const objectUrl = path => `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(path)}`;
async function request(url, options = {}) {
  const response = await fetch(url, { ...options,
    headers: { ...auth, ...options.headers }, signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw Error(`${options.method ?? 'GET'} HTTP ${response.status} ${url.split('?')[0]}`);
  return response;
}
let pageToken;
const profiles = [];
do {
  const query = new URLSearchParams({ pageSize: '100', ...(pageToken ? { pageToken } : {}) });
  const page = await firebaseRest(`${base}/users?${query}`);
  profiles.push(...(page.documents ?? []));
  pageToken = page.nextPageToken;
} while (pageToken);
const candidates = profiles.filter(profile => {
  const uid = profile.name.split('/').at(-1);
  const path = profile.fields?.avatarPath?.stringValue;
  return typeof path === 'string' && path.startsWith(`profile_images/${uid}/`) &&
    !profile.fields?.avatarThumbPath?.stringValue;
});
console.log(JSON.stringify({ project, profiles: profiles.length, missingThumbnails: candidates.length, mode: apply ? 'apply' : 'dry-run' }));
if (apply) {
let done = 0;
for (const profile of candidates) {
  const uid = profile.name.split('/').at(-1);
  const fullPath = profile.fields.avatarPath.stringValue;
  const isPrivate = profile.fields.isPrivate?.booleanValue === true;
  const thumbPath = `profile_thumbnails/${uid}/avatar_backfill_${Date.now()}_${randomUUID()}.png`;
  try {
    const full = await request(`${objectUrl(fullPath)}?alt=media`);
    const source = Buffer.from(await full.arrayBuffer());
    if (source.length > 5 * 1024 * 1024) throw Error('Full avatar exceeds 5 MiB');
    const resized = spawnSync('python', ['tool/resize_avatar.py'],
      { input: source, maxBuffer: 2 * 1024 * 1024 });
    if (resized.status !== 0 || !resized.stdout?.length || resized.stdout.length > 1024 * 1024) {
      throw Error(`Thumbnail resize failed: ${resized.stderr?.toString().slice(0, 200)}`);
    }
    const upload = new URL(`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o`);
    upload.searchParams.set('uploadType', 'media');
    upload.searchParams.set('name', thumbPath);
    upload.searchParams.set('ifGenerationMatch', '0');
    await request(upload, { method: 'POST', headers: { 'Content-Type': 'image/png' }, body: resized.stdout });
    await request(objectUrl(thumbPath), { method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ metadata: { firebaseStorageDownloadTokens: randomUUID() } }) });
    const patch = new URL(`${base}/users/${uid}`);
    patch.searchParams.append('updateMask.fieldPaths', 'avatarThumbPath');
    patch.searchParams.set('currentDocument.updateTime', profile.updateTime);
    await request(patch, { method: 'PATCH', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: { avatarThumbPath: { stringValue: thumbPath } } }) });
    if (isPrivate) {
      // Rotate any URL token issued while the account was public.
      await request(objectUrl(fullPath), { method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ metadata: { firebaseStorageDownloadTokens: randomUUID() } }) });
      const secured = new URL(`${base}/users/${uid}`);
      secured.searchParams.append('updateMask.fieldPaths', 'avatarPrivateSecured');
      await request(secured, { method: 'PATCH', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields: { avatarPrivateSecured: { booleanValue: true } } }) });
    }
    done++;
    console.log(JSON.stringify({ migrated: done, private: isPrivate }));
  } catch (error) {
    // Keep the uploaded thumbnail if the profile now points to it. A later
    // retry can still finish token rotation without harming the current image.
    console.error(JSON.stringify({ failedUid: uid, reason: String(error) }));
  }
}
console.log(JSON.stringify({ migrated: done, attempted: candidates.length }));
if (done !== candidates.length) process.exitCode = 1;
}
