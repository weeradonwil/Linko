import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/utils/avatar_thumbnail.dart';

void main() {
  test('private profile uses its small avatar preview', () {
    expect(
      visibleAvatarPath({
        'isPrivate': true,
        'avatarPath': 'profile_images/u/full.jpg',
        'avatarThumbPath': 'profile_thumbnails/u/small.png',
      }),
      'profile_thumbnails/u/small.png',
    );
    expect(
      visibleAvatarPath({
        'isPrivate': true,
        'avatarPath': 'profile_images/u/full.jpg',
      }),
      isNull,
    );
  });

  testWidgets('avatar thumbnail is resized into a PNG', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 8, 8),
        ui.Paint()..color = const ui.Color(0xFFFF4F64),
      );
      final source = await recorder.endRecording().toImage(8, 8);
      final original = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      final output = await makeAvatarThumbnail(original!.buffer.asUint8List());
      final codec = await ui.instantiateImageCodec(output);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 160);
      expect(frame.image.height, 160);
      frame.image.dispose();
      codec.dispose();
    });
  });
}
