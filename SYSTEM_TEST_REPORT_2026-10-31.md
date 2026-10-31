# ตรวจระบบ Linko และแก้โพสต์ไม่ได้ — 31 ตุลาคม 2026

สถานะ: ตรวจรับทุกชุดที่รายงานด้านล่างผ่านแล้ว และติดตั้ง Linko ปกติรุ่น 1.1.0+4 ลง AVD เดิมโดยเก็บข้อมูลบัญชีเดิมไว้

## 1. สาเหตุที่โพสต์ไม่ได้

APK ที่ติดตั้งใน Android Emulator เป็น `1.0.2+3` และ **ไม่มีคลาส `FlutterFirebaseFunctionsPlugin` ใน DEX** ขณะที่ source ใหม่เรียก `reserveWrite` ผ่าน Cloud Functions ก่อนอัปโหลด/บันทึกโพสต์ การ Hot Reload จึงเพิ่มส่วน native นี้ให้ไม่ได้

หลักฐานที่ตรวจแบบอ่านอย่างเดียว:

- APK เดิมมี Firestore และ Storage plugins แต่ไม่มี Functions plugin
- บัญชีที่อยู่ในภาพยืนยันอีเมลแล้ว ไม่ถูกปิดบัญชี และไม่พบสถานะพักสิทธิ์โพสต์
- Rules ที่ deploy ตรงกับไฟล์ในเครื่อง; indexes 15 รายการ READY, Functions 9 ตัว ACTIVE, Scheduler 4 jobs ENABLED
- ไม่พบคำขอ authenticated `reserveWrite` จากความพยายามโพสต์นั้นใน log ที่ตรวจ จึงสอดคล้องกับการล้มเหลวก่อนถึง backend

วิธีแก้คือ build และติดตั้ง APK ใหม่ทั้งแอปด้วย `install -r` เพื่อเก็บข้อมูลบัญชีเดิม ไม่ใช่แก้ Rules ให้เปิดกว้างขึ้น

## 2. สิ่งที่แก้และรวมในรอบนี้

| ส่วน | สิ่งที่เปลี่ยน |
|---|---|
| ฟอร์มโพสต์ | แสดง error แยกตามสาเหตุจริง รวมกรณีปลั๊กอิน native ขาด; กันกดปุ่มบน/ล่างติดกันจนส่งซ้ำ |
| Android | เพิ่ม INTERNET permission ใน main manifest เพื่อให้ build ปกติใช้อินเทอร์เน็ตได้ด้วย; HTTP สำหรับ Emulator เปิดเฉพาะ debug |
| หน้าดูรูป | แก้ปุ่มลองโหลดใหม่ที่คืน Future ใน `setState`; เพิ่มช่องทางทดสอบ Loading/Empty/Error และการถอนสิทธิ์ขณะโหลด |
| ปุ่มใต้โพสต์ | แสดงไอคอน ถูกใจ → ไม่ถูกใจ → ความคิดเห็น → แชร์; กดค้างเลือกอิโมจิได้เหมือนเดิม |
| หน้าฟีด | แถบ Linko แสดงค้าง; ซ่อนเฉพาะช่องสร้างโพสต์ตามทิศทางการเลื่อนเหมือนแถบล่าง |
| แจ้งเตือน | ย้ายทางลัดคำเตือน/สิทธิ์โพสต์จากฟีดไปอยู่ในหน้าแจ้งเตือน |
| รูปโปรไฟล์และภาพปก | แตะเพื่อดูภาพใหญ่และซูม; บัญชีส่วนตัวให้เจ้าของดูได้ คนอื่นเปิดหน้าดูรูปใหญ่ไม่ได้ |
| Regression tests | เพิ่มฟอร์มโพสต์, แถบเลื่อน, ไอคอน, สิทธิ์ดูรูป, Android manifest และโพสต์รูปอย่างเดียวเมื่อเปิด write tickets |

ไฟล์สำคัญ:

- `lib/screens/create_post/create_post.dart`, `lib/core/utils/firebase_error_message.dart`
- `android/app/src/main/AndroidManifest.xml`, `android/app/src/debug/AndroidManifest.xml`
- `lib/screens/profile/profile.dart`, `lib/screens/profile/profile_image_screen.dart`
- `lib/screens/home/home.dart`, `lib/core/widgets/social_navigation.dart`
- `lib/core/widgets/post_action_button.dart`, `lib/core/widgets/group_post_card.dart`
- `lib/screens/notifications/notifications_screen.dart`
- `test/create_post_screen_test.dart`, `test/feed_controls_test.dart`, `test/profile_image_screen_test.dart`, `test/android_configuration_test.dart`
- `tool/social_service_smoke.dart`, `tool/android_post_smoke.dart`, `tool/run_android_post_smoke.mjs`, `tool/run_social_validation.mjs`

## 3. วิธีตรวจทีละขั้น

1. เก็บสถานะ Git และอ่าน flow ของ Auth → ฟอร์ม → ticket → Storage → Firestore
2. รันชุดเดิมเป็น baseline: Flutter 73 เคส, backend 14 เคส, Chrome 15 flows, Rules 7 suites และฟีเจอร์ backend 25 เคส ผ่าน
3. ตรวจ Firebase production แบบอ่านอย่างเดียว และตรวจ plugin ใน APK ที่ติดตั้ง
4. แก้สาเหตุและเพิ่ม regression tests ก่อนรันซ้ำ
5. รัน Flutter ทั้งชุดพร้อม coverage และ unit tests ของ local video_thumbnail package
6. ทดสอบบริการ Flutter จริงบน Chrome พร้อม Firebase Auth/Firestore/Storage/Functions Emulators
7. ทดสอบ Android native กับ emulators: ข้อความ, รูปอย่างเดียว, แก้โพสต์, รูปในกลุ่ม และลบพร้อม cleanup
8. ติดตั้งคืนเป็น Linko build ปกติ รักษาข้อมูลเดิม แล้วบันทึกหลักฐานก่อน commit/push

## 4. ผลตรวจรับ

| ชุดทดสอบ | ผล |
|---|---|
| Static analyzer | No issues found |
| Flutter unit/widget ทั้งหมด | 101/101 ผ่าน |
| Local video_thumbnail unit tests | 2/2 ผ่าน |
| Backend policy unit tests | 14/14 ผ่าน |
| ChatService จริงบน Chrome | 6/6 ผ่าน |
| Social services จริงบน Chrome | 10/10 ผ่าน |
| Firebase Rules เดิม | 7/7 suites ผ่าน |
| Firebase feature integration | 25/25 ผ่าน |
| Native Android กับ Firebase Emulator | 5/5 ผ่าน |
| Android debug build | ผ่าน; ติดตั้งคืนเป็น Linko 1.1.0+4 |
| Production readiness | ตรวจอ่านอย่างเดียวผ่าน ไม่มี test writes/deploy |

หลักฐานอยู่ใน [test_reports/system_2026-10-31/summary.json](test_reports/system_2026-10-31/summary.json) และ output แต่ละชุดในโฟลเดอร์เดียวกัน ไม่แนบ raw Firebase debug log, token, อีเมลผู้ใช้ หรือ APK เข้า Git

APK ในเครื่อง: `build/app/outputs/flutter-apk/Linko-1.1.0-debug.apk` มี Functions native plugin แล้ว SHA-256: `78cdc0ef880bb8020e2033d76547b2444456bdec55e89d33e62755f7e679c779`

ระหว่างตรวจรับมีการรันซ้ำเพราะ assertion เดิมอ่าน ticket ที่ถูกลบด้วยสิทธิ์ client, AVD ปิดไปก่อนเริ่ม Android และ key จำลองไม่ผ่านการตรวจรูปแบบของ native SDK แก้เฉพาะ fixture/runner แล้วทดสอบผ่าน โดยไม่ได้ลดสิทธิ์ Rules

## 5. ขอบเขตและงานที่ควรทำต่อ

- รันทดสอบทุกชุดที่ใช้งานได้ในโปรเจกต์ ไม่ได้หมายความว่าพิสูจน์ทุกบรรทัดหรือทุก gesture บนทุกอุปกรณ์แล้ว
- Unit/widget line coverage ของไฟล์ที่ถูก instrument อยู่ที่ **16.28% (1,109/6,813 บรรทัด, 66 ไฟล์)** ผล integration ของ Chrome/Android ไม่ถูกรวมในเปอร์เซ็นต์นี้ ควรเพิ่ม screen E2E และ unit tests ของ service ต่อ
- ยังไม่ได้ทดสอบ runtime บนโทรศัพท์จริง, iOS/macOS/Linux หรือ signed release เนื่องจากชุดตรวจนี้ใช้ Windows/Chrome/Android Emulator และ debug APK
- การห้ามเปิดรูปใหญ่ของบัญชีส่วนตัวเป็นกติกาใน UI และมีการตรวจโปรไฟล์ซ้ำระหว่างเปิด หน้าตัวอย่างเดิมยังใช้ไฟล์เดียวกับรูปจริง และ Storage ของ avatar ยังให้สมาชิกอ่านได้ ส่วน cover ให้ผู้ติดตามที่อนุมัติอ่านได้ หากต้องการป้องกันการดึงไฟล์ต้นฉบับนอกแอป ต้องแยก thumbnail/ต้นฉบับ และปรับ Storage Rules/URL tokens เป็นอีกงาน
- Write ticket มีอายุ 5 นาทีและขอก่อนอัปโหลด ควรเพิ่มการต่อสิทธิ์/ออก ticket ใหม่เมื่ออัปโหลดนาน รวมทั้งทดสอบเครือข่ายช้ามากและไฟล์ใกล้ 50 MB
- Search ยังใช้การสแกนเป็นหน้าและ feed เพิ่ม listeners ตามช่วงที่โหลด ควรวัดต้นทุนและเวลาตอบสนองด้วยข้อมูลจำนวนมาก
- คำเตือน Kotlin/Gradle จาก dependencies ยังมี แต่ build debug ผ่าน ควรวางแผน migration ก่อนอัปเกรด toolchain major
- ตัวอย่าง upstream `packages/video_thumbnail/example` เป็น Dart ก่อน null safety และ test ถูก comment ไว้ ไม่ใช่แอป Linko จึงไม่ใช้เป็นเกณฑ์ผ่าน runtime; ตัว local plugin มี unit tests แยกและรันจริง
- ไม่สร้างโพสต์/รายงาน/ข้อความทดสอบใน production และไม่ได้ deploy เปลี่ยนนโยบาย moderation ในรอบนี้

## 6. รันซ้ำ

เริ่มจาก root ของ Flutter project ที่มี `pubspec.yaml`:

```powershell
cd C:\flutter\social_app
flutter analyze
flutter test --no-pub --coverage --reporter expanded
flutter test --no-pub --reporter expanded packages/video_thumbnail/test
node --test functions/test/policy.test.mjs
```

ชุด Firebase/Chrome/Android ใช้ `demo-linko` เท่านั้น:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:LINKO_FLUTTER_SDK = 'C:\Users\Admin\flutter'
$env:CHROME_EXECUTABLE = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$env:LINKO_INCLUDE_BROWSER = 'true'
New-Item -ItemType Directory -Force build/system_review | Out-Null

# เตรียม APK ทดสอบ แล้ว build กลับเป็นแอปปกติจาก lib/main.dart
flutter build apk --debug --no-pub --target=tool/android_post_smoke.dart
Copy-Item build/app/outputs/flutter-apk/app-debug.apk build/system_review/Linko-native-smoke.apk
flutter build apk --debug --no-pub
Copy-Item build/app/outputs/flutter-apk/app-debug.apk build/system_review/Linko-main-debug.apk
$env:LINKO_INCLUDE_ANDROID = 'true'

# ต้องมี Android Emulator ที่ adb มองเห็นเป็น emulator-5554
firebase emulators:exec --config firebase.emulator.test.json --project demo-linko --only auth,firestore,storage,functions "node tool/run_social_validation.mjs"
```

runner ติดตั้ง APK ทดสอบชั่วคราวและคืนเป็นแอปปกติใน `finally` โดยไม่ uninstall/clear data ถ้าทดสอบเฉพาะ Chrome/Rules ให้ลบ env `LINKO_INCLUDE_ANDROID` ก่อนรัน

สำหรับเครื่องที่เพิ่ง pull dependency ใหม่ ให้หยุดแอปแล้วรัน `flutter run` ใหม่ทั้งแอป การ Hot Reload อย่างเดียวเพิ่ม native plugin ไม่ได้
