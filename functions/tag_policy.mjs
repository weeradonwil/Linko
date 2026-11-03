// Shared pure checks keep account-tag validation easy to test without Firebase.
export function isValidTaggedUserIds(actorId, ids) {
  return Array.isArray(ids) && ids.length <= 10 &&
    ids.every(value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value)) &&
    new Set(ids).size === ids.length && !ids.includes(actorId);
}

export function newlyTaggedUserIds(before, after) {
  const previous = new Set(Array.isArray(before?.taggedUserIds) ? before.taggedUserIds : []);
  return [...new Set(Array.isArray(after?.taggedUserIds) ? after.taggedUserIds : [])]
    .filter(uid => typeof uid === 'string' && !previous.has(uid));
}
