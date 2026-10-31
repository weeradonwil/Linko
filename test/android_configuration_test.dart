import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android production manifest declares Internet permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
    // ไม่เปิด cleartext HTTP ใน main/release จากการตั้งค่า Emulator ของ debug
    expect(manifest, isNot(contains('usesCleartextTraffic="true"')));
  });
}
