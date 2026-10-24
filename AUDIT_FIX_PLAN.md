# Linko — แผนแก้ไขผลตรวจระบบ 2026-10-22

> รอบปัจจุบันวันที่ 24 ตุลาคม 2026 แก้ merge และเติมโพสต์กลุ่มต่อจากแผนนี้ ผลล่าสุดอยู่ใน [DELIVERY_REPORT.md](DELIVERY_REPORT.md) ตารางด้านล่างเป็นประวัติของวันที่ 22 ตุลาคม

สถานะ: ✅ ดำเนินการแก้และตรวจในเครื่องครบทั้ง 5 ขั้น เก็บการเปลี่ยนแปลงเดิมใน working tree ไว้ ผลนี้ยังไม่ใช่การยืนยัน production หรืออุปกรณ์จริง

| ลำดับ | งาน | เกณฑ์เสร็จ | สถานะ |
|---|---|---|---|
| 1 | แชท: Rules, ส่งต่อเนื่อง, เปิดห้องซ้ำ, follow, ซ่อนห้อง, schema | Emulator ผ่านข้อความซ้ำ/ตอบกลับ/เปิดซ้ำ/ซ่อนแล้วรับข้อความใหม่ และปฏิเสธผู้ไม่มีสิทธิ์/ข้อมูลผิดชนิด | ✅ |
| 2 | Post/profile schema, สิทธิ์กลุ่ม, สื่อกลุ่ม, แจ้งเตือน comment | ข้อมูลผิดชนิดถูกปฏิเสธ; owner ลบไฟล์ของสมาชิกได้; admin อนุมัติ private group ได้; แจ้งเตือนผู้ติดตาม 25 คนสำเร็จ | ✅ |
| 3 | โพสต์และโปรไฟล์: แก้สื่อเดิม, ลบข้อมูลย่อย, recovery, privacy หลาย batch | Rules/policy tests ผ่านสื่อเดิม/โพสต์ว่าง/ลบข้อมูลย่อย/ซ่อมโปรไฟล์; privacy protocol ครบ 501 โพสต์และทำต่อได้ | ✅ |
| 4 | UI lifecycle, auth navigation, search race และโหลดข้อมูลเก่า | Widget tests ผ่าน Back/แตะนอก reaction/dialog/logout; unit test กันผลค้นหาเก่า; query test โหลดครบ 61 โพสต์ | ✅ |
| 5 | Platform configuration และตรวจรวม | Tests 25 รายการและ Emulator 6 suites ผ่านหลัง merge; ChatService/Chrome 6/6; analyzer ไม่มี findings; Android Debug ผ่าน; ข้อจำกัดบันทึกด้านล่าง | ✅ |

## แนวทางและขอบเขต

- ใช้ schema และบริการเดิม เพิ่ม field เฉพาะที่จำเป็นต่อการกู้การทำงานหรือป้องกันข้อมูลค้าง
- เพิ่ม regression tests จากข้อผิดพลาดที่ตรวจพบจริง รวมกรณีปฏิเสธสิทธิ์
- ทดสอบ Firebase ด้วย `demo-linko` ใน Emulator; การ deploy Rules จริงเป็นขั้นตอนภายนอกหลังตรวจผล
- ข้อมูลเก่าต้องอ่านได้อย่างปลอดภัย แม้ข้อมูลใหม่จะถูกตรวจชนิดอย่างเข้มงวด
- การเปลี่ยน privacy จำนวนมากใช้สถานะงานที่กู้ต่อได้ และจำกัดการมองเห็นอย่างปลอดภัยระหว่างเปลี่ยน
- งานที่ต้องมีค่าตั้งต้นภายนอก เช่น release keystore, App Check enforcement, Push และ Pages บันทึกแยกในผลสรุป

## ประวัติผลตรวจ

ผลจริง คำสั่ง และกลุ่มไฟล์ที่เปลี่ยนอยู่ใน [CHANGELOG_TESTING.md](CHANGELOG_TESTING.md#2026-10-22--แก้ผลตรวจระบบตามลำดับ)

## ขอบเขตที่ยังต้องทำต่อ

| งาน | สถานะ | สิ่งที่ต้องมี |
|---|---|---|
| Deploy Rules/ตรวจ indexes และทดสอบสองบัญชีจริง | ⟳ | ใช้โปรเจกต์ Firebase เป้าหมาย; ยังไม่ได้ deploy ในรอบนี้ |
| ทดสอบ Android บนโทรศัพท์จริง และ iOS/macOS | ⟳ | รอบนี้ตรวจ Android Debug compilation และ parse Apple config; ไม่มีผล runtime บน Mac/โทรศัพท์ |
| Android release signing | ⟳ | keystore และรหัสผ่านของเจ้าของแอป; ป้องกันการใช้ debug key สำหรับ release แล้ว |
| Flutter/AGP/Kotlin compatibility ในอนาคต | ⟳ | build ปัจจุบันผ่าน แต่ยังมี warning `android.newDsl=false` และ KGP จาก Firebase plugins; ต้องตรวจ migration ก่อนอัปเกรด major |
| งานแจ้งเตือนและ cleanup ที่ต้องทำแม้แอปถูกปิด | ⟳ | รอบนี้ทำซ้ำได้/รายงานส่งไม่ครบ แต่ยังทำจาก client; ขั้นถัดไปคือ backend queue และ retry |
| การโหลดข้อมูลจำนวนมาก | ⟳ | เพิ่มโหลดข้อมูลเก่าและลด listeners แล้ว; real-time window ยังโตตามจำนวนที่โหลด และ search ยังสแกนข้อความเป็นหน้า ไม่ใช่ full-text index |
| App Check / Push / Pages | ❌ | ยังไม่ได้เพิ่ม SDK, server และการตั้งค่าแพลตฟอร์ม; เป็นงานพัฒนาต่อ |

### ตั้งค่า Android release

1. ใช้ keystore ของเจ้าของแอป และคัดลอก `android/key.properties.example` เป็น `android/key.properties`
2. ใส่ `storeFile`, `storePassword`, `keyAlias`, `keyPassword` จริง โดย `storeFile` อ้างอิงจากโฟลเดอร์ `android/` หรือเป็น absolute path ที่ใช้ `/`
3. ไฟล์รหัสผ่านและ keystore ถูก ignore แล้ว ไม่ใส่ลง Git
4. ตรวจด้วย `cd android` และ `./gradlew.bat :app:validateReleaseKey` ก่อน build release

การทดสอบ `validateReleaseKey` ในรอบนี้ **ปฏิเสธเมื่อไม่มี key ตามที่ออกแบบไว้** จึงยังไม่มีผล signed release build

Windows แสดงข้อความเมื่อวิดีโอยังไม่รองรับ; Linux ยังไม่มี Firebase configuration ของโปรเจกต์ จึงยังไม่นับเป็นแพลตฟอร์มที่ใช้งานได้
