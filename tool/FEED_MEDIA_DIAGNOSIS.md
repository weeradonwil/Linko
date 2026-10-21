# ผลตรวจรูปภาพในฟีด — 21 ตุลาคม 2026

## สถานะ

ตั้ง CORS จาก `storage.cors.json` บน bucket จริงแล้ว หลังผู้ใช้อนุมัติเมื่อ 21 ตุลาคม 2026 เวลา **13:33:29 น. (Asia/Bangkok)** และทดสอบรูปเดิมด้วย Chrome ผ่านแล้ว

ภาพในโพสต์ตามที่ผู้ใช้ส่งมามีไฟล์อยู่จริง ขนาด 3,302,621 ไบต์ เป็น JPEG ที่ถอดรหัสได้ขนาด 7680 × 4324 พิกเซล ข้อมูลโพสต์ระบุ `mediaType: image`, `visibility: public` และ `authorIsPrivate: false` ถูกต้อง

## ผลยืนยันหลังแก้

| การตรวจ | ผล |
|---|---|
| อ่านค่า CORS กลับจาก bucket จริง | ตรงกับ `storage.cors.json`; metageneration จาก 4 เป็น 5 |
| ดาวน์โหลดรูปเดิมจาก Firebase พร้อม Origin ของ localhost | HTTP 200 และ `Access-Control-Allow-Origin: *` |
| ตรวจไบต์ไฟล์ | ครบ 3,302,621 ไบต์ และ MD5 ตรงกับ metadata ของไฟล์ |
| Chrome: `fetch()` อ่านไบต์จาก URL รูปจริง | ผ่าน HTTP 200 ได้ครบ 3,302,621 ไบต์ |
| Chrome: ถอดรหัสรูปจริง | ผ่าน ขนาด 7680 × 4324 พิกเซล |
| Storage Rules, IAM configuration และ ACL | ตรวจหลังตั้งค่าแล้วเหมือนก่อนเปลี่ยน CORS |

ผล Chrome ตรวจเมื่อ 13:34:18 น. (Asia/Bangkok) โดยใช้เบราว์เซอร์และโปรไฟล์ทดสอบแยก จากนั้นปิดและลบโปรไฟล์ทดสอบแล้ว หลักฐานหลังแก้อยู่ใน `build/chat_diagnostics/storage_cors_apply.json` และ `build/chat_diagnostics/feed_browser_after.json`; ค่าเดิมสำรองไว้ที่ `build/chat_diagnostics/storage_cors_before.json`

รอบนี้ทดสอบเส้นทางดาวน์โหลดและการถอดรหัสรูปจริงใน Chrome ยังไม่ได้รันหน้าฟีด Flutter ภายใต้เซสชันบัญชีผู้ใช้หรือ Android Emulator หลังเปลี่ยนค่า หากหน้าจอยังค้างไอคอนเดิม ให้รีเฟรชฟีดหรือลองโหลดรูปใหม่

## สาเหตุที่ยืนยันก่อนแก้

`PostMedia` ใน `lib/core/widgets/post_media.dart` เรียก `FirebaseStorage.ref(path).getData()` เพื่ออ่านไบต์ก่อนส่งให้ `Image.memory()` แต่ก่อนแก้ bucket `social-network-app-c22eb.firebasestorage.app` มี CORS configuration ว่าง (`cors: []`)

สำหรับแพ็กเกจ `firebase_storage_web` รุ่นที่ติดตั้ง `getData()` ตรวจ metadata/ขนาด เรียก `getDownloadURL()` แล้วอ่านไบต์ด้วย HTTP ฝั่งเบราว์เซอร์ คำตอบดาวน์โหลดรูปจริงคืน HTTP 200 และไบต์ครบ แต่ไม่มี `Access-Control-Allow-Origin` เบราว์เซอร์จึงไม่ยอมให้โค้ดอ่านไบต์

หน้าแอปรวมข้อผิดพลาดทั้งหมดไว้เป็นไอคอน `broken_image_outlined` พร้อมปุ่มลองใหม่ จึงไม่บอกสาเหตุแก่ผู้ใช้

Firebase ระบุว่าการดาวน์โหลดข้อมูลในเบราว์เซอร์โดยตรงต้องตั้งค่า CORS: [Download files on Web](https://firebase.google.com/docs/storage/web/download-files#cors_configuration)

## ผลทดสอบช่วงวินิจฉัยก่อนแก้

| การตรวจ | ผล |
|---|---|
| อ่านข้อมูลโพสต์และ metadata ไฟล์ด้วยสิทธิ์ผู้ดูแล | พบไฟล์ JPEG ขนาด 3,302,621 ไบต์ |
| อ่านการตั้งค่า bucket | CORS ว่าง |
| ดาวน์โหลดไฟล์จริงพร้อม Origin แบบ localhost | HTTP 200, ไบต์ครบ, ไม่มี `Access-Control-Allow-Origin` |
| Chrome: `fetch()` อ่านไบต์จาก URL ไฟล์จริง | ไม่ผ่าน: `TypeError` จากการบล็อกข้าม origin |
| Chrome: โหลด URL เดียวกันผ่าน HTML image element | ผ่าน ถอดรหัสภาพได้ ยืนยันว่าไฟล์ไม่เสีย; วิธีนี้มีข้อกำหนด CORS ต่างจากการอ่านไบต์ |
| Chrome: `fetch()` ไบต์เดียวกันผ่าน local server อีก origin ที่ส่ง CORS header | ผ่าน ได้ครบ 3,302,621 ไบต์ |
| สิทธิ์ Storage service agent สำหรับตรวจ Firestore | มี `roles/firebaserules.firestoreServiceAgent` แล้ว |
| เทียบ Storage Rules ที่เผยแพร่กับในเครื่อง | เงื่อนไขสื่อโพสต์เหมือนกัน; ส่วนที่ต่างเป็นรูปประจำกลุ่ม ไม่ใช่สาเหตุของโพสต์นี้ |

การเทียบแบบมี CORS ในช่วงวินิจฉัยใช้ local server จำลอง header เท่านั้น ผลหลังตั้งค่า bucket จริงอยู่ในตารางด้านบน

หลักฐานก่อนแก้อยู่ใน `build/chat_diagnostics/feed_readonly.json` และ `build/chat_diagnostics/feed_browser_results.json` สคริปต์ตรวจสอบอยู่ในโฟลเดอร์เดียวกัน การตรวจช่วงแรกไม่ได้แก้ข้อมูลหรือการตั้งค่าของ Firebase

## การตั้งค่าที่ใช้แก้

ใช้ [`storage.cors.json`](../storage.cors.json) ตั้ง CORS ของ bucket เป้าหมาย:

- `origin: ["*"]`: รองรับ origin ของเว็บ รวม localhost ที่ Flutter เปลี่ยน port ในแต่ละครั้ง ตามตัวอย่างการตั้งค่าในเอกสาร Firebase
- `method: ["GET", "HEAD"]`: อนุญาตเฉพาะการอ่านข้าม origin สำหรับสื่อ ไม่เพิ่มวิธีเขียนหรือลบไฟล์
- `responseHeader`: ให้เบราว์เซอร์อ่านชนิดและขนาดไฟล์
- `maxAgeSeconds: 3600`: เก็บผลตรวจ CORS ได้หนึ่งชั่วโมง

CORS กำหนดการอ่านข้าม origin ของเบราว์เซอร์ ไม่ได้เปลี่ยน Firebase Authentication หรือเงื่อนไข Security Rules

หากติดตั้ง Google Cloud CLI ไว้แล้ว ใช้คำสั่งจากโฟลเดอร์โปรเจกต์:

```powershell
gcloud storage buckets update gs://social-network-app-c22eb.firebasestorage.app --cors-file=storage.cors.json
```

อีกทางหนึ่งคือ Cloud Console → Storage → bucket นี้ → Configuration → Cross-origin resource sharing โดยใส่ค่าเดียวกับไฟล์ ต้องบันทึกทั้ง configuration และหน้าตั้งค่าให้เสร็จ

งานนี้อ่าน configuration กลับ ตรวจ header และทดสอบ Chrome หลังตั้งค่าแล้ว ผลผ่านตามตารางด้านบน ขั้นตอนเดิมใช้ตรวจซ้ำได้หากมีการเปลี่ยน bucket หรือแก้ CORS ในอนาคต
