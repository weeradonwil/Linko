// Exercises group access and join workflows against the local Firebase emulators.
// Start with: firebase --config firebase.emulator.test.json emulators:exec --only auth,firestore,storage --project demo-linko "node tool/group_rules_emulator_test.mjs"

const projectId = process.env.GCLOUD_PROJECT ?? 'demo-linko';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const authBase = `http://${authHost}/identitytoolkit.googleapis.com/v1`;
const firestoreBase = `http://${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents`;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function createUser() {
  const response = await fetch(
    `${authBase}/accounts:signUp?key=emulator-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const body = await response.json();
  assert(response.ok, `Auth emulator user creation failed: ${JSON.stringify(body)}`);
  return { uid: body.localId, token: body.idToken };
}

async function firestoreRequest(path, { token, method = 'GET', body } = {}) {
  const response = await fetch(`${firestoreBase}${path}`, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await response.text();
  let parsed;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = text;
  }
  return { ok: response.ok, status: response.status, body: parsed };
}

function documentName(path) {
  return `projects/${projectId}/databases/(default)/documents/${path}`;
}

function stringValue(value) {
  return { stringValue: value };
}

function integerValue(value) {
  return { integerValue: String(value) };
}

function memberCreateWrite(groupId, user, requireMissing = true) {
  return {
    update: {
      name: documentName(`groups/${groupId}/members/${user.uid}`),
      fields: {
        uid: stringValue(user.uid),
        displayName: stringValue('Emulator member'),
      },
    },
    updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }],
    ...(requireMissing ? { currentDocument: { exists: false } } : {}),
  };
}

function requestCreateWrite(groupId, user, requireMissing = true) {
  return {
    update: {
      name: documentName(`groups/${groupId}/join_requests/${user.uid}`),
      fields: {
        uid: stringValue(user.uid),
        displayName: stringValue('Emulator member'),
      },
    },
    updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }],
    ...(requireMissing ? { currentDocument: { exists: false } } : {}),
  };
}

function groupCreateWrites(groupId, owner, visibility) {
  return [
    {
      update: {
        name: documentName(`groups/${groupId}`),
        fields: {
          name: stringValue(`Test ${visibility} group`),
          description: stringValue('Security rules test group'),
          ownerId: stringValue(owner.uid),
          visibility: stringValue(visibility),
          memberCount: integerValue(1),
        },
      },
      updateTransforms: [
        { fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' },
        { fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' },
      ],
      currentDocument: { exists: false },
    },
    memberCreateWrite(groupId, owner),
  ];
}

async function commit(token, writes) {
  return firestoreRequest(':commit', {
    token,
    method: 'POST',
    body: { writes },
  });
}

async function mustSucceed(response, message) {
  assert(response.ok, `${message}: ${JSON.stringify(response.body)}`);
}

async function mustBeDenied(response, message) {
  assert(!response.ok, `${message} unexpectedly succeeded`);
}

async function readInteger(path, field, token) {
  const response = await firestoreRequest(path, { token });
  await mustSucceed(response, `Could not read ${path}`);
  return Number(response.body.fields[field].integerValue);
}

async function main() {
  const owner = await createUser();
  const member = await createUser();
  const stranger = await createUser();

  await mustSucceed(
    await commit(owner.token, groupCreateWrites('public_group', owner, 'public')),
    'Owner could not create a public group with its first member',
  );
  await mustSucceed(
    await commit(owner.token, groupCreateWrites('private_group', owner, 'private')),
    'Owner could not create a private group with its first member',
  );
  await mustSucceed(
    await commit(owner.token, [
      {
        update: {
          name: documentName('groups/private_group/posts/private_post'),
          fields: {
            authorId: stringValue(owner.uid),
            authorName: stringValue('Owner'),
            content: stringValue('Members only'),
            mediaType: stringValue('none'),
          },
        },
        updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }],
        currentDocument: { exists: false },
      },
    ]),
    'Owner could not create a private group post',
  );

  const publicJoin = await commit(member.token, [
    {
      update: {
        name: documentName('groups/public_group'),
        fields: { memberCount: integerValue(2) },
      },
      updateMask: { fieldPaths: ['memberCount'] },
    },
    memberCreateWrite('public_group', member),
  ]);
  await mustSucceed(publicJoin, 'Public group immediate join was denied');
  assert(
    (await readInteger('/groups/public_group', 'memberCount', owner.token)) === 2,
    'Public join did not update the real member count',
  );

  const duplicatePublicJoin = await commit(member.token, [
    {
      update: {
        name: documentName('groups/public_group'),
        fields: { memberCount: integerValue(3) },
      },
      updateMask: { fieldPaths: ['memberCount'] },
    },
    memberCreateWrite('public_group', member, false),
  ]);
  await mustBeDenied(duplicatePublicJoin, 'Duplicate public membership');

  const publicLeave = await commit(member.token, [
    {
      update: {
        name: documentName('groups/public_group'),
        fields: { memberCount: integerValue(1) },
      },
      updateMask: { fieldPaths: ['memberCount'] },
    },
    { delete: documentName(`groups/public_group/members/${member.uid}`) },
  ]);
  await mustSucceed(publicLeave, 'Public group member could not leave');
  assert(
    (await readInteger('/groups/public_group', 'memberCount', owner.token)) === 1,
    'Public leave did not update the real member count',
  );

  await mustSucceed(
    await commit(member.token, [requestCreateWrite('private_group', member)]),
    'Private group join request was denied',
  );
  await mustBeDenied(
    await commit(member.token, [requestCreateWrite('private_group', member, false)]),
    'Duplicate private join request',
  );
  await mustSucceed(
    await firestoreRequest(`/groups/private_group/join_requests/${member.uid}`, {
      token: member.token,
      method: 'DELETE',
    }),
    'Requester could not cancel their pending request',
  );
  await mustSucceed(
    await commit(member.token, [requestCreateWrite('private_group', member)]),
    'Requester could not submit a new request after cancellation',
  );

  const privateReadBeforeApproval = await firestoreRequest(
    '/groups/private_group/posts/private_post',
    { token: member.token },
  );
  await mustBeDenied(privateReadBeforeApproval, 'Unapproved private post read');
  await mustBeDenied(
    await firestoreRequest('/groups/private_group/members', { token: member.token }),
    'Unapproved private member list read',
  );

  const approve = await commit(owner.token, [
    {
      update: {
        name: documentName('groups/private_group'),
        fields: { memberCount: integerValue(2) },
      },
      updateMask: { fieldPaths: ['memberCount'] },
    },
    memberCreateWrite('private_group', member),
    { delete: documentName(`groups/private_group/join_requests/${member.uid}`) },
  ]);
  await mustSucceed(approve, 'Group owner could not approve a private join request');
  assert(
    (await readInteger('/groups/private_group', 'memberCount', owner.token)) === 2,
    'Private approval did not update the real member count',
  );

  await mustSucceed(
    await firestoreRequest('/groups/private_group/posts/private_post', {
      token: member.token,
    }),
    'Approved member could not read a private group post',
  );

  await mustSucceed(
    await commit(stranger.token, [requestCreateWrite('private_group', stranger)]),
    'Second user could not request to join the private group',
  );
  await mustSucceed(
    await firestoreRequest(`/groups/private_group/join_requests/${stranger.uid}`, {
      token: owner.token,
    }),
    'Owner could not read a pending request',
  );
  await mustSucceed(
    await firestoreRequest(`/groups/private_group/join_requests/${stranger.uid}`, {
      token: owner.token,
      method: 'DELETE',
    }),
    'Owner could not reject a pending request',
  );
  assert(
    (await readInteger('/groups/private_group', 'memberCount', owner.token)) === 2,
    'Rejecting a request changed the group member count',
  );

  await mustSucceed(
    await commit(owner.token, groupCreateWrites('approval_guard', owner, 'private')),
    'Could not create a second private group for authorization test',
  );
  await mustSucceed(
    await commit(stranger.token, [requestCreateWrite('approval_guard', stranger)]),
    'Second requester could not submit a private group request',
  );
  const unauthorizedApproval = await commit(member.token, [
    {
      update: {
        name: documentName('groups/approval_guard'),
        fields: { memberCount: integerValue(2) },
      },
      updateMask: { fieldPaths: ['memberCount'] },
    },
    memberCreateWrite('approval_guard', stranger),
    { delete: documentName(`groups/approval_guard/join_requests/${stranger.uid}`) },
  ]);
  await mustBeDenied(unauthorizedApproval, 'Non-owner request approval');
  assert(
    (await readInteger('/groups/approval_guard', 'memberCount', owner.token)) === 1,
    'Unauthorized approval changed the group member count',
  );

  console.log('PASS public group immediate join, duplicate protection, and leave');
  console.log('PASS private request, cancellation, duplicate protection, and owner approval');
  console.log('PASS private post access before and after approval');
  console.log('PASS group owner can reject a request without adding a member');
  console.log('PASS non-owner cannot approve private join requests');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
