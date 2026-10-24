# Linko — โปรเจกต์ Social Network

> Flutter / Dart / Firebase Authentication / Cloud Firestore / Firebase Storage

สถานะและผลทดสอบของรอบ **24 ตุลาคม 2026** อยู่ที่ [DELIVERY_REPORT.md](DELIVERY_REPORT.md) ส่วนผลวันที่ 21–22 ตุลาคมด้านล่างเป็นประวัติของรุ่นก่อนหน้า
>
> ประวัติการเปลี่ยนแปลงและผลตรวจอยู่ใน [CHANGELOG_TESTING.md](CHANGELOG_TESTING.md) และโครงสร้างข้อมูลอยู่ใน [SCHEMA.md](SCHEMA.md)
> แผนแก้ผลตรวจระบบและขอบเขตการทดสอบรอบ 22 ตุลาคม 2026 อยู่ใน [AUDIT_FIX_PLAN.md](AUDIT_FIX_PLAN.md)

## ปัญหาแชทที่แก้แล้ว — 21 ต.ค. 2026

- **สาเหตุ:** Firestore Rules บังคับให้ข้อความ ชนิดข้อความ และผู้ส่งล่าสุดเปลี่ยนค่าทุกครั้ง คนเดิมส่งต่อหรือส่งข้อความซ้ำจึงถูกปฏิเสธ แม้ deploy สำเร็จแล้ว
- **วิธีแก้:** ยอมให้สามค่านี้เหมือนเดิมได้ แต่ยังตรวจสิทธิ์สมาชิกและข้อมูลข้อความใน batch พร้อมแก้เปิดห้องซ้ำ ยกเลิกข้อความ และแสดง error ให้ตรงสาเหตุ
- **ผลยืนยัน:** Rules ใน Emulator ผ่าน 25/25, `ChatService` บน Chrome ผ่าน 6/6, Firebase จริงสองบัญชีผ่าน 10/10 ขั้นตอน และผู้ใช้ยืนยันว่าส่ง–รับข้อความได้แล้ว; ไฟล์แนบจริงยังต้องทดสอบแยก

รายละเอียดหลักฐานและวิธีรันทดสอบอยู่ใน [รายงานแชท](tool/CHAT_DIAGNOSIS.md)

## ปัญหารูปภาพในฟีดที่แก้แล้ว — 21 ต.ค. 2026

ไฟล์ภาพยังอยู่และไม่เสีย แต่ Storage bucket มี CORS ว่าง ทำให้ Chrome บล็อกการอ่านไบต์ที่ฟีดใช้แสดงภาพ ตั้งค่า [`storage.cors.json`](storage.cors.json) บน bucket จริงแล้วเวลา 13:33 น. (Asia/Bangkok) และทดสอบรูปเดิมใน Chrome ผ่าน: HTTP 200, ได้ครบ 3,302,621 ไบต์ และถอดรหัสภาพได้ รายละเอียดและขอบเขตผลทดสอบอยู่ใน [รายงานรูปฟีด](tool/FEED_MEDIA_DIAGNOSIS.md)

## โหมดและสีการแสดงผล

เปิดเมนู **การแสดงผล** จากไอคอนพาเลต เลือกสว่าง/มืดจากแถวเดียว แล้วเลือกสีหลักของโหมดที่ใช้อยู่ได้ 8 แบบ โดยจำสีโหมดสว่างกับโหมดมืดแยกกัน พร้อมปุ่มคืนค่าเริ่มต้น สีปุ่ม แท็บ ข้อความแชท และส่วนอื่นที่ใช้ธีมกลางเปลี่ยนตามทันที รายละเอียดชุดสี ไฟล์ที่เกี่ยวข้อง และวิธีทดสอบอยู่ใน [คู่มือการแสดงผล](tool/APPEARANCE.md)

## โค้ดสำคัญและคอมเมนต์

โค้ดที่เขียนเองให้มีคอมเมนต์ภาษาไทยต้นไฟล์อธิบายหน้าที่ และคอมเมนต์ที่คลาส/ฟังก์ชันสำคัญอธิบายงานที่ทำ เงื่อนไขสิทธิ์ หรือเหตุผลที่ต้องทำเช่นนั้น เมื่อแก้พฤติกรรมให้แก้คอมเมนต์ตามด้วย ไม่จำเป็นต้องอธิบายซ้ำทุกบรรทัด ส่วนไฟล์ที่เครื่องมือสร้างอัตโนมัติให้แก้ผ่านเครื่องมือเจ้าของไฟล์

| ไฟล์/ส่วน | หน้าที่ |
|---|---|
| [`lib/main.dart`](lib/main.dart) | เริ่มแอป ตั้งค่า Firebase และธีม |
| [`lib/core/services/`](lib/core/services/) | รวมงาน Auth, โพสต์, Follow, กลุ่ม และการอ่าน/เขียนข้อมูล |
| [`profile.dart`](lib/screens/profile/profile.dart) | แสดงโปรไฟล์และโพสต์ เปิดรายชื่อผู้ติดตาม/กำลังติดตาม และแตะรายชื่อเพื่อเปิดโปรไฟล์สมาชิก |
| [`chat_service.dart`](lib/core/services/chat_service.dart) | สร้าง/เปิดห้อง ส่งข้อความพร้อมอัปเดตสรุปห้องใน batch อ่าน ซ่อน และยกเลิกข้อความ |
| [`chat_room.dart`](lib/screens/chat/chat_room.dart) | แสดงข้อความสด รับการส่ง/แนบไฟล์ และจัดการ error ของหน้าห้องแชท |
| [`firebase_error_message.dart`](lib/core/utils/firebase_error_message.dart) | แปลงรหัส Firebase เป็นข้อความแจ้งปัญหาสิทธิ์ เครือข่าย และเซสชัน |
| [`firestore.rules`](firestore.rules) / [`storage.rules`](storage.rules) | ตรวจสิทธิ์และรูปแบบข้อมูล/ไฟล์ฝั่ง Firebase |
| [`lib/core/models/`](lib/core/models/) / [`SCHEMA.md`](SCHEMA.md) | แปลงข้อมูลที่หน้าจอใช้ และอธิบายโครงสร้างข้อมูลที่จัดเก็บ |
| [`lib/core/theme/app_theme.dart`](lib/core/theme/app_theme.dart) | กำหนดสีและรูปแบบวิดเจ็ตร่วมกันทั้งโหมดสว่างและมืด |
| [`appearance_controller.dart`](lib/core/theme/appearance_controller.dart) / [`appearance_settings.dart`](lib/core/widgets/appearance_settings.dart) | ควบคุมและบันทึกโหมด/สี พร้อมเมนูการแสดงผล |
| [`chat_rules_emulator_test.mjs`](tool/chat_rules_emulator_test.mjs) | ทดสอบการอนุญาต/ปฏิเสธของ Rules และกรณีแชทที่เคยพัง |
| [`chat_service_smoke.dart`](tool/chat_service_smoke.dart) / [`run_chat_service_smoke.mjs`](tool/run_chat_service_smoke.mjs) | เรียก `ChatService` จริงผ่าน Flutter/Chrome กับ Emulator และเก็บผลทดสอบ |

## สถานะงาน

| ฟีเจอร์ | สถานะปัจจุบัน | หมายเหตุ |
|---|---|---|
| สมัครสมาชิก / Login / Logout | ✅ มีโค้ด | ใช้ Firebase Authentication; ควรทดสอบกับบัญชีจริง |
| รีเซ็ตรหัสผ่าน | ✅ มีโค้ด | ส่งอีเมลผ่าน Firebase Auth; ยังต้องยืนยันการรับอีเมลจริง |
| โพสต์และ Feed | ✅ มีโค้ด | รองรับข้อความ รูป วิดีโอ แท็ก แก้ไข และลบ |
| Like / Emoji / Dislike / Comment | ✅ มีโค้ดและ regression tests | กดค้าง Like เลือก 6 อารมณ์; Dislike แยกปุ่ม; Comment แจ้งผู้ติดตามเจ้าของโพสต์ |
| Chat 1:1 | ✅ มีโค้ดและ regression tests | ข้อความ/สื่อ, ซ่อนห้องเฉพาะบัญชี, ยกเลิกข้อความ และตัวนับยังไม่อ่าน |
| Profile / Follow | ✅ มีโค้ด | รูปโปรไฟล์, Bio, ติดตาม/เลิกติดตาม, บัญชีส่วนตัว และเปิดแชทได้เมื่อติดตามแล้ว |
| Groups | ✅ ทดสอบ Emulator และ Chrome แล้ว | สร้าง/เข้าร่วม/แก้ไข/ออก/ลบกลุ่ม; โพสต์ข้อความ/สื่อ/แท็ก แก้ไข/ลบ Comment, Like/Emoji/Dislike, รายงาน และแจ้งเตือน |
| Report / Admin moderation | ✅ มีโค้ดทั้งฟีดหลักและกลุ่ม | ผู้ดูแลใช้คิวกลางเมื่อมี Firebase custom claim `admin: true`; แสดง error และลองอ่านสิทธิ์ใหม่ได้ |
| Pages | ❌ ยังไม่มี | ยังไม่ได้พัฒนา |
| Pain Point จากผู้ใช้จริง | ❌ ยังไม่มีหลักฐานในโปรเจกต์ | ต้องเก็บโจทย์/หลักฐานและเชื่อมกับฟีเจอร์ |
| Firebase App Check | ❌ ยังไม่ได้ตั้งค่า | ยังไม่มี SDK/configuration |

> `video_thumbnail` ใช้แพ็กเกจ local ที่ปรับ Gradle ไว้ใน `packages/video_thumbnail`; ต้องเก็บโฟลเดอร์นี้ไว้ใน Git เพราะ `pubspec.yaml` อ้างถึงโดยตรง

✅ มีโค้ดหรือผ่านการตรวจที่ระบุ · ⟳ ยังต้องทดสอบ/ตั้งค่าภายนอก · ❌ ยังไม่มี

## งานที่ยังต้องทำ

1. **ทดสอบกับ Firebase จริงสองบัญชี** — ตรวจ private profile/follow request, การอ่านโพสต์และสื่อ, Comment Notification, Chat, กลุ่ม และสิทธิ์ผู้ดูแล
2. **ตั้งค่า admin claim** ให้บัญชีผู้ดูแลก่อนทดสอบหน้าจัดการรายงาน
3. **ทดสอบบนโทรศัพท์จริง** รวมการรับอีเมลรีเซ็ตรหัสผ่าน อัปโหลดสื่อ และ UX/การเข้าถึง
4. เพิ่ม Firebase App Check, Pages และหลักฐาน Pain Point หากยังอยู่ในข้อกำหนดของรายวิชา
5. เตรียม build สำหรับส่ง, README/demo และทดสอบกรณีใช้งานให้ครบตามเกณฑ์อาจารย์

> Deploy Firestore Rules, Storage Rules และ indexes รุ่นที่ตรวจรับไป `social-network-app-c22eb` แล้วเมื่อ **24 ต.ค. 2026 เวลา 16:16:59 น. (Asia/Bangkok)** อ่านกลับแล้วยืนยันว่า Rules ตรงกับโค้ดที่ทดสอบ และ indexes ทั้ง 11 รายการเป็น `READY` ดู [หลักฐานและขอบเขต](DELIVERY_REPORT.md#deploy-firebase-production--24-ตุลาคม-2026)

## ผลตรวจในเครื่องล่าสุด

ผลรอบ **2026-10-22**:

- Flutter tests: ผ่าน **25/25** รวม app tests 23 รายการและ thumbnail plugin 2 รายการ
- `dart analyze`: **No issues found** ทั้งโปรเจกต์ รวม local package
- Firebase Auth/Firestore/Storage Emulator หลัง merge: ผ่าน **6 suites** ใช้เฉพาะ `demo-linko` บนเครื่อง
- ChatService จริงบน Chrome กับ Emulator หลัง merge: **6/6 ผ่าน** (ส่ง/ตอบกลับ/อ่าน/ซ่อนห้อง/ยกเลิก/ปฏิเสธผู้ไม่มีสิทธิ์)
- ครอบคลุมส่งแชทซ้ำ/ตอบกลับ/ยกเลิก, follow gate, กลุ่มส่วนตัวและ admin, ลบสื่อสมาชิก, แจ้งผู้ติดตาม 25 คน, privacy 501 โพสต์ และ cursor 61 โพสต์
- Android Debug: `:app:assembleDebug --offline` ผ่าน
- JSON indexes และ Apple plist/entitlements: parse ผ่าน; ผล analyzer และคำสั่งทั้งหมดอยู่ใน [CHANGELOG_TESTING.md](CHANGELOG_TESTING.md)
- ยังต้องทดสอบ Firebase จริงสองบัญชี โทรศัพท์จริง และ iOS/macOS บน Mac; ผล Emulator และ build ไม่แทนผลทดสอบเหล่านี้

### รันทดสอบซ้ำ

```powershell
flutter test --no-pub test packages/video_thumbnail/test/video_thumbnail_test.dart
dart analyze
firebase --config firebase.emulator.test.json emulators:exec --only "auth,firestore,storage" --project demo-linko "node tool/run_emulator_tests.mjs"
```

คำสั่งที่ใช้ deploy Rules/indexes รอบล่าสุดจากโฟลเดอร์นี้:

```powershell
firebase deploy --only "firestore:rules,firestore:indexes,storage" --project social-network-app-c22eb --non-interactive
```

Android release ต้องใช้ keystore ของเจ้าของแอปและ `android/key.properties` ตาม [แผนและข้อจำกัด](AUDIT_FIX_PLAN.md); ระบบจะปฏิเสธ release ที่ยังไม่ได้ตั้งค่าลายเซ็น

### ประวัติการตรวจแชทจาก GitHub

รุ่นวันที่ 21 ต.ค. 2026 (`1c60028`) มีบันทึก Rules 25/25, ChatService/Chrome 6/6 และ Firebase จริง 10/10 ขั้นตอน พร้อม deploy เฉพาะ Firestore Rules ในวันนั้น ดู [รายงานเดิม](tool/CHAT_DIAGNOSIS.md)

ผลดังกล่าวเป็นของรุ่นเดิม Rules หลัง audit เผยแพร่ใหม่แล้ววันที่ 24 ต.ค. ตาม [รายงานปัจจุบัน](DELIVERY_REPORT.md) และยังต้องทดสอบผ่านแอปกับบัญชีจริงหลายบัญชี สคริปต์วินิจฉัยเดิมเก็บไว้ที่ `tool/chat_rules_diagnosis.mjs` แยกจาก regression suite ปัจจุบัน
