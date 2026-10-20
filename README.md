# Linko — โปรเจกต์ Social Network

> Flutter / Dart / Firebase Authentication / Cloud Firestore / Firebase Storage
>
> ประวัติการเปลี่ยนแปลงและผลตรวจอยู่ใน [CHANGELOG_TESTING.md](CHANGELOG_TESTING.md) และโครงสร้างข้อมูลอยู่ใน [SCHEMA.md](SCHEMA.md)

## สถานะงาน

| ฟีเจอร์ | สถานะปัจจุบัน | หมายเหตุ |
|---|---|---|
| สมัครสมาชิก / Login / Logout | ✅ มีโค้ด | ใช้ Firebase Authentication; ควรทดสอบกับบัญชีจริง |
| รีเซ็ตรหัสผ่าน | ✅ มีโค้ด | ส่งอีเมลผ่าน Firebase Auth; ยังต้องยืนยันการรับอีเมลจริง |
| โพสต์และ Feed | ✅ มีโค้ด | รองรับข้อความ รูป วิดีโอ แท็ก แก้ไข และลบ |
| Like / Dislike / Comment | ✅ มีโค้ด | Like แจ้งเจ้าของโพสต์; Comment แจ้งผู้ติดตามเจ้าของโพสต์ |
| Chat 1:1 | ✅ มีโค้ด | ข้อความ/สื่อ, ซ่อนห้องเฉพาะบัญชี, ยกเลิกข้อความ และตัวนับยังไม่อ่าน |
| Profile / Follow | ✅ มีโค้ด | รูปโปรไฟล์, Bio, ติดตาม/เลิกติดตาม, บัญชีส่วนตัว และเปิดแชทได้เมื่อติดตามแล้ว |
| Groups | ✅ มีโค้ด | รูปประจำกลุ่มและโพสต์ข้อความ/รูป/วิดีโอ พร้อม Like/Dislike |
| Report / Admin moderation | ✅ มีโค้ด | ผู้ดูแลจัดการรายงานได้เมื่อบัญชีมี Firebase custom claim `admin: true` |
| Pages | ❌ ยังไม่มี | ยังไม่ได้พัฒนา |
| Pain Point จากผู้ใช้จริง | ❌ ยังไม่มีหลักฐานในโปรเจกต์ | ต้องเก็บโจทย์/หลักฐานและเชื่อมกับฟีเจอร์ |
| Firebase App Check | ❌ ยังไม่ได้ตั้งค่า | ยังไม่มี SDK/configuration |

> `video_thumbnail` ใช้แพ็กเกจ local ที่ปรับ Gradle ไว้ใน `packages/video_thumbnail`; ต้องเก็บโฟลเดอร์นี้ไว้ใน Git เพราะ `pubspec.yaml` อ้างถึงโดยตรง

✅ มีโค้ดหรือผ่านการตรวจที่ระบุ · ⟳ ยังต้องทดสอบ/ตั้งค่าภายนอก · ❌ ยังไม่มี

## งานที่ยังต้องทำ

1. **Deploy กฎและ index รุ่นปัจจุบัน** — มีการแก้ `firestore.rules`, `storage.rules` และ `firestore.indexes.json` ในรอบนี้ กฎ/ดัชนีที่เคย deploy ก่อนหน้านี้จึงไม่ครอบคลุมการแก้ล่าสุด
2. **ทดสอบกับ Firebase จริงสองบัญชี** — ตรวจ private profile/follow request, การอ่านโพสต์และสื่อ, Comment Notification, Chat, กลุ่ม และสิทธิ์ผู้ดูแล
3. **ตั้งค่า admin claim** ให้บัญชีผู้ดูแลก่อนทดสอบหน้าจัดการรายงาน
4. **ทดสอบบนโทรศัพท์จริง** รวมการรับอีเมลรีเซ็ตรหัสผ่าน อัปโหลดสื่อ และ UX/การเข้าถึง
5. เพิ่ม Firebase App Check, Pages และหลักฐาน Pain Point หากยังอยู่ในข้อกำหนดของรายวิชา
6. เตรียม build สำหรับส่ง, README/demo และทดสอบกรณีใช้งานให้ครบตามเกณฑ์อาจารย์

> ยังไม่ได้ deploy กฎ/ดัชนีรอบล่าสุดไป Firebase production และยังไม่ได้ push การเปลี่ยนแปลงรอบนี้ขึ้น GitHub

## ผลตรวจในเครื่องล่าสุด

- `dart analyze lib test`: 0 errors, 0 warnings; พบ info-level lints 51 รายการ
- `dart format`: ผ่านสำหรับไฟล์ Dart ที่แก้ในรอบนี้
- Firestore และ Storage Emulator: เริ่มทำงานและโหลด Rules ได้สำเร็จ
- `flutter test` รอบนี้ยังรันไม่ได้ เพราะ Flutter SDK ต้องเขียน `bin/cache/lockfile` ในตำแหน่งนอก workspace ที่ไม่มีสิทธิ์เข้าถึง
- `firestore.indexes.json`: รูปแบบ JSON ถูกต้อง
- ยังไม่มีผลทดสอบ integration กับ Firebase จริงหรือ flow หลายบัญชี; Rules ใน Emulator ยังต้อง deploy ก่อนใช้งาน Firebase จริง ดูรายละเอียดใน [CHANGELOG_TESTING.md](CHANGELOG_TESTING.md)
