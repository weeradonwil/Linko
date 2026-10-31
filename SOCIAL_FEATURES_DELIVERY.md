# Linko 1.1.0 — ระบบโซเชียลรอบ 31 ตุลาคม 2026

## สิ่งที่เพิ่ม

1. **ยืนยันอีเมล** หลังสมัคร มีปุ่มตรวจสถานะ ส่งลิงก์ซ้ำ และรอ 60 วินาทีก่อนส่งซ้ำ บัญชีเดิมมีช่วงผ่อนผัน 14 วันจากวันเปิดระบบ ไม่ต่ออายุเมื่อรัน migration ซ้ำ
2. **บล็อก/ปลดบล็อก** จากโปรไฟล์หรือแชท มีหน้ารายชื่อที่บล็อก ห้ามติดตามและส่งข้อความเมื่อบล็อกกัน ซ่อนโพสต์/ความคิดเห็นทั้งสองทาง รวมในกลุ่มเดียวกัน เก็บประวัติแชทไว้ เจ้าของกลุ่มยังตรวจหลักฐานรายงานได้
3. **ดูคนกดอิโมจิ** กดที่ยอดแล้วเลือกดูทั้งหมดหรือแต่ละอารมณ์ โหลดเพิ่มครั้งละ 30 คน ยอด Like/Dislike แยกไว้ ถ้ามีอารมณ์อื่นหลายชนิดจะรวมเป็น “อื่นๆ”
4. **รายงานโพสต์** หนึ่งบัญชีต่อหนึ่งโพสต์ แจ้งเมื่อเคยรายงานแล้ว เลือกซ่อนเฉพาะตัวเองได้ ไม่มีหน้าติดตามรายงานของผู้รายงาน
5. **เจ้าของกลุ่มจัดการรายงาน** เปิดจากรายละเอียดกลุ่ม ตรวจหลักฐาน ปิดเรื่อง เตือน หรือนำโพสต์ออกได้เฉพาะกลุ่มตัวเอง ไม่เห็น UID ผู้รายงาน และปิดรายงานโพสต์ของตัวเองไม่ได้
6. **กติกาฝั่ง server** ตรวจอีเมล สมาชิก การบล็อก และโทษพักโพสต์ก่อนเขียน ป้องกันรายงาน/แชร์ซ้ำ มีการจำกัดความถี่และ ticket ใช้ครั้งเดียวสำหรับโพสต์/ข้อความ
7. **คำเตือนและพักโพสต์** มีหน้า “คำเตือนและสิทธิ์โพสต์” พร้อมการแจ้งเตือนในแอป ผู้เขียนแก้ไข ลบ หรือโต้แย้งได้ เก็บข้อมูลและไฟล์หลักฐานแยกจากต้นฉบับ
8. **แชร์** โพสต์ต้นฉบับสาธารณะจาก Feed ไป Feed ตัวเอง กลุ่มที่เป็นสมาชิก หรือแชท เลือกแชทเดิมหรือคนที่ติดตามได้ และโหลดผู้รับ/กลุ่มเพิ่มเติมเป็นหน้าๆ เก็บรหัสต้นฉบับ ไม่คัดลอกเนื้อหาลับ เมื่อเสียสิทธิ์อ่านหรือต้นฉบับหายจะแสดงว่าเปิดไม่ได้
9. **ภาพปกโปรไฟล์** เลือกรูป เลื่อนจุดครอป ดูตัวอย่าง บันทึกภาพจริงขนาด 1200×400 หรือลบรูปได้ สิทธิ์อ่านรูปปกสอดคล้องกับบัญชีส่วนตัว
10. **ชุดทดสอบและเอกสาร** เก็บผลจริงใน `test_reports/social_2026-10-31/` และเพิ่มรายละเอียด schema/ขั้นตอนเปิดระบบ

## กติกาที่ใช้

- Feed: ผู้รายงาน **2 บัญชีไม่ซ้ำ** เริ่มเตือน ให้เวลา **24 ชั่วโมง** ถ้าไม่แก้/ลบ/โต้แย้ง ระบบนำโพสต์ออกและพักสิทธิ์โพสต์ **72 ชั่วโมง**
- งานตรวจหมดเวลารันทุก 5 นาที จึงอาจดำเนินการช้ากว่ากำหนดเล็กน้อย
- กลุ่ม: เจ้าของกลุ่มพิจารณาก่อนเตือน โทษจากรายงานในกลุ่มมีผลเฉพาะกลุ่มนั้น รายงานโพสต์ของเจ้าของกลุ่มใช้เกณฑ์อัตโนมัติแทนการให้เจ้าของตัดสินเอง
- บัญชีใหม่ต้องมีอายุ 24 ชั่วโมงก่อนรายงาน จำกัดรายงาน 10 ครั้ง/ชั่วโมง โพสต์ 5 ครั้ง/นาที ข้อความ 15 ครั้ง/10 วินาที และแชร์ 5 ครั้ง/นาที
- กลุ่มใช้โทษรวมของบัญชีด้วย จึงใช้การแชร์ลงกลุ่มเพื่อหลบโทษ Feed ไม่ได้ การพักสิทธิ์โพสต์ยังเปิดให้อ่านและใช้แชทได้
- รายชื่อผู้รายงานอยู่ในข้อมูลที่ผู้เขียน/เจ้าของกลุ่มอ่านไม่ได้ คิวสำหรับตรวจแยกจากข้อมูลผู้รายงาน

## ขอบเขตที่ควรรู้

- การตรวจว่าแก้แล้วเปรียบเทียบข้อความ path รูป/วิดีโอ และรหัสต้นฉบับ ไม่ได้ใช้ AI ตัดสินความเหมาะสมของเนื้อหา การแก้เพียงข้อความก็ถือว่าเปลี่ยนแล้ว
- การโต้แย้งหยุดการลงโทษอัตโนมัติ รายงานกลุ่มให้เจ้าของกลุ่มพิจารณาต่อ ส่วน Feed ยังไม่มีผู้ตัดสินข้อพิพาทอัตโนมัติ จึงไม่อ้างว่าพิสูจน์ถูกผิดได้
- การซ่อนโพสต์จากการบล็อกเป็นพฤติกรรมในแอป โพสต์สาธารณะไม่ได้กลายเป็นข้อมูลลับ สิทธิ์ห้ามติดต่อบังคับซ้ำใน Rules/backend
- แชร์ได้เฉพาะต้นฉบับสาธารณะใน Feed ยังไม่เปิดแชร์ต้นฉบับกลุ่มส่วนตัว/ผู้ติดตาม หรือแชร์ซ้อนหลายชั้น
- การแจ้งเตือนเป็น **ในแอป** ยังไม่ได้เพิ่ม push notification เมื่อปิดแอป
- เก็บหลักฐานสำหรับตรวจรายงาน ยังไม่มีนโยบายลบหลักฐานตามอายุหรือปุ่มกู้คืนโพสต์อัตโนมัติ
- หลักฐานโพสต์แชร์เก็บ caption และรหัสอ้างอิง การ์ดต้นฉบับยังใช้สิทธิ์ปัจจุบัน ไม่มีการ snapshot เนื้อหาต้นฉบับซ้ำ
- หน้าเจ้าของโพสต์/คิวกลุ่มแสดง 100 เรื่องล่าสุด ส่วนรายชื่อ reaction และตัวเลือกแชร์โหลดเพิ่มได้
- แอปรุ่นเก่าเขียนโพสต์/แชทและส่งรายงานได้ในช่วงผ่อนผันผ่าน worker ที่อ่านงานใหม่ทุก 1 นาที โทษพักโพสต์ยังบังคับเสมอ หลังหมดช่วงนี้ต้องอัปเดตแอป รายงานเก่าที่มีอยู่ก่อน rollout ยังคงเก็บไว้ แต่ไม่ย้อนลงโทษอัตโนมัติ
- ทดสอบบน Windows, Chrome และ Android build; การลองหลายบัญชีบนโทรศัพท์จริงและ iOS/macOS ยังต้องตรวจบนเครื่องเป้าหมาย

## เปิดระบบ Firebase

ต้องใช้บัญชีที่มีสิทธิ์ในโปรเจกต์ และโปรเจกต์ที่รองรับ Cloud Functions/Cloud Scheduler

```powershell
cd C:\flutter\social_app
cd functions
npm ci
cd ..

# สำรอง Rules ก่อน และดูจำนวนบัญชีที่จะได้รับช่วงผ่อนผัน (ยังไม่แก้ข้อมูล)
node tool/backup_firebase_rules.mjs --project social-network-app-c22eb
node functions/bootstrap.mjs --project social-network-app-c22eb --firebase-cli

# ระบุ endpoint ตรงๆ เพื่อไม่ให้ deploy ลบ resource อื่นในโปรเจกต์
$linkoNames = @('enforceWarnings','legacyReportWorker','blockCleanupWorker','evidenceCopyWorker','reserveWrite','respondToWarning','reviewGroupReport','sharePost','submitReport')
$linkoFunctions = $linkoNames | ForEach-Object { "functions:linko:$_" }
$linkoTargets = @('firestore:rules','firestore:indexes','storage') + $linkoFunctions
firebase deploy --only ($linkoTargets -join ',') --project social-network-app-c22eb
node tool/verify_firebase_release.mjs --project social-network-app-c22eb

# ให้ช่วงผ่อนผันก่อน แล้วเปิด flags เป็นขั้นตอนสุดท้าย
node functions/bootstrap.mjs --project social-network-app-c22eb --firebase-cli --apply --enable-moderation
node tool/verify_firebase_release.mjs --project social-network-app-c22eb --activated
```

`--firebase-cli` ใช้บัญชีที่ `firebase login` ไว้ ไม่ต้องสร้างไฟล์ service-account key หากใช้ ADC อยู่แล้ว ให้ตัด flag นี้ออก รันซ้ำไม่เขียนทับโทษพักโพสต์และไม่ต่อเวลาผ่อนผัน ค่า `autoEnforce` เปิดเฉพาะเมื่อระบุ `--enable-moderation`

สำรองและ log รายละเอียดเก็บใน `build/social-validation/` ซึ่งไม่เข้า Git ไม่ควรส่ง raw emulator/debug log เพราะอาจมีข้อมูล environment ของเครื่อง

## รันทดสอบซ้ำ

```powershell
flutter analyze
flutter test --no-pub --reporter expanded
node --test functions/test/policy.test.mjs

$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:LINKO_INCLUDE_BROWSER = 'true'
$env:LINKO_FLUTTER_SDK = 'C:\Users\Admin\flutter'
$env:CHROME_EXECUTABLE = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
firebase emulators:exec --config firebase.emulator.test.json --project demo-linko --only auth,firestore,storage,functions "node tool/run_social_validation.mjs"

flutter build apk --debug --no-pub
```

ชุด integration ใช้บัญชีและข้อมูลจริงบน **emulators ในเครื่อง** ไม่ส่งข้อความ/รายงานทดสอบใส่ผู้ใช้ production การจำลองครบกำหนดเรียก logic เดียวกับ scheduler โดยขยับเวลา fixture จึงไม่ต้องรอ 24 ชั่วโมงจริง

## ผลตรวจรับ

| การตรวจ | ผล |
|---|---|
| Analyzer | No issues found |
| Flutter unit/widget tests | 73/73 ผ่าน |
| Backend policy unit tests | 14/14 ผ่าน |
| ChatService จริงบน Chrome | 6/6 ผ่าน |
| Social services จริงบน Chrome | 9/9 ผ่าน |
| Firebase Emulator ชุดเดิม | 7/7 ชุดผ่าน |
| Firebase integration ฟีเจอร์ใหม่ | 25/25 ผ่าน |
| Android debug APK | Build ผ่าน; label Linko, version 1.1.0+4 |

APK ในเครื่อง: `build/app/outputs/flutter-apk/Linko-1.1.0-debug.apk`

ยังมีคำเตือนจาก dependency เรื่อง Java native access และการย้าย Kotlin Gradle Plugin ใน Flutter รุ่นถัดไป build ปัจจุบันผ่าน ไม่ได้เปลี่ยน toolchain เดิมโดยพลการ และ CLI แจ้งว่ามี firebase-functions major ใหม่กว่า แต่รอบนี้คง lockfile ที่ทดสอบแล้ว

### สถานะ production

เปิดใช้จริงบน `social-network-app-c22eb` แล้ว หลังผู้ใช้ยืนยันอนุมัติ production แยก:

- Firestore/Storage Rules ที่เผยแพร่มี SHA-256 ตรงกับไฟล์ที่ทดสอบ
- indexes ที่ต้องใช้ 15 รายการเป็น READY; Functions 9 ตัวเป็น ACTIVE; Scheduler 4 jobs เป็น ENABLED และใช้ OIDC
- เปิด verification, write tickets, report backend, evidence copies และ `autoEnforce:true`; นโยบาย 2 บัญชี / 24 ชั่วโมง / 72 ชั่วโมงตรงกับที่ตกลง
- ให้สิทธิ์ผ่อนผันบัญชีเดิม 10 บัญชีสำเร็จ เริ่ม 31 ตุลาคม 2026 เวลา 18:22:36 น. ถึง **14 พฤศจิกายน 2026 เวลา 18:22:36 น. (Asia/Bangkok)** ไม่เขียนทับโทษพักโพสต์เดิม
- endpoint ทั้ง 5 ปฏิเสธคำขอที่ไม่ล็อกอินด้วย HTTP 401/UNAUTHENTICATED และ CORS preflight ผ่าน HTTP 204
- worker ทั้ง 3 รันจริงหลัง activation และเขียน protected cursor ได้ ตรวจด้วย API แบบอ่านอย่างเดียว
- ผลจริงอยู่ที่ [production-verification.json](test_reports/social_2026-10-31/production-verification.json)

ไม่สร้างโพสต์/แชท/รายงานทดสอบบน production ผลทดสอบหลายบัญชีและการจำลองครบกำหนดโทษอยู่บน emulators การลองใช้งานหลายบัญชีบนโทรศัพท์จริงยังต้องตรวจบนเครื่องเป้าหมาย

รายการ Gen1 3 ตัวที่สร้างไม่สำเร็จยังเก็บไว้ ผู้ใช้ถามคำอธิบายและยังไม่ได้ยืนยันลบ ไม่กระทบ Functions 9 ตัวที่ใช้งานจริง


## ความเข้ากันได้กับฐานข้อมูลเดิม

ฐานข้อมูล production เป็น Firestore Native/Standard ที่ `asia-southeast3` (Bangkok) ระหว่าง deploy Functions API ปฏิเสธ Firestore trigger ทั้ง Gen1 และ Gen2 สำหรับภูมิภาคนี้ จึงใช้ worker ตามเวลาแทน โดยไม่ย้ายฐานข้อมูลหรือเปลี่ยน path โพสต์/แชท/สมาชิก

Functions ที่เปิดใช้งานจริงทั้งหมด 9 ตัวเป็น Gen2/Node22 ที่ `asia-southeast1`:

- callable 5 ตัว: `reserveWrite`, `submitReport`, `respondToWarning`, `reviewGroupReport`, `sharePost`
- `enforceWarnings`: ตรวจคำเตือนหมดเวลาทุก 5 นาที
- `legacyReportWorker`: อ่านรายงานใหม่จากแอปรุ่นเก่าทุก 1 นาที
- `blockCleanupWorker`: ล้างการติดตามที่ค้างหลังบล็อกทุก 1 นาที; การห้ามติดต่อบังคับทันทีใน Rules/backend และแอปทำ cleanup เองด้วย
- `evidenceCopyWorker`: ลองเก็บหลักฐานที่ค้างทุก 1 นาที; รายงานจาก callable เริ่มคัดลอกก่อนตอบกลับอยู่แล้ว

worker อ่านเฉพาะงานตั้งแต่ rollout เก็บ checkpoint ด้วยเวลาและ document ID รองรับเวลาซ้ำ มี lease ป้องกันงานทับกัน และไม่ขยับ checkpoint ของหน้าที่ยังทำไม่ครบ ประมวลผลสูงสุด 400 รายการต่อรอบ งานค้างทำต่อในรอบถัดไป หาก process หยุดฉับพลันจะรอ lease หมดอายุ (4 นาที) แล้วทำต่อ

ทดสอบการแบ่งหน้า งานซ้อน และการขัดข้องกลางหน้าบน Firebase Emulator รวมกับระบบเดิม ผลรอบสุดท้ายอยู่ในไฟล์แนบ

มี Cloud Scheduler ทั้งหมด 4 jobs ตามความถี่ข้างต้นและใช้ค่าบริการของโปรเจกต์ รายการ Gen1 เก่า `ingestLegacyReport`, `onBlockChanged`, `preserveEvidence` สร้างล้มเหลวและไม่ได้เปิดใช้งาน ระบบตรวจอนุมัติอัตโนมัติขอคำยืนยันก่อนลบ จึงยังเก็บไว้ตามคำตอบล่าสุดที่ผู้ใช้ขอคำอธิบาย

อ้างอิงพฤติกรรม API: [ภูมิภาค Functions](https://firebase.google.com/docs/functions/locations), [ตำแหน่ง Eventarc/Firestore](https://docs.cloud.google.com/eventarc/docs/locations), [runtime Node22](https://docs.cloud.google.com/functions/docs/runtime-support) การปฏิเสธ Bangkok ที่ระบุข้างต้นเป็นผลจาก API ของโปรเจกต์ขณะ deploy ไม่ใช่การสรุปว่า Eventarc ทุกบริการไม่รองรับ Bangkok
