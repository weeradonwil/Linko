# รายงานและคู่มือทำ Unit Test: แอป Linko

ชื่อผู้จัดทำ: ____________________  รหัสนักศึกษา: ____________________

รายวิชา / อาจารย์ผู้สอน: ____________________

## 1. วัตถุประสงค์และขอบเขต

ทดสอบ logic ของโค้ดจริงในแอป Linko จำนวน **10 test cases** ด้วย `flutter_test` โดยทุกเคสประกาศด้วย `test()` และไม่มี `testWidgets()` ในชุดนี้

ครอบคลุมรายการ reaction การตรวจเนื้อหาโพสต์ นโยบายความเป็นส่วนตัว การอ่านข้อมูลโพสต์และแชทที่ผิดรูปแบบ และการรับผลคำขอแบบ asynchronous

ข้อมูล Map ในเคสเป็นข้อมูลนำเข้าสำหรับทดสอบ ไม่ได้เขียนลงฐานข้อมูลจริง ไม่ต้องเปิด Android Emulator หรือเข้าสู่ระบบ Firebase เพื่อรันชุดนี้

ชุดนี้ตรวจ logic ในหน่วยที่เรียกทดสอบ จึงไม่ได้ยืนยันการส่งข้อความจริง การอัปโหลดไฟล์ หน้าจอ หรือ Firestore Security Rules; ส่วนเหล่านั้นต้องทดสอบเพิ่มเติมแบบ integration / ระบบจริง

## 2. สภาพแวดล้อมและผลการรันจริง

| รายการ | ค่า |
| --- | --- |
| เริ่มรัน | 2026-10-30T18:25:12+07:00 |
| จบรัน | 2026-10-30T18:25:24+07:00 |
| ระบบปฏิบัติการ | Windows |
| Flutter | 3.47.0 |
| Dart | 3.13.0 |
| โค้ดฐานก่อนเพิ่มชุดทดสอบ | `f4d9d21` |
| ไฟล์ทดสอบ | `test/unit/linko_unit_test.dart` |
| จำนวน test cases | 10 |
| ผ่าน | 10 |
| ไม่ผ่าน | 0 |
| Exit code | 0 |

โค้ดทดสอบและรายงานเป็นไฟล์ที่เพิ่มใน workspace หลังโค้ดฐานข้างต้น ส่วนโค้ดแอปใน `lib/` ไม่ได้แก้ไขในงานนี้

ครั้งนี้รัน Flutter tool ผ่าน Dart และ `flutter_tools.snapshot` ของ SDK ที่ติดตั้งอยู่ โดยใช้คำสั่ง `test --no-pub --reporter expanded test/unit/linko_unit_test.dart` รายการ argument จริงบันทึกใน [unit_test_run.json](unit_test_run.json) สามารถรันซ้ำผ่านคำสั่ง `flutter test` ตามขั้นตอนด้านล่างได้

## 3. สรุป Test Cases

| เคส | สิ่งที่ทดสอบ | ข้อมูลนำเข้า / เงื่อนไข | ผลที่คาดหวัง | ผลจริง |
| --- | --- | --- | --- | --- |
| TC01 | รองรับ reaction ครบและไม่ซ้ำ | ID ของ reaction ทั้ง 7 แบบ | มี 7 รายการ ไม่ซ้ำ และอีโมจิตรงกับ ID | ผ่าน |
| TC02 | ค้นหา reaction ที่ไม่มีในระบบ | `unsupported_reaction` | `null` | ผ่าน |
| TC03 | ตรวจโพสต์ที่มีเฉพาะข้อความ | `สวัสดี Linko`, `hasMedia: false` | `true` | ผ่าน |
| TC04 | ตรวจโพสต์ที่มีเฉพาะสื่อ | ข้อความว่าง, `hasMedia: true` | `true` | ผ่าน |
| TC05 | ปฏิเสธโพสต์ว่างและไม่มีสื่อ | ช่องว่าง ขึ้นบรรทัดใหม่ และแท็บ, `hasMedia: false` | `false` | ผ่าน |
| TC06 | ใช้สถานะความเป็นส่วนตัวที่กำลังเปลี่ยน | `isPrivate: false`, `privacyTarget: true` | `true` | ผ่าน |
| TC07 | รักษาสิทธิ์โพสต์ที่ตั้งเป็นส่วนตัว | `visibility: private` ทั้งบัญชีสาธารณะและบัญชีส่วนตัว | `private` ทั้งสองกรณี | ผ่าน |
| TC08 | อ่านโพสต์เก่าที่ชนิดข้อมูลผิด | ชื่อเป็น List, ข้อความเป็น bool, tags ปนตัวเลข, วันที่ผิด, path เป็นตัวเลข | ชื่อเป็น สมาชิก, ข้อความว่าง, tags เหลือ valid, path เป็น null, วันที่เป็น epoch | ผ่าน |
| TC09 | อ่านข้อมูลสรุปแชทที่ชนิดข้อมูลผิด | รายชื่อปนตัวเลข, ชื่อคู่สนทนาไม่ใช่ Map, ยอดยังไม่อ่านไม่ใช่ตัวเลข | กรอง ID เหลือ me/peer, ชื่อเป็น สมาชิก, ยอดยังไม่อ่านเป็น 0, isHidden เป็น false | ผ่าน |
| TC10 | ป้องกันผลคำขอเก่าทับข้อมูลล่าสุด | เริ่มคำขอเก่าก่อน แต่ให้คำขอใหม่ตอบกลับก่อน | `displayed` ยังคงเป็น `latest result` | ผ่าน |

**หนึ่ง `test()` นับเป็นหนึ่ง test case** แม้ภายในจะมีหลาย `expect()` ชุดนี้จึงมี 10 เคสตามรายการ TC01–TC10

## 4. สอนรันทีละขั้นตอน

### ขั้นที่ 1: เปิด Terminal ใน VS Code

เลือกเมนู **Terminal → New Terminal** แล้วเข้าโฟลเดอร์โปรเจกต์:

```powershell
cd C:\flutter\social_app
```

ตรวจว่ามีไฟล์ `pubspec.yaml` และไฟล์ `test/unit/linko_unit_test.dart` ในโปรเจกต์นี้ หากเพิ่งดาวน์โหลดโปรเจกต์หรือยังไม่ได้ติดตั้ง dependencies ให้รัน:

```powershell
flutter pub get
```

### ขั้นที่ 2: รันครบ 10 เคส

```powershell
flutter test test/unit/linko_unit_test.dart --reporter expanded
```

คำสั่งเทียบเท่ากับรอบที่บันทึกหลักฐานนี้ โดยข้ามขั้นตอนดาวน์โหลด dependencies ที่มีอยู่แล้ว:

```powershell
flutter test --no-pub --reporter expanded test/unit/linko_unit_test.dart
```

- `flutter test` เรียกตัวรันทดสอบของ Flutter
- Path ถัดไปเลือกไฟล์ทดสอบที่ต้องการรัน
- `--reporter expanded` แสดงชื่อแต่ละเคสเป็นบรรทัด อ่านและเก็บหลักฐานได้ง่าย
- เมื่อสำเร็จต้องมีบรรทัด `+10: All tests passed!`

### ขั้นที่ 3: รันทีละเคส

ใช้ `--plain-name` เพื่อเลือกชื่อเคสที่มี ID ตรงกับที่ระบุ คำสั่งต่อไปนี้เป็นตัวเลือกให้รันทีละบรรทัด:

```powershell
flutter test test/unit/linko_unit_test.dart --plain-name "TC01" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC02" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC03" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC04" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC05" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC06" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC07" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC08" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC09" --reporter expanded
flutter test test/unit/linko_unit_test.dart --plain-name "TC10" --reporter expanded
```

เมื่อรันหนึ่งเคสสำเร็จ สรุปท้าย output จะเป็น `+1: All tests passed!` การรันครบทั้งไฟล์ในขั้นที่ 2 แสดงหลักฐานครบ 10 เคสอยู่แล้ว จึงเลือกใช้ตามรูปแบบที่อาจารย์ต้องการได้

### ขั้นที่ 4: เก็บ output เป็นไฟล์

```powershell
flutter test test/unit/linko_unit_test.dart --reporter expanded 2>&1 | Tee-Object -FilePath test_reports/unit_test_output_rerun.txt
```

คำสั่งนี้แสดงผลบน Terminal และบันทึกเป็นไฟล์ใหม่พร้อมกัน โดยเก็บหลักฐานรอบที่เตรียมไว้แล้วใน `unit_test_output.txt`

## 5. อ่านและอธิบายโค้ดทดสอบอย่างไร

แต่ละเคสใช้รูปแบบ **Arrange → Act → Assert**:

1. **Arrange — เตรียมข้อมูล:** เช่น ข้อความว่างและไม่มีสื่อ
2. **Act — เรียกฟังก์ชันจริง:** เช่น `PostPolicy.hasContent(text, hasMedia: false)`
3. **Assert — ตรวจผล:** เช่น `expect(result, isFalse)`

`expect(actual, expected)` ใช้ตรวจว่าผลจริงตรงกับผลที่คาดหวัง ถ้าไม่ตรง เคสจะไม่ผ่าน พร้อมแสดงรายละเอียดว่าคาดหวังอะไรและได้อะไร

เคส TC05 คาดหวัง `false` และยังนับว่า **เทสผ่าน** เมื่อฟังก์ชันคืน `false` เพราะเป็นการตรวจว่าระบบปฏิเสธข้อมูลไม่ถูกต้องได้ตามที่ออกแบบไว้

สำหรับ TC10 ใช้ `Completer` ควบคุมว่าคำขอใดตอบกลับก่อน จึงตรวจสถานการณ์คำขอเก่าตอบช้าได้โดยไม่ต้องรอเครือข่ายจริง

## 6. โค้ดทดสอบครบทั้ง 10 เคส

ต้นฉบับที่รันจริง: [linko_unit_test.dart](../test/unit/linko_unit_test.dart)

โค้ดแต่ละเคสระบุ TC01–TC10 และมีคอมเมนต์ Arrange / Act / Assert ให้อ่านประกอบได้:

```dart
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
```

ชื่อเคสใน output ตรงกับโค้ดดังนี้:

- **TC01**: `TC01 supports seven unique reactions with correct emoji`
- **TC02**: `TC02 unknown reaction returns null`
- **TC03**: `TC03 text-only post is valid`
- **TC04**: `TC04 media-only post is valid`
- **TC05**: `TC05 blank post without media is invalid`
- **TC06**: `TC06 pending privacy target overrides current profile setting`
- **TC07**: `TC07 explicitly private post stays private for either profile mode`
- **TC08**: `TC08 malformed post data uses safe defaults`
- **TC09**: `TC09 malformed conversation data uses safe defaults`
- **TC10**: `TC10 slower old request cannot overwrite latest result`

## 7. Output จากการรันจริง

คัดลอกจาก [unit_test_output.txt](unit_test_output.txt) ซึ่งบันทึกจาก process ที่รันจริง ไม่มีการสร้างผลทดสอบจำลอง:

```text
00:00 +0: loading C:/flutter/social_app/test/unit/linko_unit_test.dart
00:00 +0: TC01 supports seven unique reactions with correct emoji
00:00 +1: TC02 unknown reaction returns null
00:00 +2: TC03 text-only post is valid
00:00 +3: TC04 media-only post is valid
00:00 +4: TC05 blank post without media is invalid
00:00 +5: TC06 pending privacy target overrides current profile setting
00:00 +6: TC07 explicitly private post stays private for either profile mode
00:00 +7: TC08 malformed post data uses safe defaults
00:00 +8: TC09 malformed conversation data uses safe defaults
00:00 +9: TC10 slower old request cannot overwrite latest result
00:00 +10: All tests passed!
```

บรรทัดชื่อเคสแสดงขณะที่กำลังเริ่มรันเคสนั้น ตัวเลข `+0`, `+1`, … หมายถึงจำนวนเคสที่ผ่านแล้วในขณะนั้น ส่วนสรุป `+10: All tests passed!` และ exit code 0 ยืนยันว่ารอบนี้ผ่านครบ 10 เคส

## 8. วิธีแคปภาพ Terminal เพื่อส่งอาจารย์

1. รันคำสั่งในขั้นที่ 2
2. ขยาย Terminal ให้เห็นคำสั่ง ชื่อ TC01–TC10 และบรรทัดสรุป
3. กด **Windows + Shift + S** แล้วเลือกพื้นที่ Terminal
4. ถ้าภาพเดียวไม่พอ ให้แบ่งสองภาพให้เห็นชื่อเคสครบและมีภาพสรุปท้าย
5. ถ้าต้องการภาพแยกทุกเคส ให้รันทีละบรรทัดจากขั้นที่ 3 แล้วแคปแต่ละครั้ง

โจทย์อนุญาตให้ส่ง output ได้ จึงแนบ `unit_test_output.txt` แทนภาพหน้าจอได้ด้วย ไฟล์ที่เตรียมไว้เป็นหลักฐานแบบ output ยังไม่ได้แคปภาพ Terminal

## 9. ไฟล์สำหรับส่งงาน

- **รายงาน:** ไฟล์นี้ (`test_reports/UNIT_TEST_REPORT.md`) สามารถคัดลอกเนื้อหาไปจัดหน้าใน Word ตามรูปแบบรายวิชา
- **โค้ด:** `test/unit/linko_unit_test.dart`
- **ผลการรันจริง:** `test_reports/unit_test_output.txt`
- **ข้อมูลรอบทดสอบ:** `test_reports/unit_test_run.json`
- **ภาพหน้าจอ:** เพิ่มได้ตามขั้นตอนข้อ 8 หากอาจารย์ต้องการ

ก่อนส่ง ให้กรอกชื่อ รหัสนักศึกษา และข้อมูลรายวิชาด้านบน หากต้องการให้อาจารย์รันซ้ำ ควรส่งพร้อมโปรเจกต์ Flutter หรือแนบที่อยู่ repository ที่เข้าถึงได้ เพราะไฟล์ทดสอบ import โค้ดจริงจาก `lib/`

## 10. ตัวอย่างสรุปผลสำหรับรายงาน

> ทดสอบ Unit Test ของแอป Linko จำนวน 10 เคส โดยครอบคลุม reaction การตรวจเนื้อหาโพสต์ นโยบายความเป็นส่วนตัว การแปลงข้อมูลที่ผิดรูปแบบ และการจัดการผลคำขอ asynchronous ผลการรันเมื่อวันที่ 30 ตุลาคม 2026 ผ่านทั้งหมด 10 เคส ไม่ผ่าน 0 เคส มีหลักฐานเป็น source code และ output จาก Terminal ทั้งนี้ผลดังกล่าวครอบคลุมหน่วย logic ที่ทดสอบในชุดนี้
