// รันผ่าน runner ใน demo emulators เท่านั้น ใช้ปลั๊กอิน Android จริงแทน mock
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:social_app/core/models/post.dart';
import 'package:social_app/core/services/auth_service.dart';
import 'package:social_app/core/services/group_service.dart';
import 'package:social_app/core/services/post_service.dart';

const _project = 'demo-linko';
const _host = '10.0.2.2';

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<bool> _ticketExistsForTest(String path) async {
  final client = HttpClient();
  try {
    // อ่านแบบ admin ได้เฉพาะ Emulator ที่ hardcode ไว้ ไม่ลดสิทธิ์ Rules ของ client
    final request = await client.getUrl(
      Uri.parse(
        'http://$_host:8080/v1/projects/$_project/databases/(default)/documents/$path',
      ),
    );
    request.headers.set('Authorization', 'Bearer owner');
    final response = await request.close();
    await response.drain<void>();
    _check(
      response.statusCode == 200 || response.statusCode == 404,
      'Local ticket inspection failed',
    );
    return response.statusCode == 200;
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Linko: local Android posting checks')),
      ),
    ),
  );
  final results = <Map<String, Object?>>[];
  FirebaseApp? app;
  File? fixture;
  try {
    // named app แยกจากบัญชี production ที่ล็อกอินไว้ในแอปปกติ
    app = await Firebase.initializeApp(
      name: 'android_smoke_${DateTime.now().microsecondsSinceEpoch}',
      options: const FirebaseOptions(
        // Android ตรวจรูปแบบ key แม้ใช้ Emulator; ค่านี้เป็น key จำลอง 39 ตัว ไม่ใช่ key จริง
        apiKey: 'AIzaSy000000000000000000000000000000000',
        appId: '1:1234567890:android:demolinko',
        messagingSenderId: '1234567890',
        projectId: _project,
        storageBucket: 'demo-linko.appspot.com',
      ),
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator(_host, 9099);
    final db = FirebaseFirestore.instanceFor(app: app);
    db.settings = const Settings(persistenceEnabled: false);
    db.useFirestoreEmulator(_host, 8080);
    final storage = FirebaseStorage.instanceFor(app: app);
    await storage.useStorageEmulator(_host, 9199);
    FirebaseFunctions.instanceFor(
      app: app,
      region: 'asia-southeast1',
    ).useFunctionsEmulator(_host, 5001);
    final account = AuthService(auth: auth, firestore: db);
    final posts = PostService(auth: auth, firestore: db, storage: storage);
    final groups = GroupService(auth: auth, firestore: db, storage: storage);
    await account.register(
      name: 'Android local tester',
      email: 'android-${DateTime.now().microsecondsSinceEpoch}@example.test',
      password: 'Local-test-only123!',
    );
    // ยืนยันเฉพาะบัญชีทดสอบใน Auth Emulator ไม่มีอีเมลจริงส่งออกไป
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse(
          'http://$_host:9099/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:update',
        ),
      );
      request.headers.set('Authorization', 'Bearer owner');
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'localId': auth.currentUser!.uid, 'emailVerified': true}),
      );
      final response = await request.close();
      await response.drain<void>();
      _check(response.statusCode == 200, 'Local email verification failed');
    } finally {
      client.close(force: true);
    }
    await auth.currentUser!.reload();
    await auth.currentUser!.getIdToken(true);
    final uid = auth.currentUser!.uid;
    final config = await db.doc('app_config/security').get();
    _check(
      config.data()?['writeTicketsRequired'] == true,
      'Write tickets must be enabled',
    );
    _check(
      !(await db.doc('account_state/$uid').get()).exists,
      'Test account must have no grace',
    );

    Future<List<Post>> mine() async =>
        (await db
                .collection('posts')
                .where('userId', isEqualTo: uid)
                .get(const GetOptions(source: Source.server)))
            .docs
            .map(Post.fromSnapshot)
            .toList();
    Future<void> scenario(String name, Future<void> Function() action) async {
      await action().timeout(const Duration(seconds: 240));
      results.add({'name': name, 'passed': true});
      debugPrint('LINKO_ANDROID_CASE PASS $name');
    }

    await scenario(
      'native callable and text-only posting with enforced tickets',
      () async {
        await posts.createPost(
          content: 'Android native text',
          tags: [],
          visibility: 'public',
        );
        final created = (await mine()).single;
        _check(created.content == 'Android native text', 'Text was not saved');
        _check(
          !await _ticketExistsForTest('write_tickets/${uid}_${created.id}'),
          'Ticket was not consumed atomically',
        );
      },
    );

    fixture = File('${(await getTemporaryDirectory()).path}/linko_smoke.png');
    await fixture.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS2kAAAAASUVORK5CYII=',
      ),
    );
    await scenario(
      'native photo-only posting uploads and reads Storage bytes',
      () async {
        await posts.createPost(
          content: '',
          tags: [],
          visibility: 'public',
          attachment: XFile(fixture!.path, mimeType: 'image/png'),
        );
        final created = (await mine()).singleWhere(
          (p) => p.mediaType == 'image',
        );
        _check(created.content.isEmpty, 'Photo-only caption changed');
        final bytes = await storage
            .ref(created.mediaPath!)
            .getData(5 * 1024 * 1024);
        _check(
          bytes != null && bytes.isNotEmpty,
          'Uploaded photo is unreadable',
        );
      },
    );

    await scenario('native post edit retains existing media', () async {
      final created = (await mine()).singleWhere((p) => p.mediaType == 'image');
      await posts.updatePost(
        postId: created.id,
        content: 'Edited Android photo',
        tags: ['android'],
        visibility: 'public',
        oldMediaPath: created.mediaPath,
        oldThumbnailPath: created.thumbnailPath,
      );
      final edited = (await mine()).singleWhere((p) => p.id == created.id);
      _check(
        edited.content == 'Edited Android photo' &&
            edited.mediaPath == created.mediaPath,
        'Edit lost its attachment',
      );
    });

    await scenario('native group accepts an image without a caption', () async {
      final groupId = await groups.createGroup(
        name: 'Android local group',
        description: '',
        visibility: 'public',
      );
      await groups.addPost(
        groupId: groupId,
        content: '',
        attachment: XFile(fixture!.path, mimeType: 'image/png'),
      );
      final created = await db.collection('groups/$groupId/posts').get();
      _check(
        created.docs.length == 1 &&
            created.docs.single.data()['mediaType'] == 'image',
        'Group photo-only posting failed',
      );
      await groups.deleteGroup(groupId);
      _check(
        !(await db.doc('groups/$groupId').get()).exists,
        'Group cleanup failed',
      );
    });

    await scenario(
      'native deletion cleans posts and uploaded images',
      () async {
        final created = await mine();
        final paths = created
            .map((post) => post.mediaPath)
            .whereType<String>()
            .toList();
        for (final post in created) {
          await posts.deletePost(post);
        }
        _check((await mine()).isEmpty, 'Post survived deletion');
        for (final path in paths) {
          var removed = false;
          try {
            await storage.ref(path).getMetadata();
          } on FirebaseException catch (error) {
            removed = error.code == 'object-not-found';
          }
          _check(removed, 'Orphaned image remains');
        }
      },
    );
    await auth.signOut();
  } catch (error) {
    results.add({
      'name': 'native Android posting checks',
      'passed': false,
      // จำกัดให้ marker อยู่บรรทัดเดียวและไม่ถูก Android logcat ตัดกลาง JSON
      'error': error is FirebaseException
          ? '[${error.plugin}/${error.code}] ${error.message?.split('\n').first}'
          : '$error'.split('\n').first,
    });
  } finally {
    if (fixture != null && await fixture.exists()) await fixture.delete();
    if (app != null) await app.delete();
  }
  // runner อ่านเฉพาะ marker นี้ ไม่เก็บ log ทั่วเครื่องที่อาจมีข้อมูลผู้ใช้
  debugPrint('LINKO_ANDROID_RESULT ${jsonEncode(results)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Local Android checks: ${results.where((r) => r['passed'] == true).length}/${results.length}',
          ),
        ),
      ),
    ),
  );
}
