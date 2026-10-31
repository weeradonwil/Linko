import { FieldPath, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';

// Bangkok ยังใช้ Firestore trigger ผ่าน Functions API ไม่ได้ จึงอ่านงานทีละหน้าแทน
// checkpoint ขยับเมื่อทำครบหน้าเท่านั้น งานแต่ละชิ้นต้องทำซ้ำได้โดยไม่เกิดผลซ้ำ
export async function scanWork(db, name, collection, timeField, handle, {pageSize=100,maxPages=4}={}) {
  const security = (await db.doc('app_config/security').get()).data();
  const rollout = security?.rolloutAt;
  if (!(rollout instanceof Timestamp) || security.reportBackendRequired !== true) return {processed:0,reason:'not-activated'};
  const ref = db.doc(`backend_cursors/${name}`);
  const owner = randomUUID();
  const position = await db.runTransaction(async tx => {
    const current = await tx.get(ref);
    const data = current.data();
    if (data?.leaseUntil?.toMillis() > Date.now()) return null;
    tx.set(ref,{leaseOwner:owner,leaseUntil:Timestamp.fromMillis(Date.now()+240000)},{merge:true});
    return {at:data?.lastAt,id:data?.lastId};
  });
  if (!position) return {processed:0,reason:'already-running'};
  let processed=0;
  try {
    for(let pageNumber=0;pageNumber<maxPages;pageNumber++) {
      let query=db.collection(collection).where(timeField,'>=',rollout).orderBy(timeField).orderBy(FieldPath.documentId()).limit(pageSize);
      if(position.at && position.id) query=query.startAfter(position.at,position.id);
      const page=await query.get();
      if(page.empty) break;
      for(const doc of page.docs) { await handle(doc); processed++; }
      const last=page.docs.at(-1);
      position.at=last.get(timeField); position.id=last.id;
      const saved=await db.runTransaction(async tx => {
        const current=await tx.get(ref);
        // ถ้า lease เปลี่ยนเจ้าของไปแล้ว ห้ามเขียน checkpoint เก่าย้อนทับของรอบใหม่
        if(current.data()?.leaseOwner !== owner) return false;
        tx.set(ref,{lastAt:position.at,lastId:position.id,updatedAt:FieldValue.serverTimestamp(),leaseUntil:Timestamp.fromMillis(Date.now()+240000)},{merge:true});
        return true;
      });
      if(!saved || page.size<pageSize) break;
    }
    return {processed};
  } finally {
    await db.runTransaction(async tx => {
      const current=await tx.get(ref);
      if(current.data()?.leaseOwner === owner) tx.update(ref,{leaseOwner:FieldValue.delete(),leaseUntil:FieldValue.delete()});
    });
  }
}
