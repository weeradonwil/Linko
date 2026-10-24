# Linko — งานแก้ไขและตรวจรับ 24 ตุลาคม 2026

รายงานนี้เป็นสถานะของโค้ดในเครื่องรอบปัจจุบัน ผลวันที่ 21–22 ตุลาคมในเอกสารเดิมเป็นประวัติคนละรุ่น

## ชื่อและไอคอน Linko — รุ่น 1.0.1+2

เปลี่ยนชื่อที่ผู้ใช้เห็นเป็น **Linko** และใช้ไอคอนห่วงสีขาวเชื่อมเป็นรูปทรงคล้ายตัว L บนพื้นสีแดงราสป์เบอร์รี เก็บต้นฉบับจากเครื่องมือ imagegen แบบ built-in, prompt และวิธีส่งออกแต่ละขนาดใน [`assets/branding/README.md`](assets/branding/README.md)

Analyzer ผ่านโดยไม่มี findings, Flutter tests ผ่าน **54/54** และ Android Debug build ผ่าน ตรวจ APK ที่ build จริงแล้วยืนยันชื่อ Linko, เวอร์ชัน `1.0.1`, build number `2` รหัสแอป `com.example.social_app` และลายเซ็นตรงกับ APK ก่อนแก้ ไอคอนใน APK ทั้ง 5 density ตรงกับไฟล์ต้นทางทุกพิกเซล

APK พร้อมติดตั้งอยู่ที่ `build/app/outputs/flutter-apk/Linko-1.0.1-debug.apk` (165,614,481 bytes); SHA-256: `a5056a985e46b041181c2bceb3f89ba6c423c82617b18db76f6e89c568b1d5b7` หลักฐานรอบนี้อยู่ใน `build/branding-2026-10-24/` ได้แก่ `apk-verification.json`, `analyzer-result.json`, `flutter-tests.log` และ `android-build.log`

ตรวจไอคอน PNG RGB รวม 40 รายการตาม catalog และ Windows ICO 7 ขนาดผ่าน; XML/plist/scheme parse ผ่าน การตรวจนี้ยังไม่แทนการติดตั้งบนมือถือจริงหรือ build iOS/macOS บน Mac

Web release build ผ่าน ตรวจผลใน `build/web` แล้วยืนยัน title/manifest เป็น Linko, เวอร์ชัน `1.0.1` build `2` และไอคอนที่บรรจุทั้ง 5 ไฟล์ตรงกับต้นทาง หลักฐานเพิ่มเติมคือ `web-build.log` และ `web-verification.json` ในโฟลเดอร์ผลตรวจรอบนี้

## ขอบเขตและเงื่อนไขที่ตกลง

- เก็บงานเดิมใน working tree และรวมส่วนที่ merge ค้างโดยรักษาธีม การซ่อมโปรไฟล์ และการล้างเซสชัน
- วิดีโอใช้ขนาดไม่เกิน **50 MB (50 × 1024 × 1024 bytes)** ตามคำตอบผู้ใช้ ไม่จำกัดจำนวนวินาที
- ทำระบบกลุ่มให้ครบตามทางเลือก “กลุ่มหรือเพจ”; Pages เป็นงานต่อยอด
- เพิ่มคอมเมนต์ภาษาไทยในส่วนสำคัญที่พัฒนา อธิบายหน้าที่ เงื่อนไขสิทธิ์ และเหตุผลของการจัดการข้อมูล

## สิ่งที่เปลี่ยน

1. รวม conflict 10 ไฟล์ของแอป Rules ชุดทดสอบ และเอกสาร
2. โพสต์กลุ่ม: Comment, แก้ข้อความ/แท็ก/สื่อ, ลบโพสต์พร้อมข้อมูลย่อย, รายงาน และการลบโดยผู้ดูแล
3. ใช้ฟอร์มโพสต์และหน้าความคิดเห็นร่วมกันระหว่างฟีดหลักกับกลุ่ม; แยกการ์ดกลุ่มออกจากหน้าจอขนาดใหญ่
4. เพิ่มการแจ้งเตือน Like/Comment ของกลุ่มให้เจ้าของโพสต์ที่ยังเป็นสมาชิก และเปิดกลับไปยังโพสต์กลุ่มได้
5. ค้นสมาชิกเก่าทุกช่วงด้วย cursor รวมบัญชีที่ไม่มี `createdAt` หรือ `displayNameLower`
6. โหลดแจ้งเตือนย้อนหลังเกิน 100 รายการ และแสดง error/ลองใหม่ได้เมื่ออ่านสิทธิ์ผู้ดูแลล้มเหลว
7. ตรวจขนาดไฟล์กลุ่มก่อนอ่านเข้าหน่วยความจำ และใช้ Firebase SDK อ่านวิดีโอก่อนส่งให้ตัวเล่นผ่านไฟล์ชั่วคราว/Blob
8. เพิ่ม regression test สำหรับหน้าผู้ดูแล, Rules ของโพสต์กลุ่ม และบริการ Flutter หลายบัญชีบน Chrome

## การตรวจรับ

| การตรวจ | สถานะ |
|---|---|
| ชุดเดิมหลังรวม merge | ผ่าน 53 เคส รวม thumbnail 2 เคส |
| Analyzer ทั้งโปรเจกต์ | ผ่าน ไม่มี error, warning หรือ info |
| Flutter tests รวม regression ใหม่ | ผ่าน 54/54 เคส รวมการลองอ่านสิทธิ์ใหม่เมื่อเครือข่ายล้มเหลว |
| Firebase Emulator Rules รุ่นสุดท้าย | ผ่าน 7/7 suites รวม notification กลุ่มและสิทธิ์ล้าง Reaction ของเจ้าของโพสต์; ชุดวินิจฉัยแชทผ่าน 25/25 |
| Flutter services / Chrome / Emulator | ChatService ผ่าน 6/6 และ Social services ผ่าน 9/9 กรณี |
| Android Debug | ผ่าน `:app:assembleDebug --offline`; APK อยู่ที่ `build/app/outputs/flutter-apk/app-debug.apk` |
| Build เว็บแอปหลัก | ผ่าน release build จาก `lib/main.dart`; ผลอยู่ใน `build/web` |
| Syntax สคริปต์ Node | ผ่าน 14/14 ไฟล์ |

ผล Social 9 กรณีครอบคลุมสมัคร/ล็อกอิน/แก้โปรไฟล์, โพสต์หลัก, โพสต์กลุ่ม, ลบทั้งกลุ่มพร้อมข้อมูลย่อย, follow ส่วนตัวและสิทธิ์สื่อ, ค้นบัญชีเก่าเกิน 150 ราย, แจ้งเตือนเกิน 100 รายการ, อัปโหลด/เล่นวิดีโอจริง และปฏิเสธไฟล์เกิน 50 MB

หลักฐานรอบนี้:

- `build/audit-2026-10-24/final-analyzer.log` — ว่างเมื่อไม่มี findings และคำสั่งจบด้วย exit code 0
- `build/audit-2026-10-24/flutter-final-tests.log` — Flutter 54 เคสผ่าน
- `build/chat_diagnostics/chat_service_results.json` — ChatService 6 กรณี
- `build/social_diagnostics/chat_service_results.json` — Social 9 กรณีพร้อมเวลาจริงราย flow
- `build/audit-2026-10-24/delivery-tests.log` — browser และ Rules จบด้วย exit code 0
- `build/audit-2026-10-24/android-debug.log`, `app-web-build.log` — ผล build

ระหว่างพัฒนาทดสอบพบและแก้ error ของ callback `setState` ที่คืน Future, การรับ error เร็วก่อน FutureBuilder แนบ listener และสิทธิ์เจ้าของโพสต์ในการล้าง Reaction ของสมาชิกคนอื่น ชุดทดสอบเว็บรอ build ใหม่พร้อมก่อนเปิด Chrome และรองรับเสิร์ฟ build แยกเพื่อหลีกเลี่ยงการโหลดผลรอบเก่า

การทดสอบ CRUD โพสต์กลุ่มกับการลบทั้งกลุ่มแยกเป็นสอง flow มี timeout จำกัด 240 วินาทีต่อ flow และบันทึกเวลาจริง เพื่อให้คำขอเดิมจบก่อนเริ่มกรณีถัดไป ผลนี้ยืนยันความถูกต้องของขั้นตอนใน Emulator ยังไม่ใช่การวัดประสิทธิภาพบน production

รอบสุดท้าย CRUD โพสต์กลุ่มใช้ 61.63 วินาที และ flow สร้าง/เข้าร่วม/โพสต์/ออก/ลบทั้งกลุ่มใช้ 120.13 วินาทีรวมหลายคำสั่งต่อเนื่อง ควรวัดเวลารายการกระทำบน Firebase และอุปกรณ์จริงก่อนใช้เป็นเกณฑ์ประสิทธิภาพ

รวม merge และ push โค้ดที่ตรวจรับขึ้น `main` แล้วใน commit `9d2115b` โดยเก็บการเปลี่ยนแปลงเดิมไว้

## Deploy Firebase production — 24 ตุลาคม 2026

เผยแพร่ Firestore Rules, Storage Rules และ indexes จาก commit `9d2115b` ไปยัง `social-network-app-c22eb` สำเร็จเมื่อ **16:16:59 น. (Asia/Bangkok)** ด้วย Firebase CLI ซึ่งตรวจ compile Rules ทั้งสองไฟล์ผ่านก่อนเผยแพร่

อ่าน Rules ที่เผยแพร่จริงกลับจาก Firebase Rules API แล้วเทียบเนื้อหาและ SHA-256 กับไฟล์ที่ทดสอบ: ตรงกันทั้งสองไฟล์ ตรวจ Firestore Admin API แล้ว indexes ที่ต้องใช้ **11/11 รายการเป็น `READY`** ไม่มีรายการขาดหรือรอสร้าง ดัชนีทั้ง 11 รายการมีอยู่แล้วก่อน deploy

| ส่วน | Ruleset ที่เผยแพร่ |
|---|---|
| Firestore | `projects/social-network-app-c22eb/rulesets/01ee4d59-2de5-4b65-bc10-5196a0491474` |
| Storage | `projects/social-network-app-c22eb/rulesets/16213797-63eb-47d5-b02b-70eddc931454` |

สำรอง Rules เดิมและ metadata ของ indexes ก่อน deploy ไว้ในเครื่องที่ `build/deploy-2026-10-24/before-*` ส่วนหลักฐานหลังเผยแพร่อยู่ที่ `after-metadata.json`, `after-firestore.rules`, `after-storage.rules` และ `deploy.log` ในโฟลเดอร์เดียวกัน ไฟล์สำรองไม่มี credentials และไม่ถูกนำขึ้น Git

ขอบเขตรอบนี้คือ Rules/indexes ของ Firebase; การทดสอบผ่านหน้าแอปกับบัญชีจริงหลายบัญชีและอุปกรณ์จริงยังต้องทำแยกจากผลตรวจ deployment

## คำสั่งทดสอบ

```powershell
dart analyze
flutter test --no-pub test packages/video_thumbnail/test/video_thumbnail_test.dart
firebase --config firebase.emulator.test.json emulators:exec --only "auth,firestore,storage" --project demo-linko "node tool/run_emulator_tests.mjs"
# กำหนด CHROME_EXECUTABLE และ LINKO_FLUTTER_SDK ให้ชี้เครื่องนี้ก่อนรัน
firebase --config firebase.emulator.test.json emulators:exec --only "auth,firestore,storage" --project demo-linko "node tool/run_service_checks.mjs"
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run
```

## สิ่งที่ต้องตรวจแยกจากผลในเครื่อง

- การทดสอบหลายบัญชีผ่านแอปบน Firebase เป้าหมายหลัง deploy Rules/indexes
- อุปกรณ์จริงและ iOS/macOS บน Mac; Windows ยังแสดงข้อความว่าวิดีโอไม่รองรับ และ Linux ยังไม่มี Firebase configuration
- Signed release ต้องใช้ keystore ของเจ้าของแอป; ไม่สร้างกุญแจแทนเจ้าของ
- วิดีโอใหม่ในแอปอ่านด้วย SDK; download URL ที่แจกไว้ก่อนหน้านี้ต้องเพิกถอน token แยกหากต้องการปิดลิงก์เดิม
- ตัวเล่นวิดีโอรูปแบบนี้ดาวน์โหลดไฟล์ก่อนเริ่มเล่น และล้างไฟล์ชั่วคราว/Blob เมื่อปิดตัวเล่น
- การแจ้งเตือนแบบ Push และงานคิว backend เมื่อปิดแอปยังเป็นงานต่อยอด
- หลักฐาน pain-point จากผู้ใช้จริงยังรอข้อมูลจากผู้ใช้ ไม่สร้างผลสัมภาษณ์หรือผลทดลองใช้แทน

ชุดทดสอบวิดีโอใช้ [ไฟล์ตัวอย่างจากเอกสาร Flutter](https://docs.flutter.dev/cookbook/plugins/play-video) โดย cache ที่ `build/social_diagnostics/butterfly.mp4` และเสิร์ฟเฉพาะในเครื่องขณะทดสอบ ไม่แนบไฟล์นี้ในแอปส่งมอบ
