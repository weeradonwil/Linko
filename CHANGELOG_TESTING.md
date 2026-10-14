# Change Log and Test Report

บันทึกการเปลี่ยนแปลงและผลตรวจของ Profile, Like/Reaction, Follow, Groups และ Comment Notification

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
