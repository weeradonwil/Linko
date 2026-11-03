import { firebaseRest } from '../functions/firebase-cli-token.mjs';

// Read-only worker checkpoint check; does not expose post or user content.
const project = process.argv[2];
if (!/^[a-z0-9-]+$/.test(project ?? '')) throw Error('Pass project ID');
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
for (const name of ['tag_feed_created', 'tag_feed_updated', 'tag_group_created', 'tag_group_updated']) {
  const cursor = await firebaseRest(`${base}/backend_cursors/${name}`, { optional: true });
  console.log(JSON.stringify({ name, exists: !!cursor,
    updatedAt: cursor?.fields?.updatedAt?.timestampValue ?? null,
    leaseUntil: cursor?.fields?.leaseUntil?.timestampValue ?? null }));
}
