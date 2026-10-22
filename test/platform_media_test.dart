import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/widgets/post_media.dart';

void main() {
  testWidgets(
    'unsupported desktop video shows a message without plugin errors',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PostMedia(
                path: 'post_media/example/video.mp4',
                type: 'video',
              ),
            ),
          ),
        );
        expect(
          find.text('อุปกรณ์นี้ยังไม่รองรับการเล่นวิดีโอในแอป'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
