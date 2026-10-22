// Regression tests for consecutive messages, visibility, permissions and unsend.
import { createUser, createProfile, follow, commit, get, write, s, n, b, m, a,
  field, allowed, denied, assert } from './emulator_test_support.mjs';

const sender = await createUser(), recipient = await createUser(), outsider = await createUser();
for (const user of [sender, recipient, outsider]) await createProfile(user);
const room = `conversations/chat_regression_${Date.now()}`;
const ids = [sender.uid, recipient.uid].sort();
function createRoom(path = room, unread = m({ [sender.uid]: n(0), [recipient.uid]: n(0) })) {
  return write(path, {
    participantIds: a(ids.map(s)), participantNames: m({ [sender.uid]: s('Sender'), [recipient.uid]: s('Recipient') }),
    unreadCounts: unread, lastReadAt: m({}),
  }, { timestamps: ['createdAt', 'updatedAt', field('lastReadAt', sender.uid)], exists: false });
}
denied(await commit(sender.token, [createRoom()]), 'A new DM requires an approved follow');
await follow(sender, recipient);
denied(await commit(sender.token, [createRoom(room + '_bad', m({ [sender.uid]: n(0), [recipient.uid]: s('bad') }))]), 'Reject malformed counters');
allowed(await commit(sender.token, [createRoom()]), 'Create followed conversation');
function sendWrites(actor, peer, id, text) {
  return [
    write(`${room}/messages/${id}`, { senderId: s(actor.uid), type: s('text'), text: s(text) }, { timestamps: ['createdAt'], exists: false }),
    write(room, {
      lastMessageText: s(text), lastMessageType: s('text'), lastMessageSenderId: s(actor.uid), lastMessageId: s(id),
      unreadCounts: m({ [actor.uid]: n(0) }), hiddenFor: m({ [actor.uid]: b(false), [peer.uid]: b(false) }),
    }, {
      mask: ['lastMessageText', 'lastMessageType', 'lastMessageSenderId', 'lastMessageId', field('unreadCounts', actor.uid), field('hiddenFor', actor.uid), field('hiddenFor', peer.uid)],
      timestamps: ['lastMessageAt', 'updatedAt', field('lastReadAt', actor.uid)],
      increments: [{ fieldPath: field('unreadCounts', peer.uid), increment: n(1) }],
    }),
  ];
}
allowed(await commit(sender.token, sendWrites(sender, recipient, 'first', 'Hello')), 'First message');
allowed(await commit(sender.token, sendWrites(sender, recipient, 'second', 'Hello')), 'Repeated text/type/sender');
allowed(await commit(recipient.token, sendWrites(recipient, sender, 'reply', 'Reply')), 'Reply with the same type');
for (let i = 0; i < 2; i++) {
  allowed(await commit(sender.token, [write(room, { hiddenFor: m({ [sender.uid]: b(false) }) }, {
    mask: [field('hiddenFor', sender.uid)], timestamps: ['updatedAt'],
  })]), 'Idempotent reopen');
}
allowed(await commit(recipient.token, [write(room, { hiddenFor: m({ [recipient.uid]: b(true) }) }, {
  mask: [field('hiddenFor', recipient.uid)], timestamps: ['updatedAt'],
})]), 'Hide own room');
denied(await commit(sender.token, [write(room, { hiddenFor: m({ [recipient.uid]: b(false) }) }, {
  mask: [field('hiddenFor', recipient.uid)], timestamps: ['updatedAt'],
})]), 'Peer visibility cannot change without a new message');
allowed(await commit(sender.token, sendWrites(sender, recipient, 'after_hidden', 'New message')), 'New message resurfaces a hidden room');
const state = await get(recipient.token, room);
assert(state.body.fields.hiddenFor.mapValue.fields[recipient.uid].booleanValue === false, 'Recipient room must reappear');
allowed(await commit(sender.token, sendWrites(sender, recipient, 'cancel', 'ยกเลิกข้อความนี้')), 'Send cancellation-like text');
allowed(await commit(sender.token, [
  write(`${room}/messages/cancel`, { type: s('deleted'), text: s('ยกเลิกข้อความนี้') }, {
    mask: ['type', 'text', 'mediaPath', 'deletedAt'], timestamps: ['deletedAt'],
  }),
  write(room, { lastMessageText: s('ยกเลิกข้อความนี้'), lastMessageType: s('deleted') }, {
    mask: ['lastMessageText', 'lastMessageType'], timestamps: ['updatedAt'],
  }),
]), 'Unsend even if the preview text stays unchanged');
denied(await get(outsider.token, room), 'Outsider cannot read conversation');
denied(await commit(outsider.token, sendWrites(outsider, recipient, 'intrusion', 'No')), 'Outsider cannot send');
denied(await commit(sender.token, [write(`${room}/messages/without_summary`, {
  senderId: s(sender.uid), type: s('text'), text: s('Unread bypass'),
}, { timestamps: ['createdAt'] })]), 'Message must update its summary atomically');
// Admin seed represents a legacy document created before schema validation.
allowed(await commit('owner', [write(room, { unreadCounts: m({
  [sender.uid]: n(0), [recipient.uid]: s('legacy-string'),
}) }, { mask: ['unreadCounts'] })]), 'Seed old non-numeric unread counter');
allowed(await commit(sender.token, sendWrites(sender, recipient, 'legacy_counter', 'Recovered')),
  'Atomic increment repairs a legacy non-numeric recipient counter');
const repaired = await get(recipient.token, room);
assert(repaired.body.fields.unreadCounts.mapValue.fields[recipient.uid].integerValue === '1',
  'Legacy counter resumes at one unread message');
console.log('PASS chat: follow gate, schema, repeated messages, reply, reopen, hidden room, unsend, outsider and atomic summary');
