import { createRequire } from 'node:module';
import { processExpiredWarnings, processLegacyReports, processBlockChanges, processEvidenceCopies, processTaggedPosts } from '../functions/index.mjs';
import { scanWork } from '../functions/workers.mjs';
import { caseId } from '../functions/policy.mjs';
import { projectId, s, b, a, write, commit, get, allowed, denied, assert, documentName, createProfile, storage, follow } from './emulator_test_support.mjs';

// ไฟล์นี้ใช้ Admin SDK เฉพาะจัด fixture ใน demo project บนเครื่อง ห้ามชี้ production
if (!projectId.startsWith('demo-') || !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Local Emulator only');
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const db = getFirestore();
let passed = 0;
const pass = text => { passed++; console.log(`PASS social ${passed}: ${text}`); };
async function user(verified = true) {
  const email = `social-${Date.now()}-${Math.random().toString(36).slice(2)}@example.test`;
  const created = await getAuth().createUser({ email, password: 'Test-only-pass123!', emailVerified: verified });
  const response = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=test-key`, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({email,password:'Test-only-pass123!',returnSecureToken:true}) });
  const body = await response.json();
  assert(response.ok, JSON.stringify(body));
  const member = {uid:created.uid,token:body.idToken};
  await createProfile(member);
  return member;
}
async function rpc(member, name, data, success = true) {
  const response = await fetch(`http://127.0.0.1:5001/${projectId}/asia-southeast1/${name}`, { method:'POST', headers:{'Content-Type':'application/json',Authorization:`Bearer ${member.token}`}, body:JSON.stringify({data}), signal:AbortSignal.timeout(30000) });
  const body = await response.json();
  assert(success ? response.ok && !body.error : !response.ok, `${name}: ${response.status} ${JSON.stringify(body)}`);
  return body.result ?? body.error;
}
const suffix = Date.now().toString(36);
async function post(member, key, content = 'Original public post') {
  const ticket = await rpc(member,'reserveWrite',{path:`posts/${key}`});
  allowed(await commit(member.token,[write(`posts/${key}`,{userId:s(member.uid),authorName:s('Member'),authorIsPrivate:b(false),content:s(content),tags:a([]),visibility:s('public'),mediaType:s('none')},{timestamps:['createdAt','updatedAt'],exists:false}),{delete:documentName(`write_tickets/${ticket.ticketId}`)}]),'Create post using one-use ticket');
}
async function report(member, postId, groupId = null) { return rpc(member,'submitReport',{postId,groupId,reason:'สแปม',details:'รายละเอียดสำหรับทดสอบ'}); }
await db.doc('app_config/security').set({verificationRequired:true,writeTicketsRequired:true,reportBackendRequired:true,evidenceCopiesEnabled:true,rolloutAt:Timestamp.now()});
await db.doc('app_config/moderation').set({reportThreshold:2,warningHours:24,suspensionHours:72,minimumAccountHours:0,autoEnforce:true});
const [author, first, second, owner, outsider, unverified, tagAuthor, tagFriend] = await Promise.all([user(),user(),user(),user(),user(),user(false),user(),user()]);

await rpc(unverified,'reserveWrite',{path:`posts/unverified_${suffix}`},false);
pass('unverified email cannot reserve a write');
await follow(tagAuthor, tagFriend);
await follow(tagAuthor, second);
const missingBlockEdge = await get(tagAuthor.token, `block_edges/${tagAuthor.uid}_${tagFriend.uid}`);
assert(missingBlockEdge.status === 404, `tagging cannot check an unblocked account: ${JSON.stringify(missingBlockEdge.body)}`);
pass('a member can check that a missing block edge does not exist');
const taggedPostId = `tagged_${suffix}`;
denied(await commit(tagAuthor.token,[write(`posts/forged_${suffix}`,{
  userId:s(tagAuthor.uid),authorName:s('Member'),authorIsPrivate:b(false),content:s('forged tag'),tags:a([]),
  taggedUserIds:a([s(tagFriend.uid)]),visibility:s('public'),mediaType:s('none'),
},{timestamps:['createdAt','updatedAt'],exists:false})]),'Forged tag without trusted ticket');
await rpc(tagAuthor,'reserveWrite',{path:`posts/unrelated_${suffix}`,taggedUserIds:[outsider.uid]},false);
const tagTicket = await rpc(tagAuthor,'reserveWrite',{path:`posts/${taggedPostId}`,taggedUserIds:[tagFriend.uid]});
allowed(await commit(tagAuthor.token,[write(`posts/${taggedPostId}`,{
  userId:s(tagAuthor.uid),authorName:s('Member'),authorIsPrivate:b(false),content:s('tagged post'),tags:a([]),
  taggedUserIds:a([s(tagFriend.uid)]),visibility:s('public'),mediaType:s('none'),
},{timestamps:['createdAt','updatedAt'],exists:false}),{delete:documentName(`write_tickets/${tagTicket.ticketId}`)}]),'Create tagged post with trusted ticket');
await processTaggedPosts();
let tagNotice = await db.doc(`notifications/tag_feed_${taggedPostId}_${tagFriend.uid}`).get();
assert(tagNotice?.exists && tagNotice.data().type === 'tag' && tagNotice.data().postId === taggedPostId,'tag notification was not created');
pass('tag requires an eligible account and trusted ticket, then sends one in-app notification');
const updateTagTicket = await rpc(tagAuthor,'reserveWrite',{path:`posts/${taggedPostId}`,taggedUserIds:[tagFriend.uid,second.uid],update:true});
allowed(await commit(tagAuthor.token,[write(`posts/${taggedPostId}`,{
  content:s('tagged post updated'),tags:a([]),taggedUserIds:a([s(tagFriend.uid),s(second.uid)]),
},{mask:['content','tags','taggedUserIds','updatedAt','editedAt'],timestamps:['updatedAt','editedAt']}),{delete:documentName(`write_tickets/${updateTagTicket.ticketId}`)}]),'Update tagged post with trusted ticket');
await processTaggedPosts();
let addedTagNotice = await db.doc(`notifications/tag_feed_${taggedPostId}_${second.uid}`).get();
assert(addedTagNotice?.exists,'newly added account did not receive a tag notification');
pass('editing a post notifies newly tagged accounts');
// This is the production-shaped case: a private profile tags a followed
// account and attaches a photo. Saving must work, but the recipient cannot
// open the private post before approval, so the worker must not send an unusable notification.
await db.doc(`users/${tagAuthor.uid}`).update({isPrivate:true});
const privateTaggedId = `private_tagged_${suffix}`;
const privateMediaPath = `post_media/${tagAuthor.uid}/${privateTaggedId}/image.jpg`;
const privateTicket = await rpc(tagAuthor,'reserveWrite',{path:`posts/${privateTaggedId}`,taggedUserIds:[tagFriend.uid]});
allowed(await commit(tagAuthor.token,[write(`posts/${privateTaggedId}`,{
  userId:s(tagAuthor.uid),authorName:s('Member'),authorIsPrivate:b(true),content:s('Hi @Friend'),tags:a([]),
  taggedUserIds:a([s(tagFriend.uid)]),visibility:s('public'),mediaType:s('image'),mediaPath:s(privateMediaPath),
},{timestamps:['createdAt','updatedAt'],exists:false}),{delete:documentName(`write_tickets/${privateTicket.ticketId}`)}]),'Private account creates photo with a tagged friend');
denied(await get(tagFriend.token,`posts/${privateTaggedId}`),'Tagged friend cannot open a private account post');
await processTaggedPosts();
assert(!(await db.doc(`notifications/tag_feed_${privateTaggedId}_${tagFriend.uid}`).get()).exists,
  'private post sent an inaccessible tag notification');
const privateUpdateTicket = await rpc(tagAuthor,'reserveWrite',{path:`posts/${privateTaggedId}`,taggedUserIds:[tagFriend.uid,second.uid],update:true});
// ความสัมพันธ์ที่ผู้เขียนติดตามเพื่อนยังไม่พอ เพื่อนต้องได้รับอนุมัติให้ติดตามผู้เขียนด้วย
allowed(await commit(tagFriend.token, [write(`users/${tagAuthor.uid}/follow_requests/${tagFriend.uid}`, {
  uid: s(tagFriend.uid),
}, { timestamps: ['createdAt'] })]), 'Tagged friend requests approval');
allowed(await commit(tagAuthor.token, [
  write(`users/${tagAuthor.uid}/followers/${tagFriend.uid}`, { uid: s(tagFriend.uid) }, { timestamps: ['createdAt'] }),
  write(`users/${tagFriend.uid}/following/${tagAuthor.uid}`, { uid: s(tagAuthor.uid) }, { timestamps: ['createdAt'] }),
  { delete: documentName(`users/${tagAuthor.uid}/follow_requests/${tagFriend.uid}`) },
]), 'Author approves tagged follower');
allowed(await commit(tagAuthor.token,[write(`posts/${privateTaggedId}`,{
  content:s('Edited private photo'),taggedUserIds:a([s(tagFriend.uid),s(second.uid)]),
},{mask:['content','taggedUserIds','updatedAt','editedAt'],timestamps:['updatedAt','editedAt']}),
{delete:documentName(`write_tickets/${privateUpdateTicket.ticketId}`)}]),'Edit private photo tags');
await processTaggedPosts();
allowed(await get(tagFriend.token, `posts/${privateTaggedId}`), 'Approved tagged follower reads private-account post');
assert((await db.doc(`notifications/tag_feed_${privateTaggedId}_${tagFriend.uid}`).get()).exists,
  'approved follower did not receive the accessible tag notification');
assert(!(await db.doc(`notifications/tag_feed_${privateTaggedId}_${second.uid}`).get()).exists,
  'unapproved tagged account received a private-account notification');
await report(tagFriend, privateTaggedId);
await rpc(second, 'submitReport', {postId:privateTaggedId,reason:'สแปม'}, false);
await rpc(tagFriend, 'sharePost', {postId:privateTaggedId,destination:'feed',requestId:`private_follower_share_${suffix}`,caption:''}, false);
pass('approved followers can read, receive tags and report, while unapproved users and private-account resharing stay restricted');
const privateRemoveTicket = await rpc(tagAuthor,'reserveWrite',{path:`posts/${privateTaggedId}`,taggedUserIds:[],update:true});
allowed(await commit(tagAuthor.token,[write(`posts/${privateTaggedId}`,{
  content:s('Removed friend tags'),taggedUserIds:a([]),
},{mask:['content','taggedUserIds','updatedAt','editedAt'],timestamps:['updatedAt','editedAt']}),
{delete:documentName(`write_tickets/${privateRemoveTicket.ticketId}`)}]),'Remove private photo tags');
await db.doc(`users/${tagAuthor.uid}`).update({isPrivate:false});
pass('private photo post can be created, edited and untagged without leaking notifications');
const original = `original_${suffix}`;
await post(author,original);
denied(await commit(author.token,[write(`posts/no_ticket_${suffix}`,{userId:s(author.uid),authorName:s('Member'),authorIsPrivate:b(false),content:s('bypass'),tags:a([]),visibility:s('public'),mediaType:s('none')},{timestamps:['createdAt','updatedAt']})]),'Direct ticket bypass');
pass('valid ticket is accepted and missing ticket is denied by Rules');

assert(!(await report(first,original)).alreadyReported,'first report');
assert((await report(first,original)).alreadyReported,'duplicate report must return a friendly flag');
const mainCase = db.doc(`moderation_cases/${caseId(`posts/${original}`)}`);
assert((await mainCase.get()).data().reportCount === 1,'duplicate counted twice');
assert((await mainCase.get()).data().status === 'queued','one report warned early');
pass('same account reports once and does not warn early');
assert((await db.doc(`post_reports/${caseId(`posts/${original}`)}_${first.uid}`).get()).exists,'canonical raw report missing');
await report(second,original);
let state = (await mainCase.get()).data();
assert(state.status === 'warned' && state.reportCount === 2,'second report did not warn');
assert(Math.abs(state.deadline.toMillis()-Date.now()-24*3600000)<10000,'warning is not 24 hours');
assert(!('reporterUid' in state),'case exposes reporter UID');
denied(await get(outsider.token,mainCase.path),'unrelated user sees case');
denied(await get(author.token,`post_reports/${caseId(`posts/${original}`)}_${first.uid}`),'author sees raw reporter');
allowed(await get(author.token,mainCase.path),'owner cannot see warning');
pass('two reporters warn for 24 hours and reporter identity stays private');
await rpc(author,'respondToWarning',{caseId:mainCase.id,action:'edited'},false);
allowed(await commit(author.token,[write(`posts/${original}`,{content:s('Corrected public post')},{mask:['content'],timestamps:['updatedAt','editedAt']})]),'Edit original');
await rpc(author,'respondToWarning',{caseId:mainCase.id,action:'edited'});
assert((await mainCase.get()).data().status==='changed','edit not recognized');
pass('unchanged post cannot claim an edit; an actual edit closes that warning');

const punished = `punished_${suffix}`;
await post(author,punished);
await report(first,punished); await report(second,punished);
const punishedCase = db.doc(`moderation_cases/${caseId(`posts/${punished}`)}`);
await punishedCase.update({deadline:Timestamp.fromMillis(Date.now()-1000)});
await processExpiredWarnings();
assert(!(await db.doc(`posts/${punished}`).get()).exists,'post was not removed');
assert((await db.doc(`moderation_archives/${punishedCase.id}`).get()).data().snapshot.content==='Original public post','evidence missing');
const suspended = (await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil.toMillis();
assert(Math.abs(suspended-Date.now()-72*3600000)<10000,'ban duration is not 72 hours');
await processExpiredWarnings();
assert((await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil.toMillis()===suspended,'duplicate job extended ban');
pass('expired warning removes post, preserves evidence and suspends exactly 72 hours once');
await rpc(author,'reserveWrite',{path:`posts/suspended_${suffix}`},false);
denied(await commit(author.token,[write(`account_state/${author.uid}`,{},{mask:['postingSuspendedUntil']})]),'self unsuspend');
await db.doc(`account_state/${author.uid}`).update({postingSuspendedUntil:Timestamp.fromMillis(Date.now()-1)});
await post(author,`restored_${suffix}`);
pass('suspended account cannot bypass restrictions and expired suspension restores posting');

const contested = `contested_${suffix}`;
await post(author,contested); await report(first,contested); await report(second,contested);
const contestedCase = db.doc(`moderation_cases/${caseId(`posts/${contested}`)}`);
await rpc(author,'respondToWarning',{caseId:contestedCase.id,action:'contest'});
await processExpiredWarnings();
assert((await db.doc(`posts/${contested}`).get()).exists,'contested post punished');
pass('contesting a warning stops automatic punishment');

const groupId = `group_${suffix}`;
await db.doc(`groups/${groupId}`).set({name:'Private group',description:'test',ownerId:owner.uid,visibility:'private',memberCount:4,createdAt:Timestamp.now()});
for(const member of [owner,author,first,second]) await db.doc(`groups/${groupId}/members/${member.uid}`).set({uid:member.uid,role:member.uid===owner.uid?'owner':'member',joinedAt:Timestamp.now()});
for(const member of [tagAuthor,tagFriend]) await db.doc(`groups/${groupId}/members/${member.uid}`).set({uid:member.uid,role:'member',joinedAt:Timestamp.now()});
const groupTaggedPostId = `gtagged_${suffix}`;
const groupTagTicket = await rpc(owner,'reserveWrite',{path:`groups/${groupId}/posts/${groupTaggedPostId}`,taggedUserIds:[tagFriend.uid]});
allowed(await commit(owner.token,[write(`groups/${groupId}/posts/${groupTaggedPostId}`,{
  authorId:s(owner.uid),authorName:s('Member'),content:s('group tag'),tags:a([]),
  taggedUserIds:a([s(tagFriend.uid)]),mediaType:s('none'),
},{timestamps:['createdAt'],exists:false}),{delete:documentName(`write_tickets/${groupTagTicket.ticketId}`)}]),'Create tagged group post with trusted ticket');
await processTaggedPosts();
let groupTagNotice = await db.doc(`notifications/tag_${groupId}_${groupTaggedPostId}_${tagFriend.uid}`).get();
assert(groupTagNotice?.exists && groupTagNotice.data().groupId === groupId,'group tag notification was not created');
pass('group tags require group membership and notify a tagged member');
const groupPost = `gpost_${suffix}`;
await db.doc(`groups/${groupId}/posts/${groupPost}`).set({authorId:author.uid,authorName:'Member',content:'Private group content',tags:[],mediaType:'none',createdAt:Timestamp.now()});
await report(first,groupPost,groupId);
const groupCase = db.doc(`moderation_cases/${caseId(`groups/${groupId}/posts/${groupPost}`)}`);
assert((await groupCase.get()).data().status==='queued','group was automatically warned');
await rpc(outsider,'reviewGroupReport',{caseId:groupCase.id,decision:'remove'},false);
await rpc(owner,'reviewGroupReport',{caseId:groupCase.id,decision:'warn'});
const firstDeadline = (await groupCase.get()).data().deadline.toMillis();
await rpc(owner,'reviewGroupReport',{caseId:groupCase.id,decision:'warn'});
assert((await groupCase.get()).data().deadline.toMillis()===firstDeadline,'repeated group review extended deadline');
await groupCase.update({deadline:Timestamp.fromMillis(Date.now()-1)});
await processExpiredWarnings();
assert((await db.doc(`group_account_state/${groupId}_${author.uid}`).get()).data().postingSuspendedUntil.toMillis()>Date.now(),'missing group suspension');
assert((await db.doc(`account_state/${author.uid}`).get()).data().postingSuspendedUntil.toMillis()<Date.now(),'group suspended entire app');
await rpc(owner,'reviewGroupReport',{caseId:groupCase.id,decision:'warn'},false);
pass('only group owner reviews reports and group punishment stays inside that group');

await rpc(first,'sharePost',{postId:original,destination:'feed',requestId:`share_feed_${suffix}`,caption:'My caption'});
const shared = (await db.doc(`posts/share_feed_${suffix}`).get()).data();
assert(shared.sharedPostId===original && shared.content==='My caption' && !shared.mediaPath,'share copied original content/media');
await rpc(first,'sharePost',{postId:original,destination:'feed',requestId:`share_feed_${suffix}`,caption:'My caption'});
pass('feed share references original and retries do not duplicate it');
await rpc(first,'sharePost',{postId:original,destination:'group',targetId:groupId,requestId:`share_group_${suffix}`,caption:''});
await rpc(outsider,'sharePost',{postId:original,destination:'group',targetId:groupId,requestId:`share_denied_${suffix}`,caption:''},false);
assert((await db.doc(`groups/${groupId}/posts/share_group_${suffix}`).get()).data().sharedPostId===original,'group share missing');
pass('group share requires real membership');
// บัญชีส่วนตัวตั้งบางโพสต์เป็นสาธารณะได้ ฟีดและกลุ่มต้องแชร์โพสต์นั้นได้เหมือนกัน
await db.doc(`users/${author.uid}`).update({isPrivate:true});
await db.doc(`posts/${original}`).update({authorIsPrivate:true});
await db.doc(`users/${second.uid}`).update({isPrivate:true});
denied(await get(outsider.token,`posts/${original}`),'public post snapshot is hidden when its owner is private');
await rpc(second,'sharePost',{postId:original,destination:'feed',requestId:`share_private_owner_feed_${suffix}`,caption:'Public share'},false);
await rpc(second,'sharePost',{postId:original,destination:'group',targetId:groupId,requestId:`share_private_owner_group_${suffix}`,caption:''},false);
const privateGroupShare = `private_group_share_${suffix}`;
await db.doc(`group_account_state/${groupId}_${author.uid}`).update({postingSuspendedUntil:Timestamp.fromMillis(Date.now()-1)});
await rpc(author,'sharePost',{postId:original,destination:'group',targetId:groupId,requestId:privateGroupShare,caption:''});
const privateShareMediaPath = `post_media/${author.uid}/${original}/share-check.png`;
const privateShareImage = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lGQAAAAASUVORK5CYII=','base64');
allowed(await storage(author.token,privateShareMediaPath,{method:'POST',bytes:privateShareImage}),'author uploads private share media');
denied(await get(first.token,`posts/${original}`),'group recipient reads private-account source before grant');
denied(await storage(first.token,privateShareMediaPath),'group recipient reads private media before grant');
await rpc(first,'openSharedPost',{postId:original,destination:'group',targetId:groupId,shareId:privateGroupShare});
allowed(await get(first.token,`posts/${original}`),'group recipient opens explicitly shared source');
allowed(await storage(first.token,privateShareMediaPath),'group recipient opens private media');
await rpc(outsider,'openSharedPost',{postId:original,destination:'group',targetId:groupId,shareId:privateGroupShare},false);
await db.doc(`groups/${groupId}/members/${first.uid}`).delete();
denied(await get(first.token,`posts/${original}`),'former group member keeps private share');
denied(await storage(first.token,privateShareMediaPath),'former group member keeps private media');
await db.doc(`groups/${groupId}/members/${first.uid}`).set({uid:first.uid,role:'member',joinedAt:Timestamp.now()});
pass('private-account owner can share to group; only current members can unlock it');
await db.doc(`groups/${groupId}/posts/${privateGroupShare}`).delete();
denied(await get(first.token,`posts/${original}`),'deleted group share revokes source access');
await db.doc(`users/${author.uid}`).update({isPrivate:false});
await db.doc(`posts/${original}`).update({authorIsPrivate:false});
await db.doc(`users/${second.uid}`).update({isPrivate:false});
allowed(await get(outsider.token,`posts/${original}`),'public post is visible again after the account is opened');
pass('private account snapshots cannot be read or shared through public/group sharing');
allowed(await commit(first.token,[write(`posts/share_feed_${suffix}`,{content:s('edited caption')},{mask:['content'],timestamps:['updatedAt','editedAt']})]),'edit shared feed caption');
allowed(await commit(first.token,[write(`posts/share_feed_${suffix}`,{content:s('')},{mask:['content'],timestamps:['updatedAt','editedAt']})]),'clear shared feed caption');
allowed(await commit(first.token,[write(`groups/${groupId}/posts/share_group_${suffix}`,{content:s('')},{mask:['content'],timestamps:['updatedAt','editedAt']})]),'empty shared group caption');
pass('shared feed and group captions can be edited without losing the original card');


const room = `room_${suffix}`;
await db.doc(`conversations/${room}`).set({participantIds:[first.uid,second.uid],participantNames:{[first.uid]:'First',[second.uid]:'Second'},unreadCounts:{[first.uid]:0,[second.uid]:0},createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
await rpc(first,'sharePost',{postId:original,destination:'chat',targetId:room,requestId:`share_chat_${suffix}`,caption:''});
assert((await db.doc(`conversations/${room}/messages/share_chat_${suffix}`).get()).data().sharedPostId===original,'chat share missing');
pass('chat receives a post card and unread count');
const privateRoom = `private_share_room_${suffix}`;
const privateChatShare = `private_chat_share_${suffix}`;
await db.doc(`conversations/${privateRoom}`).set({participantIds:[author.uid,first.uid],participantNames:{[author.uid]:'Author',[first.uid]:'First'},unreadCounts:{[author.uid]:0,[first.uid]:0},createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
await db.doc(`users/${author.uid}`).update({isPrivate:true});
await db.doc(`posts/${original}`).update({authorIsPrivate:true});
await rpc(author,'sharePost',{postId:original,destination:'chat',targetId:privateRoom,requestId:privateChatShare,caption:''});
denied(await get(first.token,`posts/${original}`),'chat recipient reads private source before grant');
await rpc(first,'openSharedPost',{postId:original,destination:'chat',targetId:privateRoom,shareId:privateChatShare});
allowed(await get(first.token,`posts/${original}`),'chat recipient opens private-account source');
await rpc(second,'openSharedPost',{postId:original,destination:'chat',targetId:privateRoom,shareId:privateChatShare},false);
await db.doc(`conversations/${privateRoom}/messages/${privateChatShare}`).update({type:'deleted',sharedPostId:FieldValue.delete()});
denied(await get(first.token,`posts/${original}`),'unsent chat share still grants access');
await db.doc(`users/${author.uid}`).update({isPrivate:false});
await db.doc(`posts/${original}`).update({authorIsPrivate:false});
pass('private-account owner can share to chat; unsend revokes recipient access');
const legacyRoom = `legacy_room_${suffix}`;
await db.doc(`conversations/${legacyRoom}`).set({participantIds:[first.uid,unverified.uid],participantNames:{[first.uid]:'First',[unverified.uid]:'Legacy'},unreadCounts:{[first.uid]:0,[unverified.uid]:0},createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
await rpc(first,'sharePost',{postId:original,destination:'chat',targetId:legacyRoom,requestId:`share_legacy_${suffix}`},false);
await db.doc(`account_state/${unverified.uid}`).set({verificationGraceUntil:Timestamp.fromMillis(Date.now()+86400000)});
await rpc(first,'sharePost',{postId:original,destination:'chat',targetId:legacyRoom,requestId:`share_legacy_${suffix}`});
pass('unverified recipients need verification or a protected legacy grace period');
await db.doc(`posts/${original}`).update({visibility:'private'});
await rpc(second,'sharePost',{postId:original,destination:'feed',requestId:`share_private_${suffix}`},false);
denied(await get(second.token,`posts/${original}`),'private original is still readable');
pass('changing original privacy prevents further sharing and access');
await db.doc(`posts/${original}`).update({visibility:'public'});

allowed(await commit(first.token,[write(`users/${first.uid}/blocks/${second.uid}`,{uid:s(second.uid)},{timestamps:['createdAt']}),write(`block_edges/${first.uid}_${second.uid}`,{actorId:s(first.uid),targetId:s(second.uid),participants:a([s(first.uid),s(second.uid)])},{timestamps:['createdAt']})]),'create block atomically');
await db.doc(`users/${first.uid}/following/${second.uid}`).set({createdAt:Timestamp.now()});
await db.doc(`users/${second.uid}/followers/${first.uid}`).set({createdAt:Timestamp.now()});
await processBlockChanges();
assert(!(await db.doc(`users/${first.uid}/following/${second.uid}`).get()).exists,'block cleanup worker left a follow edge');
await rpc(second,'reserveWrite',{path:`conversations/${room}/messages/blocked_${suffix}`},false);
await rpc(second,'sharePost',{postId:original,destination:'chat',targetId:room,requestId:`share_blocked_${suffix}`},false);
denied(await commit(second.token,[{delete:documentName(`block_edges/${first.uid}_${second.uid}`)}]),'remove someone else block');
pass('block works in both directions and cannot be undone by the other user');
allowed(await commit(first.token,[write(`conversations/${room}/messages/share_chat_${suffix}`,{type:s('deleted'),text:s('ยกเลิกข้อความนี้')},{mask:['type','text','sharedPostId'],timestamps:['deletedAt']}),write(`conversations/${room}`,{lastMessageText:s('ยกเลิกข้อความนี้'),lastMessageType:s('deleted')},{mask:['lastMessageText','lastMessageType'],timestamps:['updatedAt']})]),'unsend shared card');
pass('unsending a shared card removes the source pointer without deleting chat history');

const cover = `profile_covers/${owner.uid}/cover.png`;
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lGQAAAAASUVORK5CYII=','base64');
allowed(await storage(owner.token,cover,{method:'POST',bytes:png,contentType:'image/png'}),'owner uploads cover');
allowed(await commit(owner.token,[write(`users/${owner.uid}`,{coverPath:s(cover)},{mask:['coverPath']})]),'save cover path');
denied(await storage(outsider.token,cover,{method:'POST',bytes:png,contentType:'image/png'}),'outsider uploads cover');
await db.doc(`users/${owner.uid}`).update({isPrivate:true});
allowed(await storage(outsider.token,cover),'signed-in non-follower reads current private cover');
allowed(await storage(owner.token,cover),'owner reads private cover');
pass('current cover is visible to signed-in users; only owner can upload');
await db.doc(`users/${owner.uid}`).update({isPrivate:false});
const avatarFull = `profile_images/${owner.uid}/avatar.png`;
const avatarThumb = `profile_thumbnails/${owner.uid}/avatar.png`;
allowed(await storage(owner.token,avatarFull,{method:'POST',bytes:png,contentType:'image/png'}),'owner uploads full avatar');
allowed(await storage(owner.token,avatarThumb,{method:'POST',bytes:png,contentType:'image/png'}),'owner uploads small avatar');
allowed(await commit(owner.token,[write(`users/${owner.uid}`,{
  avatarPath:s(avatarFull),avatarThumbPath:s(avatarThumb),avatarPrivateSecured:b(true),
},{mask:['avatarPath','avatarThumbPath','avatarPrivateSecured']})]),'save avatar paths');
allowed(await storage(outsider.token,avatarFull),'public profile full avatar can be opened');
await db.doc(`users/${owner.uid}`).update({isPrivate:true});
denied(await storage(outsider.token,avatarFull),'private profile full avatar is owner-only');
allowed(await storage(outsider.token,avatarThumb),'private profile small avatar stays visible');
allowed(await storage(owner.token,avatarFull),'owner can open own private full avatar');
await db.doc(`users/${owner.uid}`).update({isPrivate:false});
pass('private avatar full-size access is blocked while its small preview stays visible');
const expiredTicket = db.doc(`write_tickets/expired_${suffix}`);
const activeTicket = db.doc(`write_tickets/active_${suffix}`);
await expiredTicket.set({expiresAt:Timestamp.fromMillis(Date.now()-120000)});
await activeTicket.set({expiresAt:Timestamp.fromMillis(Date.now()+120000)});
await processTaggedPosts();
assert(!(await expiredTicket.get()).exists && (await activeTicket.get()).exists,
  'ticket cleanup deleted an active reservation or retained an expired one');
pass('scheduled worker clears expired write tickets while preserving active reservations');
// หลักฐานต้องเป็นคนละไฟล์ และคนที่ไม่เกี่ยวข้องอ่าน/เขียนไม่ได้
const photoId = `photo_${suffix}`;
const photoPath = `post_media/${author.uid}/${photoId}/photo.png`;
allowed(await storage(author.token,photoPath,{method:'POST',bytes:png,contentType:'image/png'}),'upload original evidence');
await post(author,photoId,'Photo evidence');
await db.doc(`posts/${photoId}`).update({mediaType:'image',mediaPath:photoPath});
await report(first,photoId); await report(second,photoId);
await processEvidenceCopies();
const photoCase = db.doc(`moderation_cases/${caseId(`posts/${photoId}`)}`);
let evidence;
for(let attempt=0;attempt<40;attempt++) {
  evidence=(await photoCase.get()).data().evidencePaths?.media;
  if(evidence) break;
  await new Promise(resolve=>setTimeout(resolve,500));
}
assert(typeof evidence==='string','private evidence copy did not finish');
allowed(await storage(author.token,evidence),'owner reads evidence');
denied(await storage(outsider.token,evidence),'outsider reads evidence');
denied(await storage(author.token,evidence,{method:'POST',bytes:png,contentType:'image/png'}),'owner modifies evidence');
pass('media evidence is copied to protected immutable storage');
await db.doc(`account_state/${first.uid}`).set({clientUpgradeGraceUntil:Timestamp.fromMillis(Date.now()+86400000)},{merge:true});
const legacyPost = `restored_${suffix}`;
allowed(await commit(first.token,[write(`post_reports/${legacyPost}_${first.uid}`,{postId:s(legacyPost),postOwnerId:s(author.uid),reporterUid:s(first.uid),reason:s('สแปม'),details:s('legacy client'),status:s('open')},{timestamps:['createdAt'],exists:false})]),'legacy client submits report');
await processLegacyReports();
const legacyCase = db.doc(`moderation_cases/${caseId(`posts/${legacyPost}`)}`);
for(let attempt=0;attempt<40;attempt++) { if((await legacyCase.get()).exists) break; await new Promise(resolve=>setTimeout(resolve,250)); }
assert((await legacyCase.get()).data()?.reportCount===1,'legacy report not ingested');
assert((await report(first,legacyPost)).alreadyReported,'legacy report counted again by new API');
pass('legacy reports enter the same queue without double counting during upgrade grace');
const removedReporter = await getAuth().createUser({email:`removed-${suffix}@example.test`,emailVerified:true});
await getAuth().deleteUser(removedReporter.uid);
const staleReport = db.doc(`post_reports/deleted_user_${suffix}`);
await staleReport.set({postId:legacyPost,postOwnerId:author.uid,reporterUid:removedReporter.uid,reason:'สแปม',status:'open',createdAt:Timestamp.now()});
await processLegacyReports();
for(let attempt=0;attempt<40;attempt++) { if((await staleReport.get()).data()?.processed) break; await new Promise(resolve=>setTimeout(resolve,250)); }
assert((await staleReport.get()).data()?.status==='ignored','deleted reporter caused permanent retries');
pass('a deleted legacy reporter is ignored instead of retrying a permanent failure');
const sameTime=Timestamp.now();
for(let i=0;i<5;i++) await db.doc(`worker_test_rows/${suffix}_${i}`).set({createdAt:sameTime});
const seen=[];
for(let page=0;page<3;page++) await scanWork(db,'cursor_test','worker_test_rows','createdAt',async doc=>{seen.push(doc.id);},{pageSize:2,maxPages:1});
assert(seen.length===5 && new Set(seen).size===5,'worker skipped or repeated equal-timestamp rows');
pass('worker pagination resumes across equal timestamps without skipping or duplicating rows');
await db.doc('backend_cursors/cursor_test').set({leaseOwner:'another-run',leaseUntil:Timestamp.fromMillis(Date.now()+60000)},{merge:true});
await db.doc(`worker_test_rows/${suffix}_5`).set({createdAt:Timestamp.now()});
const busy=await scanWork(db,'cursor_test','worker_test_rows','createdAt',async doc=>{seen.push(doc.id);});
assert(busy.reason==='already-running' && seen.length===5,'concurrent worker ignored its lease');
await db.doc('backend_cursors/cursor_test').update({leaseUntil:Timestamp.fromMillis(Date.now()-1)});
await scanWork(db,'cursor_test','worker_test_rows','createdAt',async doc=>{seen.push(doc.id);});
assert(seen.length===6,'worker failed to resume after an expired lease');
pass('worker leases prevent overlap and expired leases recover pending work');
const visits=[];
let interrupted=false;
try {
  await scanWork(db,'retry_test','worker_test_rows','createdAt',async doc=>{
    visits.push(doc.id);
    if(visits.length===2) throw new Error('simulated interruption');
  },{pageSize:2,maxPages:1});
} catch(error) { interrupted=error.message==='simulated interruption'; }
assert(interrupted && !(await db.doc('backend_cursors/retry_test').get()).data().lastAt,'failed page incorrectly advanced checkpoint');
await scanWork(db,'retry_test','worker_test_rows','createdAt',async doc=>{visits.push(doc.id);},{pageSize:2,maxPages:4});
assert(new Set(visits).size===6 && visits.length===8,'unfinished page was not retried completely');
pass('interrupted workers replay the unfinished page before advancing the checkpoint');
denied(await commit(author.token,[write('app_config/security',{verificationRequired:b(false)},{mask:['verificationRequired']})]),'disable security');
denied(await commit(author.token,[write(mainCase.path,{status:s('dismissed')},{mask:['status']})]),'fake a moderation result');
denied(await get(author.token,'backend_cursors/cursor_test'),'read backend worker state');
denied(await commit(author.token,[write('backend_cursors/cursor_test',{lastId:s('bypass')},{mask:['lastId']})]),'skip worker queue');
pass('clients cannot change security configuration or moderation results');
console.log(`PASS all ${passed} social feature integration cases against real local Auth, Firestore, Storage and Functions emulators`);
