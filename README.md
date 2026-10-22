# Linko — โปรเจกต์ Social Network

> Flutter / Dart / Firebase Authentication / Cloud Firestore / Firebase Storage
>
> ประวัติการเปลี่ยนแปลงและผลตรวจอยู่ใน [CHANGELOG_TESTING.md](CHANGELOG_TESTING.md) และโครงสร้างข้อมูลอยู่ใน [SCHEMA.md](SCHEMA.md)
> แผนแก้ผลตรวจระบบและขอบเขตการทดสอบรอบ 22 ตุลาคม 2026 อยู่ใน [AUDIT_FIX_PLAN.md](AUDIT_FIX_PLAN.md)

## สถานะงาน

| ฟีเจอร์ | สถานะปัจจุบัน | หมายเหตุ |
|---|---|---|
| สมัครสมาชิก / Login / Logout | ✅ มีโค้ด | ใช้ Firebase Authentication; ควรทดสอบกับบัญชีจริง |
| รีเซ็ตรหัสผ่าน | ✅ มีโค้ด | ส่งอีเมลผ่าน Firebase Auth; ยังต้องยืนยันการรับอีเมลจริง |
| โพสต์และ Feed | ✅ มีโค้ด | รองรับข้อความ รูป วิดีโอ แท็ก แก้ไข และลบ |
| Like / Emoji / Dislike / Comment | ✅ มีโค้ดและ regression tests | กดค้าง Like เลือก 6 อารมณ์; Dislike แยกปุ่ม; Comment แจ้งผู้ติดตามเจ้าของโพสต์ |
| Chat 1:1 | ✅ มีโค้ด | ข้อความ/สื่อ, ซ่อนห้องเฉพาะบัญชี, ยกเลิกข้อความ และตัวนับยังไม่อ่าน |
| Profile / Follow | ✅ มีโค้ด | รูปโปรไฟล์, Bio, ติดตาม/เลิกติดตาม, บัญชีส่วนตัว และเปิดแชทได้เมื่อติดตามแล้ว |
| Groups | ✅ มีโค้ดและ Rules tests | กลุ่มสาธารณะ/ส่วนตัว คำขอเข้าร่วม รูปกลุ่ม โพสต์สื่อ และ Like/Emoji/Dislike |
| Report / Admin moderation | ✅ มีโค้ด | ผู้ดูแลจัดการรายงานได้เมื่อบัญชีมี Firebase custom claim `admin: true` |
| Pages | ❌ ยังไม่มี | ยังไม่ได้พัฒนา |
| Pain Point จากผู้ใช้จริง | ❌ ยังไม่มีหลักฐานในโปรเจกต์ | ต้องเก็บโจทย์/หลักฐานและเชื่อมกับฟีเจอร์ |
| Firebase App Check | ❌ ยังไม่ได้ตั้งค่า | ยังไม่มี SDK/configuration |

> `video_thumbnail` ใช้แพ็กเกจ local ที่ปรับ Gradle ไว้ใน `packages/video_thumbnail`; ต้องเก็บโฟลเดอร์นี้ไว้ใน Git เพราะ `pubspec.yaml` อ้างถึงโดยตรง

✅ มีโค้ดหรือผ่านการตรวจที่ระบุ · ⟳ ยังต้องทดสอบ/ตั้งค่าภายนอก · ❌ ยังไม่มี

## งานที่ยังต้องทำ

1. **Deploy Rules รุ่นปัจจุบันและตรวจ indexes** — รอบนี้แก้ `firestore.rules` และ `storage.rules`; query ใช้ indexes ที่มีใน `firestore.indexes.json` อยู่แล้ว ต้องตรวจว่าโปรเจกต์จริงมีดัชนีตรงกัน
2. **ทดสอบกับ Firebase จริงสองบัญชี** — ตรวจ private profile/follow request, การอ่านโพสต์และสื่อ, Comment Notification, Chat, กลุ่ม และสิทธิ์ผู้ดูแล
3. **ตั้งค่า admin claim** ให้บัญชีผู้ดูแลก่อนทดสอบหน้าจัดการรายงาน
4. **ทดสอบบนโทรศัพท์จริง** รวมการรับอีเมลรีเซ็ตรหัสผ่าน อัปโหลดสื่อ และ UX/การเข้าถึง
5. เพิ่ม Firebase App Check, Pages และหลักฐาน Pain Point หากยังอยู่ในข้อกำหนดของรายวิชา
6. เตรียม build สำหรับส่ง, README/demo และทดสอบกรณีใช้งานให้ครบตามเกณฑ์อาจารย์

> ยังไม่ได้ deploy กฎ/ดัชนีรอบล่าสุดไป Firebase production และยังไม่ได้ push การเปลี่ยนแปลงรอบนี้ขึ้น GitHub

## ผลตรวจในเครื่องล่าสุด

ผลรอบ **2026-10-22**:

- Flutter tests: ผ่าน **25/25** รวม app tests 23 รายการและ thumbnail plugin 2 รายการ
- `dart analyze`: **No issues found** ทั้งโปรเจกต์ รวม local package
- Firebase Auth/Firestore/Storage Emulator: ผ่าน **5 suites** ใช้เฉพาะ `demo-linko` บนเครื่อง
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

เมื่อพร้อมนำ Rules ไปใช้จริง ให้ deploy จากโฟลเดอร์นี้แล้วทดสอบหลายบัญชี:

```powershell
firebase deploy --only "firestore:rules,firestore:indexes,storage" --project social-network-app-c22eb
```

Android release ต้องใช้ keystore ของเจ้าของแอปและ `android/key.properties` ตาม [แผนและข้อจำกัด](AUDIT_FIX_PLAN.md); ระบบจะปฏิเสธ release ที่ยังไม่ได้ตั้งค่าลายเซ็น
