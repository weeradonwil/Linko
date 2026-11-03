# ผลตรวจ Linko 1.1.2+6

วันที่ 3 พฤศจิกายน 2026 — Firebase project: `social-network-app-c22eb`

## ผลทดสอบ

| รายการ | คำสั่ง/วิธีตรวจ | ผล |
| --- | --- | --- |
| วิเคราะห์โค้ด Flutter | `flutter analyze --no-pub` | ผ่าน ไม่มี issue |
| Flutter unit/widget tests | `flutter test --no-pub` | ผ่าน 108 เคส |
| Functions unit tests | `cd functions` แล้ว `npm.cmd test` | ผ่าน 18 เคส |
| ตรวจ syntax Functions | `cd functions` แล้ว `npm.cmd run check` | ผ่าน |
| Firebase Emulator | `firebase.cmd emulators:exec --project demo-linko --config firebase.emulator.test.json "node tool/run_emulator_tests.mjs"` | ผ่านครบ 7 ชุด รวม Rules, แท็กเพื่อน, กลุ่ม, แชท และรูปโปรไฟล์ |
| ตรวจ production | `node tool/verify_firebase_release.mjs --project social-network-app-c22eb --activated` | Rules ตรงกับโค้ด, indexes พร้อม, Functions 11 ตัวทำงาน, Scheduler 5 ตัวเปิดใช้งาน |
| ย้ายรูปโปรไฟล์เก่า | `node tool/backfill_profile_thumbnails.mjs social-network-app-c22eb` | 14 โปรไฟล์ เหลือ 0 โปรไฟล์ที่ขาดภาพตัวอย่าง |
| Android | `flutter build apk --debug --no-pub` แล้วติดตั้งด้วย `adb install -r` | สร้างและติดตั้งสำเร็จ; ชื่อ Linko, เวอร์ชัน 1.1.2, versionCode 6 |
| โพสต์แท็กเพื่อนจริง | บัญชีทดสอบใน Android Emulator สร้างโพสต์ข้อความที่แท็ก `@Paradise` | บันทึกสำเร็จและชื่อแสดงบนฟีด; ลบโพสต์ QA หลังตรวจ |
| กดแท็กและหน้าสร้างโพสต์ | ติดตั้ง APK ล่าสุดบน Android Emulator แล้วกด `@Paradise` ในโพสต์ที่มีอยู่ | เปิดโปรไฟล์ Paradise ได้จริง; ข้อความเตือนใต้ชื่อบัญชีในหน้าสร้างโพสต์ถูกนำออก |

APK ที่สร้างบนเครื่อง: `build/app/outputs/flutter-apk/Linko-1.1.2-debug.apk` (SHA-256 `231FBF25EB6E22F1A548F2F722F4B29ACD2ACADBCEA509BD382DD7CE741E3218`)

## ขอบเขตที่ยังไม่ได้ยืนยัน

- APK นี้เป็น debug build ที่อยู่ในเครื่อง ยังไม่ได้อัปโหลดเป็น GitHub Release หรือทดสอบติดตั้งบนโทรศัพท์จริง
- โพสต์ QA มาจากบัญชีส่วนตัว จึงใช้ยืนยันการบันทึกและการแสดงแท็ก ไม่ใช่การแจ้งเตือนถึงผู้ถูกแท็กบน production; การแจ้งเตือนทดสอบผ่าน Firebase Emulator และตรวจว่า worker บน production ทำงานแล้ว
- Firebase Emulator บางเคสที่คาดว่าจะถูกปฏิเสธมีคำเตือน `maximum of 1000 expressions` จาก Rules runtime ผล 403 ปลอดภัยตามที่คาด แต่เคสเหล่านั้นยังไม่พิสูจน์ว่าเข้ากิ่ง Rules ที่ตั้งใจทุกกรณี
