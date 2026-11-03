import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { firebaseRest } from '../functions/firebase-cli-token.mjs';

// Read-only check for a partial Rules deploy. Print hashes, never rule content.
const project = process.argv[2];
if (!project || !/^[a-z0-9-]+$/.test(project)) throw Error('Pass a Firebase project ID');
const hash = value => createHash('sha256').update(value.replaceAll('\r\n', '\n')).digest('hex');
const local = {
  firestore: hash(await readFile('firestore.rules', 'utf8')),
  storage: hash(await readFile('storage.rules', 'utf8')),
};
const releases = await firebaseRest(`https://firebaserules.googleapis.com/v1/projects/${project}/releases`);
for (const release of releases.releases ?? []) {
  const kind = release.name.includes('cloud.firestore') ? 'firestore'
    : release.name.includes('firebase.storage') ? 'storage' : null;
  if (!kind) continue;
  const ruleset = await firebaseRest(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  console.log(JSON.stringify({ kind, release: release.name,
    matches: ruleset.source.files.some(file => hash(file.content) === local[kind]),
    ruleset: release.rulesetName }));
}
