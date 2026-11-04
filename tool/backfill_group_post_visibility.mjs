// เติมเฉพาะ groupVisibility ให้โพสต์เก่า ไม่เปลี่ยนเนื้อหา เวลา สื่อ หรือสมาชิก
// ค่าเริ่มต้นเป็นตรวจอย่างเดียว ใช้ --apply หลังตรวจแผนและสำรองไว้ใน receipt แล้ว
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { firebaseRest } from '../functions/firebase-cli-token.mjs';

const project = process.argv.find(arg => arg.startsWith('--project='))?.slice(10);
if (!project || !/^[a-z][a-z0-9-]+$/.test(project)) throw new Error('Specify --project=PROJECT_ID');
const apply = process.argv.includes('--apply');
const receiptPath = resolve(process.argv.find(arg => arg.startsWith('--receipt='))?.slice(10)
  ?? `build/public-group-access/${apply ? 'migration-applied' : 'migration-plan'}.json`);
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const receipt = { project, apply, startedAt: new Date().toISOString(), groups: 0, posts: 0, changes: [], applied: [] };
await mkdir(dirname(receiptPath), { recursive: true });
async function save() { await writeFile(receiptPath, JSON.stringify(receipt, null, 2) + '\n'); }
async function list(path, fields) {
  const docs = [];
  let token;
  do {
    const query = new URLSearchParams({ pageSize: '500' });
    for (const field of fields) query.append('mask.fieldPaths', field);
    if (token) query.set('pageToken', token);
    const page = await firebaseRest(`${base}/${path}?${query}`);
    docs.push(...(page.documents ?? []));
    token = page.nextPageToken;
  } while (token);
  return docs;
}
try {
  for (const group of await list('groups', ['visibility'])) {
    const visibility = group.fields?.visibility?.stringValue;
    if (!['public', 'private'].includes(visibility)) throw new Error('Invalid group visibility');
    const path = group.name.split('/documents/')[1];
    receipt.groups++;
    for (const post of await list(`${path}/posts`, ['groupVisibility'])) {
      receipt.posts++;
      const previous = post.fields?.groupVisibility;
      if (previous?.stringValue === visibility) continue;
      receipt.changes.push({ path: post.name.split('/documents/')[1], previous: previous ?? null,
        visibility, updateTime: post.updateTime, groupUpdateTime: group.updateTime });
    }
  }
  // บันทึกค่าเดิมและ precondition ทุกโพสต์ก่อนเริ่มเขียน เพื่อทวนสอบและกู้ค่าเฉพาะ field ได้
  await save();
  if (apply) {
    for (const change of receipt.changes) {
      const groupPath = change.path.split('/posts/')[0];
      const group = await firebaseRest(`${base}/${groupPath}?mask.fieldPaths=visibility`);
      if (group.updateTime !== change.groupUpdateTime || group.fields.visibility.stringValue !== change.visibility) {
        throw new Error('Group changed during migration; inspect receipt before retrying');
      }
      const query = new URLSearchParams({ 'updateMask.fieldPaths': 'groupVisibility', 'currentDocument.updateTime': change.updateTime });
      const updated = await firebaseRest(`${base}/${change.path}?${query}`, {
        method: 'PATCH', body: { fields: { groupVisibility: { stringValue: change.visibility } } },
      });
      receipt.applied.push({ path: change.path, updateTime: updated.updateTime });
      await save();
    }
  }
  receipt.finishedAt = new Date().toISOString();
  await save();
  console.log(JSON.stringify({ project, apply, groups: receipt.groups, posts: receipt.posts,
    planned: receipt.changes.length, applied: receipt.applied.length, receiptPath }));
} catch (error) {
  receipt.error = error.message;
  await save();
  throw error;
}
