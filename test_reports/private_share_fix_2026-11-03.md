# แก้แชร์โพสต์ของบัญชีส่วนตัวไปกลุ่มและแชท

วันที่ 3 พฤศจิกายน 2026 · Firebase `social-network-app-c22eb`

## ผลที่แก้

- เจ้าของบัญชีส่วนตัวแชร์โพสต์ต้นฉบับของตัวเองที่ตั้งผู้ชมเป็นสาธารณะไปกลุ่มหรือแชทได้
- สมาชิกกลุ่มปัจจุบันหรือผู้รับแชทเท่านั้นที่เปิดเนื้อหาและสื่อของโพสต์ต้นฉบับได้
- ลบรายการแชร์ ออกจากกลุ่ม หรือยกเลิกข้อความแชร์แล้ว สิทธิ์อ่านต้นฉบับจะหมดทันที
- แชร์ไปฟีดสาธารณะยังไม่เปิดให้บัญชีส่วนตัว เพื่อไม่ให้โพสต์รั่วไปนอกกลุ่มหรือแชท

## สิ่งที่ตรวจแล้ว

| คำสั่ง | ผล |
| --- | --- |
| `flutter analyze --no-pub` | ผ่าน ไม่มี issue |
| `flutter test --no-pub --reporter expanded` | ผ่าน 108 เคส |
| `cd functions && npm.cmd run check && npm.cmd test` | ผ่าน 18 เคส |
| `firebase.cmd emulators:exec --project demo-linko --config firebase.emulator.test.json "node tool/social_features_emulator_test.mjs"` | ผ่าน 35 เคส รวมสิทธิ์กลุ่ม แชท รูป และการถอนสิทธิ์ |
| `firebase.cmd emulators:exec --project demo-linko --config firebase.emulator.test.json "node tool/run_emulator_tests.mjs"` | ผ่านทั้ง 7 ชุด |
| `node tool/verify_firebase_release.mjs --project social-network-app-c22eb --activated` | Rules ตรงไฟล์, Functions 11 ตัวพร้อมใช้งาน, indexes พร้อม |
| `flutter build apk --debug --no-pub` และติดตั้งบน emulator | ผ่าน แอปเปิดได้ |

APK ใหม่อยู่ที่ `build/app/outputs/flutter-apk/Linko-1.1.2-share-fix-debug.apk` (SHA-256 `CFBDF182CDD63EC437079CBA5AEE18DF9F183386C76B076D17454159CD718D36`) ยังไม่ได้อัปโหลดขึ้น GitHub Release

การกดแชร์โพสต์จริงบน production ใน emulator ถูกระบบตรวจอนุมัติอัตโนมัติปฏิเสธ เพราะจะสร้างโพสต์ในกลุ่มและอาจแจ้งเตือนสมาชิก จึงยังไม่มีผลทดสอบแบบส่งจริงบน production
