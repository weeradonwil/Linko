import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.justsoft.xyz/video_thumbnail');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'file'
          ? 'thumbnail.jpg'
          : Uint8List.fromList([1, 2, 3]);
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('thumbnailFile forwards supported native parameters', () async {
    final result = await VideoThumbnail.thumbnailFile(
        video: 'video.mp4',
        thumbnailPath: 'thumbnail.jpg',
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        maxHeight: 480,
        timeMs: 1000,
        quality: 68);
    expect(result, 'thumbnail.jpg');
    expect(calls.single.method, 'file');
    expect(calls.single.arguments, {
      'video': 'video.mp4',
      'headers': null,
      'path': 'thumbnail.jpg',
      'format': 0,
      'maxh': 480,
      'maxw': 720,
      'timeMs': 1000,
      'quality': 68,
    });
  });
  test('thumbnailData returns native bytes', () async {
    expect(await VideoThumbnail.thumbnailData(video: 'video.mp4'), [1, 2, 3]);
    expect(calls.single.method, 'data');
  });
}
