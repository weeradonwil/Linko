// จุดเริ่ม Flutter สำหรับทดสอบ ChatService ตัวจริงบนเบราว์เซอร์กับ Emulator ในเครื่อง
// แยกจาก lib/main.dart และใช้ demo-linko เท่านั้น; ไม่อัปโหลดไฟล์แนบจริง
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:social_app/core/models/chat_models.dart';
import 'package:social_app/core/services/chat_service.dart';
import 'package:social_app/core/services/auth_service.dart';
import 'package:social_app/core/services/follow_service.dart';
import 'package:web/web.dart' as web;

// ส่งผลกลับให้ run_chat_service_smoke.mjs อ่านผ่าน Chrome DevTools
@JS('globalThis.linkoChatTestResults')
external set _browserResults(JSAny? value);

const _options = FirebaseOptions(
  apiKey: 'emulator-only-api-key',
  appId: '1:123456:web:chat-emulator-tests',
  messagingSenderId: '123456',
  projectId: 'demo-linko',
  storageBucket: 'demo-linko.appspot.com',
);

/// รวม Firebase instance ของบัญชีหนึ่ง เพื่อทดสอบผู้ส่งและผู้รับในเบราว์เซอร์เดียวกัน
class _Account {
  _Account(this.app, this.auth, this.db, this.service);
  final FirebaseApp app;
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final ChatService service;
  String get uid => auth.currentUser!.uid;
}

void _check(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

/// ยืนยันว่า Rules ปฏิเสธด้วย permission-denied จริง ไม่ใช่ผ่านเพราะ error ชนิดอื่น
Future<void> _permissionDenied(Future<dynamic> operation) async {
  try {
    await operation;
  } on FirebaseException catch (error) {
    _check(error.code == 'permission-denied', 'Unexpected code: ${error.code}');
    return;
  }
  throw StateError('A forbidden operation succeeded');
}

// จำลองห้องที่เคยกดลบในแอปรุ่นเก่า ซึ่งยังไม่มีจุดตัดประวัติ
Future<void> _legacyHide(String conversationId, String uid) async {
  _check(_options.projectId == 'demo-linko', 'Emulator project is required');
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
          body: jsonEncode({
            'writes': [
              {
                'update': {
                  'name':
                      'projects/demo-linko/databases/(default)/documents/conversations/$conversationId',
                  'fields': {
                    'hiddenFor': {
                      'mapValue': {
                        'fields': {
                          uid: {'booleanValue': true},
                        },
                      },
                    },
                  },
                },
                'updateMask': {
                  'fieldPaths': ['hiddenFor.$uid'],
                },
              },
            ],
          }).toJS,
        ),
      )
      .toDart;
  if (!response.ok) throw StateError('Legacy fixture failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = <Map<String, Object?>>[];
  final accounts = <_Account>[];
  var serial = 0;
  late _Account alice;
  late _Account bob;
  late String room;

  // สร้าง Firebase app แยกต่อบัญชี ปิด cache และชี้ SDK ทุกตัวไป Emulator ก่อนใช้งาน
  Future<_Account> createAccount(String name) async {
    _check(_options.projectId == 'demo-linko', 'Emulator project is required');
    final app = await Firebase.initializeApp(
      name: 'chat_test_${DateTime.now().microsecondsSinceEpoch}_${serial++}',
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
      ChatService(auth: auth, firestore: db, storage: storage),
    );
    accounts.add(account);
    await auth.signInAnonymously();
    await auth.currentUser!.updateDisplayName(name);
    await AuthService(
      auth: auth,
      firestore: db,
    ).ensureProfile(auth.currentUser!, displayName: name);
    return account;
  }

  // รอฝั่งผู้รับเห็นข้อความครบและมีเวลาจาก server เพื่อไม่ใช้เพียงผลเขียนใน cache ผู้ส่ง
  Future<List<ChatMessage>> received(int count) => bob.service
      .watchMessages(room)
      .firstWhere(
        (messages) =>
            messages.length == count &&
            messages.every((message) => message.createdAt != null),
      )
      .timeout(const Duration(seconds: 20));

  Future<Map<String, dynamic>> summary() async =>
      (await bob.db
              .collection('conversations')
              .doc(room)
              .get(const GetOptions(source: Source.server)))
          .data()!;

  // แต่ละกรณีเรียก public API ของ ChatService รวม flow ที่ทำให้ Rules เดิมล้มเหลว
  final scenarios = <String, Future<void> Function()>{
    'consecutive and identical text received by peer': () async {
      for (final text in ['First', 'Second', 'Second']) {
        await alice.service.sendMessage(
          conversationId: room,
          peerId: bob.uid,
          text: text,
        );
      }
      final messages = await received(3);
      _check(
        messages.map((m) => m.text).join('|') == 'First|Second|Second',
        'Peer message text/order',
      );
      _check(messages.every((m) => m.senderId == alice.uid), 'Sender identity');
      final data = await summary();
      _check(
        (data['unreadCounts'] as Map)[bob.uid] == 3,
        'Recipient unread count',
      );
      _check(data['lastMessageId'] == messages.last.id, 'Latest message ID');
    },
    'replies and read receipts preserve peer state': () async {
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'One',
      );
      await bob.service.sendMessage(
        conversationId: room,
        peerId: alice.uid,
        text: 'Two',
      );
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'Three',
      );
      final messages = await received(3);
      _check(
        messages[1].senderId == bob.uid && messages.last.senderId == alice.uid,
        'Reply senders',
      );
      final before = await summary();
      _check((before['unreadCounts'] as Map)[bob.uid] == 1, 'Bob unread count');
      _check(
        (before['unreadCounts'] as Map)[alice.uid] == 0,
        'Alice unread count',
      );
      await bob.service.markRead(room);
      final after = await summary();
      _check((after['unreadCounts'] as Map)[bob.uid] == 0, 'Mark read');
      _check(
        (after['lastReadAt'] as Map)[alice.uid] ==
            (before['lastReadAt'] as Map)[alice.uid],
        'Peer read state unchanged',
      );
    },
    'deleted chat stays empty after reopening while peer keeps history':
        () async {
          await alice.service.sendMessage(
            conversationId: room,
            peerId: bob.uid,
            text: 'Hello',
          );
          final oldMessage = (await received(1)).single;
          await alice.service.hideConversation(room);
          _check(
            (await alice.service.watchConversations().first).isEmpty,
            'Deleted room stays out of the list',
          );
          _check(
            (await alice.service.watchMessages(room).first).isEmpty,
            'Old messages do not return for the deleting account',
          );
          await _permissionDenied(
            alice.db
                .collection('conversations')
                .doc(room)
                .collection('messages')
                .doc(oldMessage.id)
                .get(const GetOptions(source: Source.server)),
          );
          _check(
            (await received(1)).single.id == oldMessage.id,
            'Peer keeps the original message',
          );
          _check(
            await alice.service.openConversation(
                  peerId: bob.uid,
                  peerName: 'Bob',
                ) ==
                room,
            'Open deleted room from profile',
          );
          _check(
            await alice.service.openConversation(
                  peerId: bob.uid,
                  peerName: 'Bob',
                ) ==
                room,
            'Open same room again',
          );
          _check(
            (await alice.service.watchConversations().first).isEmpty,
            'Opening from profile does not restore chat list',
          );
          _check(
            (await alice.service.watchMessages(room).first).isEmpty,
            'Opening from profile does not restore old messages',
          );
          await alice.service.sendMessage(
            conversationId: room,
            peerId: bob.uid,
            text: 'New start',
          );
          final mine = await alice.service
              .watchMessages(room)
              .firstWhere(
                (messages) =>
                    messages.length == 1 && messages.single.text == 'New start',
              )
              .timeout(const Duration(seconds: 20));
          _check(
            mine.single.id != oldMessage.id,
            'Deleter sees only the new message',
          );
          _check(
            (await received(2)).first.id == oldMessage.id,
            'Other account still sees both messages',
          );
          final hidden = (await summary())['hiddenFor'] as Map;
          _check(
            hidden[alice.uid] == false && hidden[bob.uid] == false,
            'New message returns the chat to the list',
          );
        },
    'each account can clear its own history independently': () async {
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'Before clearing',
      );
      final oldMessage = (await received(1)).single;
      await alice.service.hideConversation(room);
      await bob.service.hideConversation(room);
      _check(
        (await alice.service.watchMessages(room).first).isEmpty,
        'Alice cannot see the old message',
      );
      _check(
        (await bob.service.watchMessages(room).first).isEmpty,
        'Bob cannot see the old message after clearing too',
      );
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'After clearing',
      );
      final newMessage =
          (await bob.service
                  .watchMessages(room)
                  .firstWhere(
                    (messages) =>
                        messages.length == 1 &&
                        messages.single.text == 'After clearing',
                  )
                  .timeout(const Duration(seconds: 20)))
              .single;
      _check(
        newMessage.id != oldMessage.id,
        'A new message does not restore either old history',
      );
    },
    'old hidden room is cleared when opened from profile': () async {
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'From old version',
      );
      final oldMessage = (await received(1)).single;
      await _legacyHide(room, alice.uid);
      _check(
        (await summary())['clearedAt'] == null,
        'Old room has no cutoff yet',
      );
      await alice.service.openConversation(peerId: bob.uid, peerName: 'Bob');
      final after = await summary();
      _check(
        (after['clearedAt'] as Map)[alice.uid] != null,
        'Opening old hidden room creates a cutoff',
      );
      _check(
        (after['hiddenFor'] as Map)[alice.uid] == true,
        'Old room stays out of the chat list',
      );
      _check(
        (await alice.service.watchMessages(room).first).isEmpty,
        'Old messages stay deleted after migration',
      );
      _check(
        (await received(1)).single.id == oldMessage.id,
        'Peer history survives migration',
      );
    },
    'unsend identical preview and send another text': () async {
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'ยกเลิกข้อความนี้',
      );
      final original = (await received(1)).single;
      await alice.service.unsendMessage(
        conversationId: room,
        message: original,
      );
      final cancelled = await bob.service
          .watchMessages(room)
          .firstWhere(
            (messages) => messages.length == 1 && messages.single.isUnsent,
          )
          .timeout(const Duration(seconds: 20));
      _check(
        cancelled.single.id == original.id,
        'Cancellation message identity',
      );
      _check(
        (await summary())['lastMessageType'] == 'deleted',
        'Cancellation preview',
      );
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'Next',
      );
      _check(
        (await received(2)).last.text == 'Next',
        'Send after cancellation',
      );
    },
    'nonparticipant cannot read or send': () async {
      final stranger = await createAccount('Stranger');
      await _permissionDenied(stranger.service.watchMessages(room).first);
      await _permissionDenied(
        stranger.service.sendMessage(
          conversationId: room,
          peerId: bob.uid,
          text: 'Forbidden',
        ),
      );
      _check((await received(0)).isEmpty, 'No unauthorized message persisted');
    },
    'peer cannot cancel another sender message': () async {
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'Owned by Alice',
      );
      final original = (await received(1)).single;
      var denied = false;
      try {
        await bob.service.unsendMessage(
          conversationId: room,
          message: original,
        );
      } on ChatServiceException {
        denied = true;
      }
      _check(denied, 'Reject another sender cancellation');
      _check(
        !(await received(1)).single.isUnsent,
        'Original message unchanged',
      );
    },
  };

  // แยกบัญชี/ห้องใหม่ทุกกรณี และปิด instance หลังจบเพื่อไม่ให้สถานะข้ามกรณีทดสอบ
  for (final entry in scenarios.entries) {
    final result = <String, Object?>{'name': entry.key, 'passed': false};
    try {
      alice = await createAccount('Alice');
      bob = await createAccount('Bob');
      await FollowService(
        auth: alice.auth,
        firestore: alice.db,
      ).follow(bob.uid);
      room = await alice.service.openConversation(
        peerId: bob.uid,
        peerName: 'Bob',
      );
      await entry.value().timeout(const Duration(seconds: 60));
      result['passed'] = true;
    } catch (error) {
      result['error'] = error is FirebaseException
          ? '${error.plugin}/${error.code}'
          : error.toString();
    } finally {
      for (final account in accounts.reversed) {
        await account.auth.signOut();
        await account.db.terminate();
        await account.app.delete();
      }
      accounts.clear();
    }
    results.add(result);
  }
  _browserResults = results.jsify();
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Text(
          'Chat checks: ${results.where((r) => r['passed'] == true).length}/${results.length}',
        ),
      ),
    ),
  );
}
