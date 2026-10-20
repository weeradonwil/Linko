# Change Log and Test Report

บันทึกการเปลี่ยนแปลงและผลตรวจของ Profile, Like/Reaction, Follow, Groups และ Comment Notification

> บันทึกก่อนหัวข้อ 2026-10-20 เป็นสถานะ ณ เวลาที่ทำรายการนั้น; หัวข้อ 2026-10-20 คือสถานะล่าสุดของ working tree

## 2026-10-14 — เพิ่มฟีเจอร์สังคม

### โครงสร้างที่ตรวจพบก่อนแก้

- `lib/screens/profile/profile.dart` ว่าง และแท็บ Profile/Groups ยังเป็นข้อความ placeholder
- ปุ่ม reaction ใน Feed ยังไม่บันทึกข้อมูล
- Comment Notification เดิมส่งให้เจ้าของโพสต์ทุกครั้ง
- Firestore schema มีเพียงข้อมูล Chat/Comment เดิม ยังไม่มี Rules สำหรับ Follow, Reaction และ Groups

### สิ่งที่เปลี่ยน

- เพิ่มหน้า Profile: ดูชื่อ โพสต์ จำนวนผู้ติดตาม/กำลังติดตาม; แก้ชื่อที่แสดง
- เพิ่ม Follow/Unfollow และรายชื่อผู้ติดตาม/กำลังติดตาม เก็บความสัมพันธ์ทั้งสองด้านด้วย batch
- เพิ่ม Reaction ต่อโพสต์แบบหนึ่ง reaction ต่อบัญชี: Like, Love, Haha, Wow, Sad และ Angry
- เพิ่ม Groups: สร้าง/แก้ไข/ลบกลุ่มสาธารณะ, เข้าร่วม/ออกจากกลุ่ม และโพสต์ข้อความใน Group Feed
- เปลี่ยน Comment Notification ให้ส่งเฉพาะผู้ติดตามเจ้าของโพสต์ และเฉพาะโพสต์สาธารณะ; การส่ง notification ล้มเหลวจะไม่ทำให้ผู้ใช้ส่ง Comment ซ้ำ
- เพิ่ม Firestore Rules และ index โปรไฟล์ที่ใช้; เพิ่มอธิบาย schema ใน `SCHEMA.md`

### ผลการทดสอบในเครื่อง

| รายการ | ผล |
|---|---|
| `dart format` ไฟล์ที่แก้ | ผ่าน; จัดรูปแบบไฟล์ Dart ที่เกี่ยวข้อง 13 ไฟล์ |
| `dart analyze lib test` | ผ่าน ไม่มี error; มี lint ระดับ info 50 รายการ โดยส่วนใหญ่อยู่ในไฟล์เดิม |
| `flutter test --no-pub -r expanded` | ผ่าน 6/6 กรณี: Auth 4 กรณี และ reaction 2 กรณี |
| ตรวจ `firestore.indexes.json` | ผ่าน; JSON ถูกต้อง |
| `git diff --check` | ผ่าน; ไม่พบ whitespace error |
| Firestore Emulator / Rules | ยังไม่ได้ทดสอบ: CLI ต้องดาวน์โหลด emulator แต่ cache path ของบัญชีระบบเขียนไม่ได้ และเครือข่ายไม่สามารถดึงข้อมูล Firebase ได้ |
| ทดสอบ Firebase จริงด้วยหลายบัญชี | ยังไม่ได้ทดสอบจากเครื่องมือนี้ |

### ยืนยัน Deploy — 2026-10-14

- ผู้ใช้ส่งภาพผล `firebase deploy --only firestore:rules,firestore:indexes --project social-network-app-c22eb`
- Firebase รายงานว่า Rules compile สำเร็จ, Indexes deploy สำเร็จ และ Rules ถูก release ไปยัง Cloud Firestore
- ยังต้องทดสอบพฤติกรรมจริงด้วยหลายบัญชีตามรายการด้านล่าง; ผล Deploy ยืนยันการเผยแพร่ไฟล์ แต่ไม่แทนการทดสอบ flow ในแอป

### ขั้นตอนทดสอบ Firebase ที่ยังต้องทำ

1. ใช้บัญชีเจ้าของโพสต์, ผู้แสดงความคิดเห็น, ผู้ติดตาม และผู้ที่ไม่ได้ติดตาม: ตรวจว่าเฉพาะผู้ติดตามได้รับ Comment Notification
2. ตรวจ Like/Emoji: เลือก reaction, เลือกซ้ำเพื่อยกเลิก, เปลี่ยนเป็น reaction อื่น และดูจำนวนจากอีกบัญชี
3. ตรวจ Follow: ติดตาม/เลิกติดตามแล้วดูจำนวนและรายชื่อจากทั้งสองบัญชี
4. ตรวจ Groups: สร้างกลุ่ม, เข้าร่วมด้วยบัญชีที่สอง, โพสต์ข้อความ, ออกจากกลุ่ม และลบกลุ่มด้วยเจ้าของ
5. ตรวจว่า private post ไม่ส่ง Notification ให้ผู้ติดตามที่ไม่มีสิทธิ์อ่านโพสต์

## ขอบเขตที่ยังไม่ทำ

- ยังไม่มี Dislike, รูปโปรไฟล์, Bio, Follow Request/การอนุมัติบัญชีส่วนตัว หรือ Pages
- Group Feed ปัจจุบันรองรับข้อความเท่านั้น
- Firestore Rules และ Indexes รุ่นนี้ Deploy แล้ว แต่ยังไม่มีผลทดสอบ permission/runtime กับ Firebase จริง

## 2026-10-20 — ปิดงานฟีเจอร์ที่ค้างจากการตรวจระบบ

### สิ่งที่เพิ่ม/ปรับ

- เชื่อม Forgot Password กับ Firebase Auth และเพิ่ม Bio ในข้อมูลสมาชิก/หน้า Profile
- เพิ่มโปรไฟล์ส่วนตัว, คำขอติดตาม, อนุมัติ/ปฏิเสธคำขอ และการกรองโพสต์ตามสิทธิ์ผู้ติดตาม
- เพิ่มสื่อรูป/วิดีโอและ Like/Dislike ใน Group Feed พร้อมจัดการไฟล์เมื่อโพสต์หรือกลุ่มถูกลบ
- เพิ่มหน้าผู้ดูแลจัดการรายงาน: ปิดรายงาน, ยุติรายงาน หรือเอาโพสต์ออก; ต้องกำหนด Firebase custom claim `admin: true`
- ปรับ Firestore/Storage Rules และ Firestore index ให้ครอบคลุมฟีเจอร์ด้านบน
- ปรับสถานะติดตามให้ยังกดดำเนินการได้เมื่อ stream สถานะมีปัญหา พร้อมข้อความชี้ไปที่ Firestore Rules; ไม่ให้ notification failure ยกเลิกความสัมพันธ์ติดตาม
- เพิ่มปุ่มเปิดห้องแชท 1:1 บนโปรไฟล์ที่ติดตามแล้ว
- เพิ่มรูปกลุ่มทั้งตอนสร้างและแก้ไข พร้อมแสดงในรายการ/หน้ากลุ่ม และลบไฟล์เก่าเมื่อเปลี่ยนรูปสำเร็จ
- ปรับการ์ดโปรไฟล์และลดปุ่มกล้องเปลี่ยนรูปให้เล็กลง
- เก็บ `video_thumbnail` เวอร์ชันที่ปรับ Gradle ไว้ใน `packages/video_thumbnail`; เป็น local path dependency ที่ต้องรวมเมื่อ clone/build
- อัปเดต README และ Schema ให้แยกฟีเจอร์ที่มีโค้ดออกจากสิ่งที่ยังรอ deploy/ทดสอบ

### ผลตรวจในเครื่อง

| รายการ | ผล |
|---|---|
| `flutter test` | ผ่าน 7/7 กรณี |
| `flutter analyze --no-pub` | 0 errors, 0 warnings; 59 info-level lints |
| Firestore และ Storage Emulator | โหลด Rules สำเร็จ; เป็นการตรวจ rules ไม่ใช่การทดสอบ flow/สิทธิ์ทุกกรณี |
| `firestore.indexes.json` | JSON ถูกต้อง |

### ยังต้องทำ

- Deploy `firestore.rules`, `firestore.indexes.json` และ `storage.rules` รุ่นนี้ไปยัง Firebase project เป้าหมาย
- ทดสอบสิทธิ์และ flow จริงด้วยผู้ใช้หลายบัญชี/โทรศัพท์ โดยเฉพาะ private profile, media, notification และ admin moderation
- ตั้งค่า App Check, พัฒนา Pages และบันทึกหลักฐาน Pain Point หากเป็นข้อกำหนด
- ยังไม่มีการ deploy production หรือ push GitHub ในการเปลี่ยนแปลงรอบนี้

## 2026-10-20 — แชทจากโปรไฟล์และรูปประจำกลุ่ม

### เปลี่ยนแปลง

- เพิ่มปุ่มข้อความบนโปรไฟล์เมื่อผู้ชมติดตามบัญชีนั้นแล้ว; เปิดห้องเดิมหรือสร้างห้อง 1:1 ก่อนนำเข้าหน้าแชท
- ปรับให้ปุ่มติดตามลองทำรายการได้แม้ stream สถานะติดตามมี error และแสดงคำแนะนำเมื่อ Firestore Rules ยังไม่ deploy
- แยกการบันทึกความสัมพันธ์ติดตามออกจาก notification เพื่อให้ notification failure ไม่ย้อนยกเลิกการติดตาม
- เพิ่มเลือกรูปกลุ่มตอนสร้าง/แก้ไข, แสดง avatar ในรายการและหน้ากลุ่ม และจัดเก็บไฟล์ใต้ `group_images/`
- ปรับการ์ดโปรไฟล์/สถิติ และย่อปุ่มเปลี่ยนรูปโปรไฟล์
- เพิ่ม Firestore/Storage Rules สำหรับ path รูปกลุ่ม; ต้อง deploy Rules ล่าสุดก่อนใช้งานกับ Firebase จริง

### ผลตรวจ

| รายการ | ผล |
|---|---|
| `dart format` | ผ่านสำหรับไฟล์ Dart ที่แก้ |
| `dart analyze lib test` | 0 errors, 0 warnings; 51 info-level lints |
| `git diff --check` | ผ่าน |
| `firestore.indexes.json` | JSON ถูกต้อง |
| `flutter test` | รอบนี้รันไม่ได้: Flutter SDK ต้องเขียน `bin/cache/lockfile` ในตำแหน่งนอก workspace ที่ sandbox ปฏิเสธ |
| Firestore และ Storage Emulator | เริ่มทำงานและโหลด Rules สำเร็จ; มีเพียง warning ของ Java/การเชื่อมต่อ CLI ที่ไม่กระทบการเริ่ม emulator |

ยังต้องทดสอบ permission/runtime ด้วยสองบัญชี และ deploy `firestore.rules`, `firestore.indexes.json`, `storage.rules` ก่อนทดสอบบนโทรศัพท์จริง

## 2026-10-20 — ปรับ UX/UI และสิทธิ์การเข้าร่วมกลุ่ม

### เปลี่ยนแปลง

- ปรับการ์ดรายการกลุ่มให้แสดงรูป ชื่อ เจ้าของจริงจาก `users`, ประเภทกลุ่ม และจำนวนสมาชิก พร้อมปุ่มตามสถานะสมาชิก/คำขอ
- ปรับรายละเอียดกลุ่มให้แสดงเจ้าของ ประเภท จำนวนสมาชิก คำอธิบาย และเงื่อนไขเข้าร่วม; เจ้าของเปิดหน้าจัดการและดูคำขอได้
- กลุ่มสาธารณะเข้าร่วมทันที; กลุ่มส่วนตัวส่งคำขอ ยกเลิกคำขอ และรอเจ้าของหรือผู้ดูแลอนุมัติ/ปฏิเสธ
- เพิ่ม `memberCount` และ collection `join_requests`; อัปเดต Firestore Rules ให้กันคำขอซ้ำ จำกัดสิทธิ์อนุมัติ และปิดโพสต์/สมาชิกกลุ่มส่วนตัวสำหรับผู้ที่ยังไม่ได้รับอนุมัติ
- ให้ผู้ใช้ที่ลงชื่อเข้าใช้เห็นรูปกลุ่มในรายการได้; สื่อและโพสต์ส่วนตัวยังคงต้องเป็นสมาชิกที่อนุมัติแล้ว
- เพิ่มชุดทดสอบ Firestore/Auth Emulator ที่ `tool/group_rules_emulator_test.mjs` และ config แยกที่ `firebase.emulator.test.json`

### ผลตรวจ

| รายการ | ผล |
|---|---|
| Firestore/Auth Emulator: เข้ากลุ่มสาธารณะ ออกจากกลุ่ม อัปเดตจำนวนสมาชิก และป้องกันสมาชิกซ้ำ | ผ่าน |
| Firestore/Auth Emulator: ส่ง/ยกเลิก/ส่งใหม่ ป้องกันคำขอซ้ำ และเจ้าของอนุมัติหรือปฏิเสธ | ผ่าน |
| Firestore/Auth Emulator: อ่านโพสต์/รายชื่อสมาชิกส่วนตัว | ผ่าน; ก่อนอนุมัติถูกปฏิเสธ และสมาชิกที่อนุมัติแล้วอ่านโพสต์ได้ |
| Firestore/Auth Emulator: ผู้ใช้ที่ไม่ใช่เจ้าของพยายามอนุมัติ | ผ่าน; ถูกปฏิเสธและจำนวนสมาชิกไม่เปลี่ยน |
| Storage Emulator | เริ่มทำงานกับ Rules ล่าสุดได้; รอบนี้ยังไม่ได้ทดสอบ upload/download ไฟล์กลุ่ม |
| `dart analyze` ไฟล์ Group UI/Service/Model | แสดง `No issues found`; process คืน exit code 1 เพราะ Dart พยายามแก้ telemetry file นอก workspace ที่ไม่มีสิทธิ์เขียน |
| `flutter test` | ยังไม่มีผล: คำสั่งไม่แสดง output เกิน 90 วินาที จึงหยุดไว้; Emulator tests ข้างต้นทำงานครบ |
| `git diff --check` | ผ่าน; ไม่พบ whitespace error |

ยังไม่ได้ deploy Rules ขึ้น Firebase จริง; ต้อง deploy `firestore.rules` และ `storage.rules` ก่อนให้ผู้ใช้จริงใช้ flow คำขอส่วนตัว
