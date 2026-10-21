# โหมดและสีการแสดงผลของ Linko

## วิธีใช้

กดไอคอนพาเลต **การแสดงผล** บนหน้าเข้าสู่ระบบ หน้าฟีด หรือ AppBar ร่วม แล้วเลือก:

1. โหมด **สว่าง / มืด** เพื่อกำหนดหน้าตาของแอป
2. สีจากรายการด้านล่างที่มีจุดสี ชื่อสี และเครื่องหมายเลือก เพื่อปรับสีของโหมดที่กำลังใช้งาน

มีตัวเลือกโหมดภาษาไทยแถวเดียว เมื่อสลับโหมด ช่องเลือกสีจะแสดงสีที่เคยตั้งไว้ของโหมดนั้น และยังจำสีอีกโหมดแยกกัน เลือก **คืนค่าเริ่มต้น** เพื่อกลับเป็นโหมดเริ่มต้นในรอบนี้และสี Linko ของทั้งสองโหมด

## ชุดสี

| ตัวเลือก | ID ที่บันทึก | Light | Dark |
|---|---|---|---|
| ค่าเริ่มต้น Linko | `default` | `#C92847` | `#FF8092` |
| น้ำเงิน | `blue` | `#2457D6` | `#8EADFF` |
| เขียว | `green` | `#006B57` | `#4DD4AC` |
| เหลือง | `yellow` | `#805600` | `#FACC15` |
| ชมพู | `pink` | `#B21C65` | `#FF9ACD` |
| ส้ม | `orange` | `#A13C00` | `#FFB784` |
| ม่วง | `purple` | `#7430BE` | `#D3AEFF` |
| ขาว / ดำ | `monochrome` | `#171A21` | `#F8FAFC` |

พื้นหลังและการ์ดใช้โทนสว่าง/มืดเดิม สีหลักเปลี่ยนปุ่ม ลิงก์ แท็บ กรอบช่องกรอก สถานะเลือก สื่อควบคุมวิดีโอ และข้อความแชทฝั่งผู้ส่ง สีข้อความบนปุ่มและแชทเลือกจากความต่างความสว่างจริง โดยสีแจ้งข้อผิดพลาดยังใช้บทบาท `error/onError` แยกจากสีหลัก

## หน้าที่ของไฟล์

- [`theme_accent.dart`](../lib/core/theme/theme_accent.dart): รายการสี เฉดของสองโหมด และ ID คงที่
- [`app_theme.dart`](../lib/core/theme/app_theme.dart): สร้าง `ThemeData/ColorScheme` พร้อมสีข้อความที่เข้าคู่กัน
- [`appearance_controller.dart`](../lib/core/theme/appearance_controller.dart): เปลี่ยนโหมด/สี อ่านและบันทึกค่าลงเครื่อง เรียงงานบันทึก และกระจายการเปลี่ยนแปลงให้ route ต่าง ๆ
- [`appearance_settings.dart`](../lib/core/widgets/appearance_settings.dart): ปุ่มเปิดเมนู ตัวเลือกสว่าง/มืด และรายการสีแยกสองโหมด
- [`main.dart`](../lib/main.dart): เชื่อมตัวควบคุมกับ `MaterialApp` เหนือ Navigator เพื่อให้หน้าที่เปิดค้างเปลี่ยนธีมพร้อมกัน
- [`appearance_test.dart`](../test/appearance_test.dart): ตรวจคู่สี การจำค่า การคืนค่าเริ่มต้น การกู้การบันทึก และเมนูบนจอเล็ก
- [`appearance_smoke.dart`](appearance_smoke.dart): หน้าแยกทดสอบ render ของ 16 ชุดและ storage บนแพลตฟอร์มจริง โดยไม่เรียก `Firebase.initializeApp()`
- [`run_appearance_smoke.mjs`](run_appearance_smoke.mjs): เปิด Flutter/Chrome ทดสอบ เก็บผลและภาพ และปิด process/ลบโปรไฟล์ชั่วคราวที่สร้างเอง

## การบันทึกและค่ารุ่นเดิม

ใช้ `SharedPreferences` ภายในเครื่อง:

- `social_app_theme_mode`: ใช้ key เดิม บันทึกค่า `light` หรือ `dark`
- `social_app_light_accent`: สีของโหมดสว่าง
- `social_app_dark_accent`: สีของโหมดมืด

ค่ารุ่นเดิมที่ยังไม่มีสีใช้ค่าเริ่มต้น Linko ส่วน ID ที่ไม่รู้จักกลับเป็นค่าเริ่มต้น หากไม่มีโหมดที่บันทึกไว้หรือยังเป็น `system` จะเลือกสว่าง/มืดตามความสว่างเครื่องเมื่อเริ่มแอปครั้งเดียว และไม่เปลี่ยนตามเครื่องระหว่างใช้งาน การเลือกครั้งถัดไปจะบันทึกโหมดสว่าง/มืดที่ใช้อยู่ การโหลดค่าที่เสร็จช้าไม่ทับตัวเลือกใหม่ของผู้ใช้ และการบันทึกเรียงลำดับเพื่อคงค่าล่าสุดเมื่อกดเปลี่ยนเร็ว ๆ หากบันทึกไม่สำเร็จ แอปยังใช้สีที่เลือกในรอบนั้นและบอกสถานะในเมนู เมื่อ storage กลับมาใช้งานได้ การเลือกครั้งถัดไปบันทึกค่าปัจจุบันครบทั้งโหมดและสองสี

บนเว็บค่าผูกกับ browser และ origin เดิม; การรัน Flutter ด้วย port ใหม่ใช้ local storage คนละชุด การตั้งค่านี้ไม่ได้ซิงก์ข้ามเครื่องหรือข้ามบัญชี

## การตรวจสอบ

ผลล่าสุดวันที่ 21 ต.ค. 2026: `flutter test` ผ่าน 34/34, Chrome จริงผ่าน 17/17 และ analyzer ของโค้ดธีม/ชุดทดสอบใหม่ไม่พบปัญหา ตรวจภาพเมนูบน Chrome แล้ว

Android Emulator ตรวจธีมที่ render ใน widget tree และการอ่านค่ากลับจาก storage จริงผ่าน 17/17 เช่นกัน หลักฐานคือ `build/appearance_diagnostics/android_results.json` แต่การจับภาพด้วย `adb screencap` ค้างจนหมดเวลา ทำให้สคริปต์ตรวจ Android จบด้วย error ในขั้นตอนเก็บภาพ ไม่ใช่การตรวจทั้ง 17 กรณี จึงยังไม่มีภาพ Android สำหรับยืนยันด้วยสายตา

การ build Android ครั้งแรกเตรียม SDK Platforms 34/35 เพิ่ม เครื่องทดสอบมี RAM ประมาณ 6 GB จึงใช้ heap 1.5 GB และ worker 2 ตัวเฉพาะคำสั่ง Gradle โดยไม่แก้ `gradle.properties` ถาวร สร้าง APK ทดสอบสำเร็จ และติดตั้งแบบไม่ใช้ streaming บน Emulator RAM 2 GB ที่เปิดแบบ read-only จากนั้นปิด Emulator แล้ว

```powershell
flutter test --no-pub --reporter expanded
$env:CHROME_EXECUTABLE = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
node tool/run_appearance_smoke.mjs
```

ชุดทดสอบวัดคู่สีข้อความ 9 คู่และแถบวิดีโอบนพื้นดำอีก 1 คู่ต่อชุด ทั้ง 8 สี × 2 โหมด รวม 160 คู่ โดยเกณฑ์ข้อความทั่วไปอย่างน้อย 4.5:1 ตาม [W3C](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum) แถบวิดีโอเลือกเฉดที่ผ่าน 4.5:1 เช่นกัน และตรวจการคืนค่าเดิม การอ่านค่า `system` รุ่นเก่าเป็นสว่าง/มืด การสลับโหมดแล้วเลือกสีจากแถวเดียว การจำสีแยกสองโหมด และความกว้างจอ 320 พิกเซล

หน้า smoke ใช้ `SocialApp` และ `AppearanceController` จริง ตรวจธีมที่ render หลังเปลี่ยนแต่ละชุดและอ่านค่าด้วยตัวควบคุมใหม่ รวม 17 กรณี เรียก `SharedPreferences.reload()` เพื่ออ่าน storage ของแพลตฟอร์มใหม่แล้วคืนค่าเดิมเมื่อจบ สำหรับ Android ให้รันหน้า smoke บน Emulator ที่ใช้ทดสอบเท่านั้น:

```powershell
flutter run -d <emulator-id> --target=tool/appearance_smoke.dart
```

ผล Chrome และภาพอยู่ใน `build/appearance_diagnostics/` ซึ่งเป็นไฟล์ผลตรวจในเครื่อง ไม่ต้องเพิ่มเข้า Git

APK ใน `build/app/outputs/` ที่เกิดจากคำสั่งทดสอบนี้ใช้ entry point `tool/appearance_smoke.dart` สำหรับทดสอบเท่านั้น เมื่อต้องการรันหรือสร้างแอป Linko ปกติ ให้ใช้ entry point `lib/main.dart` ตามค่าเริ่มต้นของ `flutter run`/`flutter build`
