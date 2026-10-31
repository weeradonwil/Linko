import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/screens/profile/profile_image_screen.dart';

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS2kAAAAASUVORK5CYII=',
);

void main() {
  for (final kind in ProfileImageKind.values) {
    final field = kind == ProfileImageKind.avatar ? 'avatarPath' : 'coverPath';

    testWidgets('public $kind opens and supports zoom', (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileImageScreen(
            ownerUid: 'owner',
            kind: kind,
            readViewerUid: () => 'reader',
            profileStream: Stream.value({
              'isPrivate': false,
              field: 'real/path.png',
            }),
            loadImage: (_) async {
              reads++;
              return _pixel;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('private $kind denies other users before reading the file', (
      tester,
    ) async {
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileImageScreen(
            ownerUid: 'owner',
            kind: kind,
            readViewerUid: () => 'reader',
            profileStream: Stream.value({
              'isPrivate': true,
              field: 'real/path.png',
            }),
            loadImage: (_) async {
              reads++;
              return _pixel;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.text('บัญชีส่วนตัว เปิดดูรูปใหญ่ไม่ได้'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('owner can open their own private $kind', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileImageScreen(
            ownerUid: 'owner',
            kind: kind,
            readViewerUid: () => 'owner',
            profileStream: Stream.value({
              'isPrivate': true,
              field: 'real/path.png',
            }),
            loadImage: (_) async => _pixel,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changing to private removes an already open image', (
    tester,
  ) async {
    final profiles = StreamController<Map<String, dynamic>?>();
    addTearDown(profiles.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileImageScreen(
          ownerUid: 'owner',
          kind: ProfileImageKind.cover,
          readViewerUid: () => 'reader',
          profileStream: profiles.stream,
          loadImage: (_) async => _pixel,
        ),
      ),
    );
    profiles.add({'isPrivate': false, 'coverPath': 'real/cover.png'});
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    profiles.add({
      'isPrivate': false,
      'privacyTarget': true,
      'coverPath': 'real/cover.png',
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('บัญชีส่วนตัว เปิดดูรูปใหญ่ไม่ได้'), findsOneWidget);
  });

  testWidgets('a pending image cannot appear after privacy is revoked', (
    tester,
  ) async {
    final profiles = StreamController<Map<String, dynamic>?>();
    final image = Completer<Uint8List?>();
    addTearDown(profiles.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileImageScreen(
          ownerUid: 'owner',
          kind: ProfileImageKind.avatar,
          readViewerUid: () => 'reader',
          profileStream: profiles.stream,
          loadImage: (_) => image.future,
        ),
      ),
    );
    profiles.add({'isPrivate': false, 'avatarPath': 'real/avatar.png'});
    await tester.pump();
    await tester.pump();
    profiles.add({'isPrivate': true, 'avatarPath': 'real/avatar.png'});
    await tester.pump();
    image.complete(_pixel);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing photo shows an empty state without calling Storage', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileImageScreen(
          ownerUid: 'owner',
          kind: ProfileImageKind.avatar,
          readViewerUid: () => 'reader',
          profileStream: Stream.value({'isPrivate': false}),
          loadImage: (_) async => throw StateError('must not load'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีรูปภาพ'), findsOneWidget);
  });

  testWidgets('deleted account shows a missing-account state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileImageScreen(
          ownerUid: 'owner',
          kind: ProfileImageKind.avatar,
          readViewerUid: () => 'reader',
          profileStream: Stream.value(null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบบัญชีนี้'), findsOneWidget);
  });

  testWidgets('profile read failure hides the photo and shows an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileImageScreen(
          ownerUid: 'owner',
          kind: ProfileImageKind.avatar,
          readViewerUid: () => 'reader',
          profileStream: Stream.error(StateError('offline')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('เปิดรูปไม่สำเร็จ ลองเข้ามาใหม่นะ'), findsOneWidget);
  });

  testWidgets('failed image load can retry successfully', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileImageScreen(
          ownerUid: 'owner',
          kind: ProfileImageKind.avatar,
          readViewerUid: () => 'reader',
          profileStream: Stream.value({
            'isPrivate': false,
            'avatarPath': 'real/avatar.png',
          }),
          loadImage: (_) async {
            if (++reads == 1) throw StateError('offline');
            return _pixel;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('โหลดรูปไม่สำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
