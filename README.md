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
| Chat 1:1 | ✅ ทดสอบข้อความแล้ว | ส่ง/รับข้อความ ซ่อน/เปิดห้อง ยกเลิกข้อความ และตัวนับอ่านผ่าน Emulator และ Firebase จริง; ไฟล์แนบยังต้องทดสอบเพิ่ม |
| Profile / Follow | ✅ มีโค้ด | รูปโปรไฟล์, Bio, ติดตาม/เลิกติดตาม, บัญชีส่วนตัว และเปิดแชทได้เมื่อติดตามแล้ว |
| Groups | ✅ มีโค้ด | รูปประจำกลุ่มและโพสต์ข้อความ/รูป/วิดีโอ พร้อม Like/Dislike |
| Report / Admin moderation | ✅ มีโค้ด | ผู้ดูแลจัดการรายงานได้เมื่อบัญชีมี Firebase custom claim `admin: true` |
| Pages | ❌ ยังไม่มี | ยังไม่ได้พัฒนา |
| Pain Point จากผู้ใช้จริง | ❌ ยังไม่มีหลักฐานในโปรเจกต์ | ต้องเก็บโจทย์/หลักฐานและเชื่อมกับฟีเจอร์ |
| Firebase App Check | ❌ ยังไม่ได้ตั้งค่า | ยังไม่มี SDK/configuration |

> `video_thumbnail` ใช้แพ็กเกจ local ที่ปรับ Gradle ไว้ใน `packages/video_thumbnail`; ต้องเก็บโฟลเดอร์นี้ไว้ใน Git เพราะ `pubspec.yaml` อ้างถึงโดยตรง

✅ มีโค้ดหรือผ่านการตรวจที่ระบุ · ⟳ ยังต้องทดสอบ/ตั้งค่าภายนอก · ❌ ยังไม่มี

## งานที่ยังต้องทำ

1. **ยืนยันสถานะ Storage Rules และ indexes** — งานแก้แชทวันที่ 21 ต.ค. 2026 เผยแพร่เฉพาะ `firestore.rules` ที่แก้แล้ว; Storage Rules และ indexes ต้องตรวจแยก
2. **ทดสอบฟีเจอร์อื่นกับ Firebase จริงหลายบัญชี** — private profile/follow request, โพสต์และสื่อ, Comment Notification, ไฟล์แนบแชท, กลุ่ม และสิทธิ์ผู้ดูแล; แชทข้อความผ่านการทดสอบสองบัญชีแล้ว
3. **ตั้งค่า admin claim** ให้บัญชีผู้ดูแลก่อนทดสอบหน้าจัดการรายงาน
4. **ทดสอบบนโทรศัพท์จริง** รวมการรับอีเมลรีเซ็ตรหัสผ่าน อัปโหลดสื่อ และ UX/การเข้าถึง
5. เพิ่ม Firebase App Check, Pages และหลักฐาน Pain Point หากยังอยู่ในข้อกำหนดของรายวิชา
6. เตรียม build สำหรับส่ง, README/demo และทดสอบกรณีใช้งานให้ครบตามเกณฑ์อาจารย์

> Firestore Rules แก้ปัญหาส่งแชทเผยแพร่แล้วเมื่อ 21 ต.ค. 2026 และตรวจว่าตรงกับไฟล์ที่ทดสอบ รายละเอียดใน [รายงานแชท](tool/CHAT_DIAGNOSIS.md); งานนี้ไม่ได้เผยแพร่ Storage Rules/indexes หรือ push GitHub

## ผลตรวจในเครื่องล่าสุด

- `dart analyze lib test`: 0 errors, 0 warnings; พบ info-level lints 51 รายการ
- `dart format`: ผ่านสำหรับไฟล์ Dart ที่แก้ในรอบนี้
- Firestore และ Storage Emulator: เริ่มทำงานและโหลด Rules ได้สำเร็จ
- `flutter test --no-pub --reporter expanded`: ผ่าน 7/7 กรณี
- `firestore.indexes.json`: รูปแบบ JSON ถูกต้อง
- แชท: Rules ใน Emulator ผ่าน 25/25, `ChatService` จริงบน Chrome กับ Emulator ผ่าน 6/6 และ Firebase จริงสองบัญชีชั่วคราวผ่าน 10/10 ขั้นตอน; ลบข้อมูลและบัญชีทดสอบแล้ว
- ฟีเจอร์อื่นยังต้องทดสอบ integration หลายบัญชีเพิ่มเติม ดูรายละเอียดใน [CHANGELOG_TESTING.md](CHANGELOG_TESTING.md)
