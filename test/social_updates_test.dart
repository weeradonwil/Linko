import 'package:social_app/core/utils/cover_crop.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/models/post.dart';
import 'package:social_app/core/models/reaction_summary.dart';
import 'package:social_app/core/widgets/cover_editor.dart';
import 'package:social_app/core/widgets/reaction_people_sheet.dart';

void main() {
  // ตัวเลขในแถบยอดต้องไม่เอา Like/Dislike ไปปนกับอารมณ์อื่น
  test('reaction summary keeps like and dislike separate', () {
    expect(
      ReactionSummary.visible({'like': 12, 'love': 3, 'haha': 2, 'dislike': 2}),
      {'like': 12, 'other': 5, 'dislike': 2},
    );
  });
  test('a single other reaction keeps its own emoji', () {
    expect(ReactionSummary.visible({'like': 2, 'love': 1}), {
      'like': 2,
      'love': 1,
    });
  });
  test('zero and unknown reactions are not displayed', () {
    expect(ReactionSummary.visible({'like': 0, 'unknown': 99}), isEmpty);
  });
  test('legacy posts still parse without a shared source', () {
    expect(Post.fromData('old', {}).sharedPostId, isNull);
  });
  test('shared source survives parsing without duplicating media', () {
    final post = Post.fromData('share', {
      'sharedPostId': 'original',
      'content': '',
    });
    expect(post.sharedPostId, 'original');
    expect(post.mediaPath, isNull);
  });
  testWidgets('summary renders another label and separate counters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReactionSummaryBar(
            counts: {'like': 12, 'love': 3, 'haha': 2, 'dislike': 2},
            path: 'posts/example/reactions',
          ),
        ),
      ),
    );
    expect(find.text('👍 12'), findsOneWidget);
    expect(find.text('อื่นๆ 5'), findsOneWidget);
    expect(find.text('👎 2'), findsOneWidget);
  });
  testWidgets('cover crop exports an actual 1200 by 400 PNG', (tester) async {
    final bytes = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.red, BlendMode.src);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 32, 32),
        Paint()..color = Colors.blue,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 32);
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      return data;
    }))!;
    await tester.pumpWidget(MaterialApp(home: CoverEditor(bytes: bytes)));
    await tester.pumpAndSettle();
    expect(find.text('จัดรูปปก'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    await tester.runAsync(() async {
      final data = await cropProfileCover(bytes, x: 1, y: -1);
      final codec = await ui.instantiateImageCodec(data);
      final cropped = (await codec.getNextFrame()).image;
      expect(cropped.width, 1200);
      expect(cropped.height, 400);
      cropped.dispose();
      codec.dispose();
    });
    await tester.pumpAndSettle();
    expect(find.text('ใช้รูปนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
