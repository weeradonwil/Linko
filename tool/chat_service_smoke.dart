// Flutter browser entry point for real ChatService checks against emulators only.
import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:social_app/core/models/chat_models.dart';
import 'package:social_app/core/services/chat_service.dart';

@JS('globalThis.linkoChatTestResults')
external set _browserResults(JSAny? value);

const _options = FirebaseOptions(
  apiKey: 'emulator-only-api-key',
  appId: '1:123456:web:chat-emulator-tests',
  messagingSenderId: '123456',
  projectId: 'demo-linko',
  storageBucket: 'demo-linko.appspot.com',
);

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

Future<void> _permissionDenied(Future<dynamic> operation) async {
  try {
    await operation;
  } on FirebaseException catch (error) {
    _check(error.code == 'permission-denied', 'Unexpected code: ${error.code}');
    return;
  }
  throw StateError('A forbidden operation succeeded');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = <Map<String, Object?>>[];
  final accounts = <_Account>[];
  var serial = 0;
  late _Account alice;
  late _Account bob;
  late String room;

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
    await db.collection('users').doc(account.uid).set({'displayName': name});
    return account;
  }

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
    'reopen visible room and preserve peer hidden state': () async {
      await alice.service.sendMessage(
        conversationId: room,
        peerId: bob.uid,
        text: 'Hello',
      );
      await alice.service.hideConversation(room);
      _check(
        (await alice.service.watchConversations().first).isEmpty,
        'Hidden room filtered',
      );
      _check(
        await alice.service.openConversation(
              peerId: bob.uid,
              peerName: 'Bob',
            ) ==
            room,
        'Reopen hidden room',
      );
      _check(
        await alice.service.openConversation(
              peerId: bob.uid,
              peerName: 'Bob',
            ) ==
            room,
        'Reopen visible room',
      );
      await bob.service.hideConversation(room);
      await alice.service.openConversation(peerId: bob.uid, peerName: 'Bob');
      final hidden = (await summary())['hiddenFor'] as Map;
      _check(
        hidden[alice.uid] == false && hidden[bob.uid] == true,
        'Peer hidden state preserved',
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

  for (final entry in scenarios.entries) {
    final result = <String, Object?>{'name': entry.key, 'passed': false};
    try {
      alice = await createAccount('Alice');
      bob = await createAccount('Bob');
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
