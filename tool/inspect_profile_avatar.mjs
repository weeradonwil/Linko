import { firebaseRest } from '../functions/firebase-cli-token.mjs';

// Read only the avatar migration fields; keep names and image URLs out of logs.
const [project, uid] = process.argv.slice(2);
if (!/^[a-z0-9-]+$/.test(project ?? '') || !/^[A-Za-z0-9_-]+$/.test(uid ?? '')) {
  throw Error('Pass project ID and UID');
}
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const user = await firebaseRest(`${base}/users/${uid}`);
const fields = user.fields ?? {};
console.log(JSON.stringify({
  private: fields.isPrivate?.booleanValue ?? null,
  hasFullAvatar: !!fields.avatarPath?.stringValue,
  hasThumbnail: !!fields.avatarThumbPath?.stringValue,
  secured: fields.avatarPrivateSecured?.booleanValue ?? null,
  migrationTarget: fields.privacyMigrationTarget?.booleanValue ?? null,
}));
