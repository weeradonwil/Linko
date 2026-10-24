// ทดสอบบริการ Flutter จริงบน Chrome กับ Firebase Emulator เท่านั้น ไม่แตะฐานข้อมูล production
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;
import 'package:social_app/core/models/post.dart';
import 'package:social_app/core/models/social_group.dart';
import 'package:social_app/core/services/auth_service.dart';
import 'package:social_app/core/services/comment_service.dart';
import 'package:social_app/core/services/follow_service.dart';
import 'package:social_app/core/services/group_service.dart';
import 'package:social_app/core/services/group_reaction_service.dart';
import 'package:social_app/core/services/notification_service.dart';
import 'package:social_app/core/services/post_service.dart';
import 'package:social_app/core/services/reaction_service.dart';
import 'package:social_app/core/services/search_service.dart';
import 'package:social_app/core/utils/authenticated_video.dart';

@JS('globalThis.linkoSocialTestResults')
external set _browserResults(JSAny? value);
@JS('globalThis.linkoSocialTestProgress')
external set _browserProgress(JSAny? value);

const _options = FirebaseOptions(
  apiKey: 'emulator-only-api-key',
  appId: '1:123456:web:social-tests',
  messagingSenderId: '123456',
  projectId: 'demo-linko',
  storageBucket: 'demo-linko.appspot.com',
);
const _password = 'Linko-test-2026!';

/// แยก Auth/Firestore/Storage ต่อบัญชี เพื่อทดสอบสิทธิ์ด้วย SDK จริงในเบราว์เซอร์เดียวกัน
class _Account {
  _Account(this.app, this.auth, this.db, this.storage, this.email);
  final FirebaseApp app;
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirebaseStorage storage;
  final String email;
  String get uid => auth.currentUser!.uid;
  AuthService get accounts => AuthService(auth: auth, firestore: db);
  PostService get posts =>
      PostService(auth: auth, firestore: db, storage: storage);
  GroupService get groups =>
      GroupService(auth: auth, firestore: db, storage: storage);
  CommentService get comments => CommentService(auth: auth, firestore: db);
  FollowService get follows => FollowService(auth: auth, firestore: db);
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _denied(Future<dynamic> operation) async {
  try {
    await operation;
  } on FirebaseException catch (error) {
    _check(
      error.code == 'permission-denied' || error.code == 'unauthorized',
      'Unexpected Firebase error: ${error.code}',
    );
    return;
  }
  throw StateError('Forbidden operation succeeded');
}

/// ชุดข้อมูลเก่าหรือแจ้งเตือนจำนวนมากสร้างได้เฉพาะ REST ของ Emulator ในเครื่อง
Future<void> _seed(List<Map<String, Object?>> documents) async {
  _check(_options.projectId == 'demo-linko', 'Demo project is mandatory');
  for (var offset = 0; offset < documents.length; offset += 100) {
    final writes = documents
        .skip(offset)
        .take(100)
        .map(
          (document) => {
            'update': {
              'name':
                  'projects/demo-linko/databases/(default)/documents/${document['path']}',
              'fields': document['fields'],
            },
          },
        )
        .toList();
    final headers = web.Headers()
      ..set('Authorization', 'Bearer owner')
      ..set('Content-Type', 'application/json');
    final response = await web.window
        .fetch(
          'http://127.0.0.1:8080/v1/projects/demo-linko/databases/(default)/documents:commit'
              .toJS,
          web.RequestInit(
            method: 'POST',
            headers: headers,
            body: jsonEncode({'writes': writes}).toJS,
          ),
        )
        .toDart;
    if (!response.ok) throw StateError((await response.text().toDart).toDart);
  }
}

/// อ่านวิดีโอมาตรฐานที่เก็บใน build ผ่าน HTTP server ทดสอบในเครื่อง
Future<XFile> _videoFixture() async {
  final response = await web.window
      .fetch('http://127.0.0.1:18092/fixture.mp4'.toJS)
      .toDart;
  _check(response.ok, 'Known-valid video fixture is unavailable');
  final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
  return XFile.fromData(bytes, name: 'fixture.mp4', mimeType: 'video/mp4');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Checking Linko services...')),
    ),
  );
  final results = <Map<String, Object?>>[];
  final accounts = <_Account>[];
  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  late _Account owner, member, reader;
  var currentStep = '';
  void trace(String step) {
    currentStep = step;
    _browserProgress = {'step': step, 'finished': results}.jsify();
  }

  Future<_Account> createAccount(String name) async {
    final app = await Firebase.initializeApp(
      name: 'social_${name}_$suffix',
      options: _options,
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('127.0.0.1', 9099);
    await auth.setPersistence(Persistence.NONE);
    final db = FirebaseFirestore.instanceFor(app: app);
    db.settings = const Settings(persistenceEnabled: false);
    db.useFirestoreEmulator('127.0.0.1', 8080);
    final storage = FirebaseStorage.instanceFor(app: app);
    await storage.useStorageEmulator('127.0.0.1', 9199);
    final account = _Account(
      app,
      auth,
      db,
      storage,
      '${name}_$suffix@linko.test',
    );
    accounts.add(account);
    await account.accounts.register(
      name: name,
      email: account.email,
      password: _password,
    );
    return account;
  }

  Future<void> scenario(String name, Future<void> Function() action) async {
    currentStep = name;
    final elapsed = Stopwatch()..start();
    _browserProgress = {'running': name, 'finished': results}.jsify();
    try {
      // ให้ flow หลายบัญชี/หลาย transaction จบใน Emulator ก่อนเริ่มกรณีถัดไป
      // บันทึกเวลาจริงแยกไว้ เพื่อไม่ให้ timeout ทำให้คำขอเดิมไปรบกวนกรณีถัดไป
      await action().timeout(const Duration(seconds: 240));
      results.add({
        'name': name,
        'passed': true,
        'durationMs': elapsed.elapsedMilliseconds,
      });
    } catch (error, stack) {
      results.add({
        'name': name,
        'passed': false,
        'error': '$error (step: $currentStep)',
        'stack': '$stack',
      });
    }
  }

  Future<SocialGroup> group(_Account account, String id) async =>
      SocialGroup.fromSnapshot(
        await account.db
            .collection('groups')
            .doc(id)
            .get(const GetOptions(source: Source.server)),
      );
  // ตรวจผล CRUD จาก server เพื่อไม่อ่านค่า serverTimestamp ที่ยัง pending ใน snapshot แรก
  Future<List<GroupPost>> groupPosts(_Account account, String id) async =>
      (await account.db
              .collection('groups')
              .doc(id)
              .collection('posts')
              .orderBy('createdAt', descending: true)
              .get(const GetOptions(source: Source.server)))
          .docs
          .map(GroupPost.fromSnapshot)
          .toList();
  Future<List<Post>> ownPosts(_Account account) async =>
      (await account.db
              .collection('posts')
              .where('userId', isEqualTo: account.uid)
              .get(const GetOptions(source: Source.server)))
          .docs
          .map(Post.fromSnapshot)
          .toList();
  XFile image() => XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6wSIAAAAASUVORK5CYII=',
    ),
    name: 'fixture.png',
    mimeType: 'image/png',
  );

  await scenario(
    'register, repair profile, edit profile, logout and login',
    () async {
      owner = await createAccount('Owner');
      member = await createAccount('Member');
      reader = await createAccount('Reader');
      await owner.db.collection('users').doc(owner.uid).update({
        'displayName': 'Owner edited',
        'displayNameLower': 'owner edited',
        'bio': 'Saved profile',
      });
      await owner.auth.currentUser!.updateDisplayName('Owner edited');
      final uid = owner.uid;
      await owner.accounts.signOut();
      await owner.accounts.signIn(email: owner.email, password: _password);
      _check(owner.uid == uid, 'Login changed identity');
      _check(
        (await owner.db.collection('users').doc(uid).get()).data()?['bio'] ==
            'Saved profile',
        'Profile repair lost bio',
      );
    },
  );

  await scenario(
    'main feed posts, 7 reactions, comments, edit and recursive delete',
    () async {
      await owner.posts.createPost(
        content: 'Public smoke $suffix',
        tags: ['smoke'],
        visibility: 'public',
      );
      var post = (await ownPosts(owner)).single;
      final feed = await reader.posts
          .watchFeed()
          .firstWhere((posts) => posts.any((p) => p.id == post.id))
          .timeout(const Duration(seconds: 15));
      _check(feed.any((p) => p.id == post.id), 'Public feed missed post');
      final reactions = ReactionService(
        auth: reader.auth,
        firestore: reader.db,
      );
      for (final reaction in ReactionService.supportedReactions) {
        await reactions.toggleReaction(postId: post.id, reaction: reaction);
      }
      await reader.comments.addComment(post: post, content: 'Main comment');
      _check(
        (await owner.comments
                    .watchComments(post.id)
                    .firstWhere((items) => items.isNotEmpty))
                .single
                .content ==
            'Main comment',
        'Missing main comment',
      );
      await owner.posts.updatePost(
        postId: post.id,
        content: 'Edited main post',
        tags: ['edited'],
        visibility: 'public',
        oldMediaPath: null,
        oldThumbnailPath: null,
      );
      post = (await ownPosts(owner)).single;
      _check(
        post.content == 'Edited main post' && post.editedAt != null,
        'Main edit failed',
      );
      await owner.posts.deletePost(post);
      _check((await ownPosts(owner)).isEmpty, 'Main post survived deletion');
    },
  );

  await scenario('group lifecycle, media edit, comments, reactions, report and cleanup', () async {
    trace('create and join group');
    final id = await owner.groups.createGroup(
      name: 'Smoke group',
      description: 'Before',
      visibility: 'public',
    );
    await owner.groups.updateGroup(
      groupId: id,
      name: 'Smoke group edited',
      description: 'After',
    );
    final metadata = await group(owner, id);
    _check(metadata.name == 'Smoke group edited', 'Group metadata edit failed');
    await member.groups.joinGroup(metadata);
    await reader.groups.joinGroup(metadata);
    await member.groups.addPost(
      groupId: id,
      content: 'Group media',
      tags: ['group'],
      attachment: image(),
    );
    var post = (await groupPosts(member, id)).single;
    trace('read initial group stream and media');
    await reader.groups
        .watchPosts(id)
        .firstWhere((posts) => posts.any((item) => item.id == post.id))
        .timeout(const Duration(seconds: 15));
    final oldMedia = post.mediaPath!;
    _check(
      (await reader.storage.ref(oldMedia).getData())!.isNotEmpty,
      'Group image inaccessible',
    );
    final delivery = await reader.comments.addComment(
      post: post.asPost(),
      content: 'Group comment',
      groupId: id,
    );
    _check(
      delivery.notificationsComplete && delivery.notifiedFollowers == 1,
      'Group author notification failed',
    );
    _check(
      (await member.comments
                  .watchComments(post.id, groupId: id)
                  .firstWhere((items) => items.isNotEmpty))
              .single
              .content ==
          'Group comment',
      'Missing group comment',
    );
    final reactions = GroupReactionService(
      auth: reader.auth,
      firestore: reader.db,
    );
    for (final reaction in GroupReactionService.supportedReactions) {
      trace('group reaction $reaction');
      await reactions.toggleReaction(
        groupId: id,
        postId: post.id,
        reaction: reaction,
      );
    }
    trace('edit group text and preserve media');
    await member.groups.updatePost(
      groupId: id,
      postId: post.id,
      content: 'Edited with old image',
      tags: ['edited'],
    );
    trace('confirm group edit from server');
    post = (await groupPosts(member, id)).single;
    _check(
      post.mediaPath == oldMedia &&
          post.tags.single == 'edited' &&
          post.editedAt != null,
      'Group edit lost existing image or tags: media=${post.mediaPath}, tags=${post.tags}, editedAt=${post.editedAt}',
    );
    trace('remove group media');
    await member.groups.updatePost(
      groupId: id,
      postId: post.id,
      content: 'Image removed',
      removeMedia: true,
    );
    post = (await groupPosts(member, id)).single;
    _check(
      post.mediaPath == null && post.mediaType == 'none',
      'Group media removal failed',
    );
    try {
      trace('confirm deleted media is missing');
      await member.storage.ref(oldMedia).getMetadata();
      throw StateError('Old image was not removed');
    } on FirebaseException catch (error) {
      _check(error.code == 'object-not-found', 'Unexpected cleanup error');
    }
    trace('report group post');
    await reader.groups.reportPost(
      groupId: id,
      post: post,
      reason: 'ไม่เหมาะสม',
    );
    trace('delete group post with comments and reactions');
    await member.groups.deletePost(groupId: id, postId: post.id);
    _check(
      (await groupPosts(owner, id)).isEmpty,
      'Group post survived deletion',
    );
  });

  // แยกการลบทั้งกลุ่มเป็นอีก flow เพื่อแยกผล CRUD รายโพสต์ออกจากงานล้างข้อมูลหลายชุด
  await scenario(
    'whole group cleanup removes member media and comments after leaving',
    () async {
      final id = await owner.groups.createGroup(
        name: 'Cleanup group',
        description: '',
        visibility: 'public',
      );
      final metadata = await group(owner, id);
      await member.groups.joinGroup(metadata);
      await reader.groups.joinGroup(metadata);
      trace('create second post for whole group cleanup');
      await member.groups.addPost(
        groupId: id,
        content: 'Cleanup whole group',
        attachment: image(),
      );
      var post = (await groupPosts(member, id)).single;
      await reader.comments.addComment(
        post: post.asPost(),
        content: 'Clean me',
        groupId: id,
      );
      trace('leave group and revoke media access');
      await reader.groups.leaveGroup(metadata);
      await _denied(reader.storage.ref(post.mediaPath!).getData());
      trace('delete whole group');
      await owner.groups.deleteGroup(id);
      _check(
        !(await owner.db.collection('groups').doc(id).get()).exists,
        'Group survived deletion',
      );
    },
  );

  await scenario(
    'private profile follow request, approval, unfollow and media access',
    () async {
      await owner.posts.createPost(
        content: 'Private image',
        tags: [],
        visibility: 'public',
        attachment: image(),
      );
      final post = (await ownPosts(owner)).single;
      await owner.posts.updateProfilePrivacy(true);
      await _denied(reader.storage.ref(post.mediaPath!).getData());
      await reader.follows.requestFollow(owner.uid);
      await owner.follows.approveFollowRequest(reader.uid);
      _check(
        (await reader.storage.ref(post.mediaPath!).getData())!.isNotEmpty,
        'Approved follower cannot read media',
      );
      await reader.follows.unfollow(owner.uid);
      await _denied(reader.storage.ref(post.mediaPath!).getData());
      await owner.posts.updateProfilePrivacy(false);
      await owner.posts.deletePost((await ownPosts(owner)).single);
    },
  );

  await scenario(
    'legacy users beyond 150 entries can be found across cursor pages',
    () async {
      await _seed(
        List.generate(
          180,
          (i) => {
            'path': 'users/legacy_${suffix}_${i.toString().padLeft(3, '0')}',
            'fields': {
              'uid': {'stringValue': 'legacy_${suffix}_$i'},
              'displayName': {
                'stringValue': i == 179
                    ? 'Legacy needle $suffix'
                    : 'Older member $i',
              },
              'bio': {'stringValue': ''},
              'isPrivate': {'booleanValue': false},
            },
          },
        ),
      );
      final search = SearchService(auth: owner.auth, firestore: owner.db);
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      var found = false, pages = 0;
      while (!found && pages++ < 20) {
        final page = await search.searchUserPage(
          'Legacy needle $suffix',
          cursor: cursor,
          pageSize: 40,
        );
        found = page.users.any(
          (user) => user['displayName'] == 'Legacy needle $suffix',
        );
        cursor = page.cursor;
        if (!page.hasMore) break;
      }
      _check(
        found && pages > 1,
        'Old profile was truncated or cursor did not advance',
      );
    },
  );

  await scenario(
    'notification history is reachable beyond the first 100 items',
    () async {
      await _seed(
        List.generate(
          110,
          (i) => {
            'path': 'notifications/history_${suffix}_$i',
            'fields': {
              'recipientId': {'stringValue': owner.uid},
              'actorId': {'stringValue': member.uid},
              'actorName': {'stringValue': 'Member'},
              'type': {'stringValue': 'like'},
              'body': {'stringValue': ''},
              'isRead': {'booleanValue': false},
              'createdAt': {
                'timestampValue': DateTime.utc(2020)
                    .add(Duration(seconds: i))
                    .toIso8601String(),
              },
            },
          },
        ),
      );
      final notifications = NotificationService(
        auth: owner.auth,
        firestore: owner.db,
      );
      final first = await notifications.watchNotifications().firstWhere(
        (items) => items.length == 100,
      );
      final expanded = await notifications
          .watchNotifications(limit: 200)
          .firstWhere((items) => items.length >= 110);
      _check(
        first.length == 100 &&
            expanded.any((item) => item.id == 'history_${suffix}_0'),
        'Old notification is unreachable',
      );
    },
  );

  await scenario('video upload, authenticated Blob playback, and denied access after leaving', () async {
    final id = await owner.groups.createGroup(
      name: 'Video group',
      description: '',
      visibility: 'public',
    );
    final metadata = await group(owner, id);
    await reader.groups.joinGroup(metadata);
    final fixture = await _videoFixture();
    await owner.groups.addPost(
      groupId: id,
      content: 'Video',
      attachment: fixture,
    );
    final post = (await groupPosts(owner, id)).single;
    _check(post.mediaType == 'video', 'Video type lost');
    _check(
      listEquals(
        await reader.storage.ref(post.mediaPath!).getData(50 * 1024 * 1024),
        await fixture.readAsBytes(),
      ),
      'Video changed during upload/download',
    );
    final source = await loadAuthenticatedVideo(
      reader.storage.ref(post.mediaPath!),
    );
    try {
      await source.controller.initialize().timeout(const Duration(seconds: 15));
      _check(
        source.controller.value.isInitialized &&
            source.controller.value.size.width > 0,
        'Real browser video did not initialize',
      );
    } finally {
      await source.dispose();
    }
    await reader.groups.leaveGroup(metadata);
    await _denied(loadAuthenticatedVideo(reader.storage.ref(post.mediaPath!)));
    await owner.groups.deleteGroup(id);
  });

  await scenario(
    'videos larger than 50 MB are rejected before upload',
    () async {
      final id = await owner.groups.createGroup(
        name: 'Size limit',
        description: '',
        visibility: 'public',
      );
      final oversized = XFile.fromData(
        Uint8List(50 * 1024 * 1024 + 1),
        name: 'oversized.mp4',
        mimeType: 'video/mp4',
      );
      var rejected = false;
      try {
        await owner.groups.addPost(
          groupId: id,
          content: '',
          attachment: oversized,
        );
      } on GroupServiceException {
        rejected = true;
      }
      _check(
        rejected && (await groupPosts(owner, id)).isEmpty,
        'Oversized group video was accepted',
      );
      rejected = false;
      try {
        await owner.posts.createPost(
          content: '',
          tags: [],
          visibility: 'public',
          attachment: oversized,
        );
      } on PostServiceException {
        rejected = true;
      }
      _check(rejected, 'Oversized main video was accepted');
      await owner.groups.deleteGroup(id);
    },
  );

  for (final account in accounts) {
    await account.auth.signOut();
    await account.app.delete();
  }
  _browserResults = results.jsify();
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Text(
          'Social checks: ${results.where((result) => result['passed'] == true).length}/${results.length}',
        ),
      ),
    ),
  );
}
