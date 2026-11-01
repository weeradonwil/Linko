import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:social_app/core/services/group_service.dart';
import 'package:social_app/core/services/post_service.dart';
import 'package:social_app/screens/create_post/create_post.dart';

class _User extends Fake implements User {
  @override
  String get displayName => 'dummy';
}

class _Posts extends Fake implements PostService {
  int calls = 0;
  String? content;
  List<String>? tags;
  String? visibility;
  XFile? attachment;
  Object? failure;
  Completer<void>? pending;

  @override
  Future<void> createPost({
    required String content,
    required List<String> tags,
    required String visibility,
    XFile? attachment,
  }) async {
    calls++;
    this.content = content;
    this.tags = tags;
    this.visibility = visibility;
    this.attachment = attachment;
    if (failure != null) throw failure!;
    if (pending != null) await pending!.future;
  }
}

class _Groups extends Fake implements GroupService {
  int calls = 0;
  String? target;

  @override
  Future<void> addPost({
    required String groupId,
    required String content,
    List<String> tags = const [],
    XFile? attachment,
  }) async {
    calls++;
    target = groupId;
  }
}

class _Picker extends Fake implements ImagePicker {
  XFile? image;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => image;
}

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS2kAAAAASUVORK5CYII=',
);

// XFile.fromData ใช้ชื่อไฟล์ต่างกันตามแพลตฟอร์ม จึงแยก fixture ในหน่วยความจำให้แน่นอน
class _ImageFile extends Fake implements XFile {
  @override
  String get name => 'scaled_10.jpg';
  @override
  String get mimeType => 'image/jpeg';
  @override
  Future<int> length() async => _pixel.length;
  @override
  Future<Uint8List> readAsBytes() async => _pixel;
}

Future<void> _open(
  WidgetTester tester,
  _Posts posts, {
  _Picker? picker,
  _Groups? groups,
  String? groupId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CreatePostScreen(
                  user: _User(),
                  postService: posts,
                  imagePicker: picker ?? _Picker(),
                  groupService: groups,
                  groupId: groupId,
                ),
              ),
            ),
            child: const Text('open composer'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open composer'));
  await tester.pumpAndSettle();
}

Finder get _save => find.widgetWithText(TextButton, 'โพสต์');

void main() {
  testWidgets('text post submits once and closes the composer', (tester) async {
    final posts = _Posts();
    await _open(tester, posts);
    await tester.enterText(find.byType(TextFormField).first, 'Morning 🌅');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(posts.calls, 1);
    expect(posts.content, 'Morning 🌅');
    expect(posts.visibility, 'public');
    expect(find.byType(CreatePostScreen), findsNothing);
  });

  testWidgets('photo-only post works without typing a caption', (tester) async {
    final posts = _Posts();
    final picker = _Picker()..image = _ImageFile();
    await _open(tester, posts, picker: picker);
    await tester.ensureVisible(find.text('เพิ่มภาพ'));
    await tester.tap(find.text('เพิ่มภาพ'));
    await tester.pumpAndSettle();
    expect(find.text('scaled_10.jpg'), findsOneWidget);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(posts.content, '');
    expect(posts.attachment, same(picker.image));
    expect(find.byType(CreatePostScreen), findsNothing);
  });

  testWidgets('empty content displays the service validation message', (
    tester,
  ) async {
    final posts = _Posts()
      ..failure = const PostServiceException(
        'กรุณาใส่ข้อความหรือแนบภาพ/วิดีโอ',
      );
    await _open(tester, posts);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.text('กรุณาใส่ข้อความหรือแนบภาพ/วิดีโอ'), findsOneWidget);
    expect(find.byType(CreatePostScreen), findsOneWidget);
  });

  testWidgets('six tags are rejected before calling Firebase', (tester) async {
    final posts = _Posts();
    await _open(tester, posts);
    await tester.enterText(find.byType(TextFormField).at(1), 'a,b,c,d,e,f');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(posts.calls, 0);
    expect(find.text('ใส่แท็กได้ไม่เกิน 5 รายการ'), findsOneWidget);
  });

  testWidgets('canceling the photo picker keeps the draft', (tester) async {
    final posts = _Posts();
    await _open(tester, posts);
    await tester.enterText(find.byType(TextFormField).first, 'draft');
    await tester.ensureVisible(find.text('เพิ่มภาพ'));
    await tester.tap(find.text('เพิ่มภาพ'));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(posts.content, 'draft');
    expect(posts.attachment, isNull);
  });

  testWidgets('missing native plugin gives an app update message', (
    tester,
  ) async {
    final posts = _Posts()
      ..failure = MissingPluginException('FirebaseFunctions#call');
    await _open(tester, posts);
    await tester.enterText(find.byType(TextFormField).first, 'keep this draft');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.textContaining('กรุณาอัปเดตแอปแล้วเปิดใหม่'), findsOneWidget);
    expect(find.text('keep this draft'), findsOneWidget);
    expect(tester.widget<TextButton>(_save).onPressed, isNotNull);
  });

  testWidgets('posting suspension shows the backend reason', (tester) async {
    final posts = _Posts()
      ..failure = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'บัญชีนี้อยู่ระหว่างพักสิทธิ์โพสต์',
      );
    await _open(tester, posts);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.text('บัญชีนี้อยู่ระหว่างพักสิทธิ์โพสต์'), findsOneWidget);
  });

  testWidgets('storage permission error is shown and the draft can retry', (
    tester,
  ) async {
    final posts = _Posts()
      ..failure = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthorized',
      );
    await _open(tester, posts);
    await tester.enterText(find.byType(TextFormField).first, 'retry draft');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.textContaining('Firebase Storage'), findsOneWidget);
    posts.failure = null;
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(posts.calls, 2);
    expect(find.byType(CreatePostScreen), findsNothing);
  });

  testWidgets('Firestore permission error names the rules that rejected save', (
    tester,
  ) async {
    final posts = _Posts()
      ..failure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _open(tester, posts);
    await tester.enterText(find.byType(TextFormField).first, 'draft');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.textContaining('Firestore'), findsOneWidget);
    expect(find.textContaining('Firestore Rules'), findsOneWidget);
  });

  testWidgets('rapid taps while saving do not create duplicate posts', (
    tester,
  ) async {
    final posts = _Posts()..pending = Completer<void>();
    await _open(tester, posts);
    await tester.enterText(find.byType(TextFormField).first, 'one post');
    final button = tester.widget<TextButton>(_save);
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(posts.calls, 1);
    posts.pending!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('group composer calls the group service instead of feed', (
    tester,
  ) async {
    final posts = _Posts();
    final groups = _Groups();
    await _open(tester, posts, groups: groups, groupId: 'real-group');
    await tester.enterText(find.byType(TextFormField).first, 'group post');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(groups.calls, 1);
    expect(groups.target, 'real-group');
    expect(posts.calls, 0);
  });
}
