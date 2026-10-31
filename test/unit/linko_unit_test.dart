// ชุด Unit Test สำหรับรายงาน: เรียก logic จริงโดยไม่เชื่อมต่อ Firebase
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/models/chat_models.dart';
import 'package:social_app/core/models/post.dart';
import 'package:social_app/core/models/post_policy.dart';
import 'package:social_app/core/models/social_reaction.dart';
import 'package:social_app/core/utils/latest_request.dart';

void main() {
  test('TC01 supports seven unique reactions with correct emoji', () {
    // Arrange: กำหนด ID และอีโมจิที่ระบบต้องรองรับ
    const expected = {
      'like': '👍',
      'love': '❤️',
      'haha': '😂',
      'wow': '😮',
      'sad': '😢',
      'angry': '😡',
      'dislike': '👎',
    };

    // Act: อ่านรายการและค้นหา reaction จากโค้ดจริง
    final ids = SocialReaction.options.map((reaction) => reaction.id).toList();
    final actual = {
      for (final id in expected.keys) id: SocialReaction.byId(id)?.emoji,
    };

    // Assert: มีครบ 7 รายการ ไม่ซ้ำ และจับคู่ ID กับอีโมจิถูกต้อง
    expect(ids, hasLength(7));
    expect(ids.toSet(), hasLength(7));
    expect(actual, expected);
  });

  test('TC02 unknown reaction returns null', () {
    // Arrange
    const unknownId = 'unsupported_reaction';

    // Act
    final result = SocialReaction.byId(unknownId);

    // Assert
    expect(result, isNull);
  });

  test('TC03 text-only post is valid', () {
    // Arrange
    const text = 'สวัสดี Linko';

    // Act
    final result = PostPolicy.hasContent(text, hasMedia: false);

    // Assert
    expect(result, isTrue);
  });

  test('TC04 media-only post is valid', () {
    // Arrange
    const text = '';

    // Act
    final result = PostPolicy.hasContent(text, hasMedia: true);

    // Assert
    expect(result, isTrue);
  });

  test('TC05 blank post without media is invalid', () {
    // Arrange
    const text = '   \n\t';

    // Act
    final result = PostPolicy.hasContent(text, hasMedia: false);

    // Assert
    expect(result, isFalse);
  });

  test('TC06 pending privacy target overrides current profile setting', () {
    // Arrange: กำลังเปลี่ยนบัญชีจากสาธารณะเป็นส่วนตัว
    final profile = <String, dynamic>{
      'isPrivate': false,
      'privacyTarget': true,
    };

    // Act
    final result = PostPolicy.profileIsPrivate(profile);

    // Assert
    expect(result, isTrue);
  });

  test(
    'TC07 explicitly private post stays private for either profile mode',
    () {
      // Arrange
      const visibility = 'private';

      // Act
      final publicProfileResult = PostPolicy.audience(false, visibility);
      final privateProfileResult = PostPolicy.audience(true, visibility);

      // Assert
      expect(publicProfileResult, 'private');
      expect(privateProfileResult, 'private');
    },
  );

  test('TC08 malformed post data uses safe defaults', () {
    // Arrange: จำลองข้อมูลที่เก็บชนิดข้อมูลผิดใน document เก่า
    final data = <String, dynamic>{
      'userId': 1,
      'authorName': [],
      'content': false,
      'tags': [123, 'valid'],
      'createdAt': 'bad-date',
      'mediaPath': 42,
    };

    // Act
    final post = Post.fromData('legacy-post', data);

    // Assert
    expect(post.authorName, 'สมาชิก');
    expect(post.content, '');
    expect(post.tags, ['valid']);
    expect(post.mediaPath, isNull);
    expect(post.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
  });

  test('TC09 malformed conversation data uses safe defaults', () {
    // Arrange
    final data = <String, dynamic>{
      'participantIds': ['me', 'peer', 123],
      'participantNames': 'invalid-map',
      'unreadCounts': {'me': 'not-a-number'},
      'hiddenFor': false,
    };

    // Act
    final room = ConversationSummary.fromData('legacy-chat', data, 'me');

    // Assert
    expect(room.participantIds, ['me', 'peer']);
    expect(room.peerName('me'), 'สมาชิก');
    expect(room.unreadCount, 0);
    expect(room.isHidden, isFalse);
  });

  test('TC10 slower old request cannot overwrite latest result', () async {
    // Arrange: ควบคุมลำดับการตอบกลับโดยไม่พึ่งอินเทอร์เน็ตหรือเวลาหน่วง
    final guard = LatestRequest();
    final oldRequest = Completer<String>();
    final latestRequest = Completer<String>();
    String? displayed;

    Future<void> load(Future<String> request) async {
      final version = guard.next();
      final result = await request;
      if (guard.accepts(version)) {
        displayed = result;
      }
    }

    // Act: ส่งคำขอเก่าก่อน แต่ให้คำขอใหม่ตอบกลับก่อน
    final oldTask = load(oldRequest.future);
    final latestTask = load(latestRequest.future);
    latestRequest.complete('latest result');
    await latestTask;
    oldRequest.complete('old result');
    await oldTask;

    // Assert: ข้อมูลเก่าต้องไม่ทับข้อมูลล่าสุด
    expect(displayed, 'latest result');
  });
}
