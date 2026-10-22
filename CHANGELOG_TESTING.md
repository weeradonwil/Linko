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

## 2026-10-20 — Chat send permission diagnosis

- Updated the chat send error to show the Firebase plugin and error code.
- Added `tool/chat_rules_emulator_test.mjs` to reproduce the app's atomic message and conversation-summary write.
- Firestore/Auth Emulator: the current local rules allowed the chat send batch.
- The phone still reports `cloud_firestore/permission-denied`; verify that these exact rules are active in project `social-network-app-c22eb`, then inspect legacy conversation data if the deployed rules are confirmed.

## 2026-10-21 — Long-press emoji reactions

### Changes

- Added a shared reaction palette to Like buttons in the main feed and group posts; holding the button opens 👍, ❤️, 😂, 😮, 😢, and 😡 choices, while Dislike remains a separate action.
- Persisted each selected reaction as its own Firestore value and display counts and the current user's selected emoji.
- Updated Firestore Rules to allow the six Like-family reactions and Dislike for regular and group posts.
- Added tests for the supported reaction IDs and picker selection.

### Checks

| Check | Result |
|---|---|
| `git diff --check` | Passed |
| `dart format` | Could not confirm; Dart produced no output and was stopped after waiting. |
| `flutter test test/social_features_test.dart test/social_reaction_picker_test.dart` | Could not confirm; Flutter produced no output and was stopped after waiting. |

## 2026-10-22 — แก้ผลตรวจระบบตามลำดับ

วางแผนก่อนแก้ใน `AUDIT_FIX_PLAN.md` แล้วทำขั้น 1–5 จาก working tree ปัจจุบัน เก็บงาน emoji และงานแชทเดิมไว้ การทดสอบ Firebase ใช้เฉพาะ Auth/Firestore/Storage Emulator โปรเจกต์ `demo-linko` บน loopback

### 1. แชทและ Rules

- เปลี่ยนการตรวจ diff ให้ยอมรับ field ที่เขียนค่าเดิมได้: ข้อความซ้ำ ชนิดเดิม การตอบกลับ เปิดห้องซ้ำ และยกเลิกข้อความที่มี preview เดิม
- บังคับ approved follow ตอนสร้าง DM ใหม่ และบังคับข้อความกับ room summary เขียนพร้อมกัน
- ตรวจ schema ห้องใหม่; อ่าน legacy maps/counters อย่างปลอดภัย และรองรับ increment ค่าที่ไม่ใช่ตัวเลขกลับเป็น 1
- ข้อความใหม่เปิดห้องที่ทั้งสองฝ่ายซ่อนไว้ โดยห้ามแก้ hidden state ของอีกฝ่ายลอย ๆ
- ยกเลิกข้อความใช้ transaction เพื่อไม่เขียน preview ทับข้อความใหม่ที่ส่งพร้อมกัน

### 2. ความถูกต้องของข้อมูล สิทธิ์กลุ่ม และแจ้งเตือน

- Rules ตรวจชนิด profile/tags/content และ 7 reaction IDs; model ไม่ปล่อยข้อมูลผิดชนิดทำลายรายการทั้งหมด
- ผู้ดูแลที่ไม่ใช่สมาชิกอ่าน membership ที่ต้องใช้อนุมัติกลุ่มส่วนตัวได้
- เจ้าของกลุ่มลบ Storage media ของสมาชิกได้; ทดสอบ outsider แล้วถูกปฏิเสธ
- เพิ่ม `isDeleting` ปิดการเข้าร่วม/เพิ่มเนื้อหา/อัปโหลดใหม่ระหว่าง cleanup; UI แสดงสถานะและให้เจ้าของลองลบต่อ
- Comment Notification เปลี่ยนจาก batch ใหญ่เป็นคำขอแยก ขนานสูงสุด 8 งาน พร้อมจำนวนส่งสำเร็จตามจริง

### 3. โพสต์ โปรไฟล์ และงานหลายหน้า

- แก้โพสต์ที่มีเฉพาะสื่อได้โดยนับสื่อเดิม; ปฏิเสธการลบสื่อสุดท้ายจนโพสต์ว่าง
- การแก้สื่อและลบโพสต์อ่านสถานะใน transaction ป้องกันแข่งกับการแก้/ลบจากอีกอุปกรณ์
- ลบ comments/reactions เป็นหน้า ๆ ก่อนลบโพสต์แม่; การลบหยุดกลางทางสามารถลองต่อได้
- AuthGate เตรียม/ซ่อม profile ก่อนเปิด Home พร้อม loading/error/retry; profile repair ใช้ transaction และไม่ reset privacy เดิม
- Privacy ใช้ `privacyTarget` เก็บงานค้าง อ่าน ID เป็นหน้า 200 และทำ transaction ต่อโพสต์ ขนานสูงสุด 8 งาน ไม่มีเพดาน 499 โพสต์ และไม่เขียนทับ tags จาก snapshot เก่า
- การเปลี่ยน audience ไม่ใช่ atomic ทั้งบัญชี: โพสต์เดิมทยอยเปลี่ยนจนจบ; โพสต์ใหม่และ follow ใช้ target ขณะทำงาน ส่วนสวิตช์มีสถานะงานค้าง/ดำเนินการต่อ

### 4. Lifecycle การค้นหา และข้อมูลเก่า

- กล่องกลุ่มและรายงานโพสต์เป็น StatefulWidget ที่ดูแล controller เองจน route ถูก dispose
- Reaction palette ใช้ route: เลือกอารมณ์, Back และแตะนอกกล่องปิดได้; ปรับขนาดรองรับจอ 240/390 px
- Auth session เปลี่ยนแล้วปิดหน้าที่ push ค้างและล้าง media cache; ผลโหลดภาพเก่าไม่กลับมาเติม cache บัญชีใหม่
- Search จับ query/filter ก่อน await และใช้ generation ปฏิเสธผลเก่า รวมช่วง debounce
- Explore เปิดโปรไฟล์เพื่อติดตามก่อนเริ่ม DM; backend ยังตรวจ follow ซ้ำ
- Feed เรียง own posts ใหม่ไปเก่า ลด follow listeners ด้วยกลุ่มละ 5 UID ยกเลิก listener เก่าอย่างมี generation guard และเพิ่มปุ่มโหลดก่อนหน้า
- Profile/Groups/Chat/Comments ขยาย real-time query ตามปุ่มโหลดเพิ่ม; Search ใช้ cursor เข้าถึงโพสต์เก่า แม้หน้าปัจจุบันไม่พบคำค้น
- ตรวจ mounted หลังเลือก/อ่านไฟล์และหลังส่งความคิดเห็น พร้อม error/size checks ก่อนสร้าง preview

### 5. Platform และการตรวจรวม

- เพิ่ม iOS photo-library usage description และ macOS network client/file selection entitlements
- ปิด FileInputStream ของ local Android thumbnail plugin และปรับ channel tests ให้ตรงกับ implementation
- คง public enum API ของ plugin และใช้ named library ที่รองรับ Dart language version ของแพ็กเกจเดิม
- Windows แสดงข้อความวิดีโอยังไม่รองรับ แทนเรียก plugin ซ้ำจน error
- Android release ใช้ `key.properties` และ guard; เอาการเซ็นด้วย debug key ออกจาก release และเพิ่มตัวอย่าง/ignore secrets
- เก็บ analyzer lints ด้วย mechanical fixes โดยไม่อัปเกรด dependencies

### กลุ่มไฟล์ที่เปลี่ยน

| ส่วน | ไฟล์ |
|---|---|
| สิทธิ์ข้อมูลและสื่อ | `firestore.rules`, `storage.rules` |
| Model/Policy | `post.dart`, `post_comment.dart`, `social_group.dart`, `chat_models.dart`, `social_reaction.dart`, `post_policy.dart` |
| Service | `auth_service.dart`, `chat_service.dart`, `comment_service.dart`, `follow_service.dart`, `group_service.dart`, `post_service.dart`, `search_service.dart`, `reaction_service.dart`, `group_reaction_service.dart` |
| Utilities | `document_values.dart`, `latest_request.dart` |
| Shared widgets | `auth_session_boundary.dart`, `group_editor_dialog.dart`, `post_report_dialog.dart`, `social_reaction_picker.dart`, `post_media.dart`, `social_navigation.dart` |
| Screens | AuthGate, Home, Groups, ChatRoom, ChatList, Comments, CreatePost, Profile, EditProfile, SearchExplore, Notifications และ `main.dart` |
| Native/config | Android Gradle/key example, `.gitignore`, iOS plist, macOS entitlements, local `packages/video_thumbnail` Java/Dart/tests |
| Tests | `test/auth_session_boundary_test.dart`, `dialog_lifecycle_test.dart`, `document_policy_test.dart`, `latest_request_test.dart`, `platform_media_test.dart`, `social_features_test.dart`, `social_reaction_picker_test.dart`; auth form tests เดิมยังผ่าน |
| Emulator tools | `emulator_test_support.mjs`, `run_emulator_tests.mjs`, `chat_rules_emulator_test.mjs`, `group_rules_emulator_test.mjs`, `audit_rules_emulator_test.mjs`, `privacy_rules_emulator_test.mjs`, `feed_query_emulator_test.mjs` |
| เอกสาร | `AUDIT_FIX_PLAN.md`, `README.md`, `SCHEMA.md`, `CHANGELOG_TESTING.md` |

### ผลทดสอบจริง

| การตรวจ | ผล |
|---|---|
| `dart analyze` ทั้งโปรเจกต์ | ✅ `No issues found!` exit 0 รวม local package |
| `flutter test --no-pub test packages/video_thumbnail/test/video_thumbnail_test.dart` | ✅ 25/25: app 23 และ thumbnail native-channel contract 2 |
| `node tool/run_emulator_tests.mjs` | ✅ 5 suites; หยุดทันทีเมื่อ suite ใดล้มเหลว และรันซ้ำบน emulator เดิมได้ |
| Chat Rules | ✅ follow gate, malformed create, ส่งซ้ำ/ตอบกลับ/เปิดห้องซ้ำ, hidden room กลับมา, unsend, atomic summary, outsider denial, legacy string counter |
| Group Rules | ✅ public join/leave/duplicate, private request/cancel/approve/reject, ก่อนอนุมัติอ่านโพสต์ไม่ได้, non-owner อนุมัติไม่ได้, non-member admin อนุมัติได้ |
| Post/Storage/Notification | ✅ tags ผิดชนิดและโพสต์ว่างถูกปฏิเสธ, 7 reactions, แจ้งผู้ติดตาม 25 คนครบ/ไม่แจ้ง outsider, media-only edit, owner ลบ child และสื่อสมาชิกได้, deletion barrier |
| Privacy protocol | ✅ 501 โพสต์ ข้ามหน้า cursor, marker คงอยู่เมื่อหยุดกลางทาง, ปิด new-public-write/follow ระหว่าง pending private, เปิด/ปิด private และคง explicit private |
| Feed query/cursor | ✅ รวม 5 followed authors ใน query เดียว, outsider ถูกปฏิเสธ, cursor 61 โพสต์ที่ timestamp เท่ากันครบและไม่ซ้ำ |
| Android `:app:assembleDebug --offline --console=plain` | ✅ Debug build ผ่าน รวม Java thumbnail plugin |
| Android `:app:validateReleaseKey --offline` เมื่อไม่มี keystore | ✅ guard ปฏิเสธตามที่ออกแบบ พร้อมบอกวิธีตั้งค่า; **ไม่ใช่ผล release build ผ่าน** |
| Index JSON / Apple plist 3 ไฟล์ | ✅ parse ผ่าน |
| `git diff --check` | ✅ ไม่พบ whitespace error |

ระหว่างทดสอบพบและแก้เพิ่มเติม: picker root Positioned ผิด ancestor, outside tap ไม่ปิด palette, การ reset ตัวแปร platform ของ test, unnamed library ไม่รองรับใน plugin ภาษาเก่า และ test กลุ่มใช้ ID ตายตัว ผลข้างต้นเป็นผลหลังแก้และรันซ้ำ

### ข้อจำกัดของผลและงานถัดไป

- Emulator scripts ตรวจ Rules/Storage และ write/query protocol ผ่าน REST; ไม่ได้รัน Firebase Flutter integration บนอุปกรณ์จริง ส่วน Flutter tests ครอบคลุม model/policy/widgets/channel contract
- Android build เป็นผล compilation; ยังไม่ได้ติดตั้ง APK แล้วทดสอบ flow จริงในรอบนี้
- iOS/macOS เพิ่ม config และ parse ผ่าน แต่ยังไม่ได้ build/run บน Mac; Linux ยังไม่มี Firebase options; Windows ยังไม่รองรับ video playback
- ยังไม่มี signed release build เพราะต้องใช้ keystore ของเจ้าของแอป; ไม่มีการสร้าง key หรือบันทึกรหัสผ่านจริง
- ยังมี Gradle warnings เรื่อง new DSL/Kotlin plugin compatibility สำหรับอนาคต ต้องตรวจ migration ก่อนอัปเกรด major
- งาน fan-out notification และ cleanup ยังพึ่ง client ที่เปิดอยู่ ขั้นถัดไปควรเป็น backend queue/retry; real-time windows โตตามการโหลด และ text search ยังไม่มี search index
- App Check, Push และ Pages ยังไม่ได้พัฒนาในรอบนี้
- **ยังไม่ได้ deploy Rules, เขียนข้อมูล production หรือ push Git**; ต้อง deploy Rules ล่าสุดแล้วทดสอบ Firebase จริงอย่างน้อยสองบัญชี


## 2026-10-21 — แก้ regression ส่งแชทต่อเนื่องไม่ได้

- พบและทำซ้ำได้ว่า `affectedKeys().hasAll(...)` ใน Rules บังคับให้ข้อความ ชนิดข้อความ และผู้ส่งล่าสุดเปลี่ยนค่าทุกครั้ง ข้อความแรกผ่าน แต่ข้อความที่สองชนิดเดิมถูกปฏิเสธ
- เอาสาม field ที่สามารถมีค่าเดิมออกจากรายการบังคับเปลี่ยน โดยยังตรวจข้อมูลกับข้อความใน batch และสิทธิ์สมาชิกเหมือนเดิม
- แก้เปิดห้องที่มองเห็นอยู่แล้วซ้ำ และยกเลิกข้อความที่มีเนื้อหา `ยกเลิกข้อความนี้` อยู่แล้ว
- หน้าแชทบันทึกรหัส Firebase error จริงใน debug Console และแยกข้อความแจ้งปัญหาสิทธิ์ เครือข่าย และเซสชัน รวมการอ่าน stream โดยไม่ปล่อย error ที่ไม่ได้จัดการ
- เพิ่มชุดทดสอบแชท (ปัจจุบันเก็บเป็น `tool/chat_rules_diagnosis.mjs`), `tool/chat_service_smoke.dart` และ `tool/run_chat_service_smoke.mjs`

| รายการ | ผล |
|---|---|
| Rules หลังแก้ใน Auth/Firestore Emulator | ผ่าน 25/25 |
| `ChatService` จริงบน Chrome กับ Emulator | ผ่าน 6/6 |
| `flutter test --no-pub --reporter expanded` | ผ่าน 7/7 |
| Analyzer ไฟล์ที่แก้และหน้า browser ทดสอบ | 0 errors, 0 warnings; 7 info lints เดิม |
| Firebase จริงสองบัญชีชั่วคราว | ผ่าน 10/10 ขั้นตอน; ส่งต่อ/ส่งซ้ำ/ตอบกลับ/อ่าน/เปิดห้องซ้ำ/ยกเลิก/ส่งใหม่ |
| Cleanup ทดสอบจริง | ลบข้อมูล 9 เอกสารและบัญชี 2 บัญชีเรียบร้อย |
| Deploy | สำเร็จ เฉพาะ `firestore:rules` ไป `social-network-app-c22eb` |
| ตรวจ Rules หลัง deploy | เนื้อหาตรงกับไฟล์ที่ทดสอบทุกประการ |

Rules เดิมบน Firebase ตรงกับรุ่นที่มี bug จึงไม่ใช่ปัญหา deploy ไม่สำเร็จ Rules ใหม่เผยแพร่เวลา 11:40:31 น. (Asia/Bangkok) วันที่ 21 ต.ค. 2026 รายละเอียดและ hash อยู่ใน [รายงานแชท](tool/CHAT_DIAGNOSIS.md) ยังไม่ได้ทดสอบไฟล์แนบจริงหรือเผยแพร่ Storage Rules/indexes ในงานนี้


## 2026-10-22 — รวมงานในเครื่องกับ origin/main

รวม commit `1250133` (audit fixes) กับ `1c60028` (วินิจฉัย/แก้ regression แชท) โดยเก็บประวัติและงานทั้งสองฝั่ง ไม่เลือกทับทั้งไฟล์ฝ่ายเดียว

- แก้ conflict ใน `README.md`, `CHANGELOG_TESTING.md`, `firestore.rules`, `lib/screens/chat/chat_room.dart` และ `tool/chat_rules_emulator_test.mjs`
- ใช้ Rules จาก audit ซึ่งครอบคลุมข้อความซ้ำ/เปิดห้องซ้ำ/ยกเลิก โดยเก็บ follow gate, schema, deletion barrier และ privacy jobs
- หน้า ChatRoom เก็บ pagination และ media-picker error handling พร้อมใช้ debug error handler จาก GitHub; ข้อความสิทธิ์ไม่สรุปว่าเกิดจากยังไม่ deploy เสมอ
- เก็บชุด regression ปัจจุบันชื่อเดิม และแยกชุดวินิจฉัยจาก GitHub เป็น `tool/chat_rules_diagnosis.mjs`; runner รวมเป็น 6 suites
- ปรับ diagnostic fixtures และ `tool/chat_service_smoke.dart` ให้สร้าง profile ครบ schema และมี approved follow ก่อนสร้าง DM
- ชุดวินิจฉัยรันซ้ำได้ด้วย ID แยกแต่ละรอบ และคืน Rules ปัจจุบันใน `finally` แม้เกิดข้อผิดพลาด
- ตัวรัน ChatService รองรับ `LINKO_FLUTTER_SDK` เพื่อหลีกเลี่ยง PATH/shell ambiguity และใช้ Chrome แยกสำหรับทดสอบ
- คงบันทึกผล production ของวันที่ 21 ต.ค. เป็นประวัติเดิม ไม่อ้างว่า Rules หลัง audit ถูก deploy แล้ว

| การตรวจหลัง merge | ผล |
|---|---|
| `dart analyze` | No issues found |
| Flutter tests รวม thumbnail plugin | 25/25 ผ่าน |
| `node tool/run_emulator_tests.mjs` | 6 suites ผ่าน |
| `node tool/chat_rules_diagnosis.mjs --diagnose` | รุ่นมี bug 16/25 (แสดง regression), รุ่นก่อน 16/16, Rules ปัจจุบัน 25/25; exit 0 และคืน Rules ปัจจุบันแล้ว |
| ChatService จริง / Flutter release web / Chrome / Emulator | 6/6 ผ่าน หลังปรับ follow/schema fixtures |
| Android Debug offline build | ผ่าน |
| Conflict markers / whitespace | ผ่าน; ไม่มี marker ค้างในไฟล์ที่แก้ conflict |

รอบนี้ใช้ Firebase Emulator เฉพาะ `demo-linko` บน localhost ไม่มีการ deploy Rules หรือทดสอบเขียน production เพิ่มเติม ผลการ sync Git ตรวจจาก `git status` และ remote HEAD หลัง commit/push
