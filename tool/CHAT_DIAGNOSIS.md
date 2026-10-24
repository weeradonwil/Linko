# ผลตรวจปัญหาส่งแชท — 21 ตุลาคม 2026

> ประวัติจาก commit `1c60028`: ตาราง/เวลา deploy ด้านล่างเป็นผลของรุ่นวันที่ 21 ต.ค. ไม่ใช่หลักฐานว่า Rules หลังรวม audit วันที่ 22 ต.ค. ถูก deploy แล้ว สคริปต์เดิมเปลี่ยนชื่อเป็น `tool/chat_rules_diagnosis.mjs` และปรับ fixtures ให้ตรง schema/follow gate ปัจจุบัน ส่วนชุด regression audit อยู่ที่ `tool/chat_rules_emulator_test.mjs`

หลัง merge วันที่ 22 ต.ค. รันทดสอบใหม่แล้ว: ชุดวินิจฉัย Rules ปัจจุบัน 25/25 และ ChatService จริงกับ Chrome/Emulator 6/6 ผ่าน รายละเอียดรวมใน `CHANGELOG_TESTING.md` ไม่มีการ deploy production ในรอบ merge

## สถานะหลังแก้และเผยแพร่

แก้ `firestore.rules` จริงแล้ว โดยไม่บังคับให้ข้อความ ชนิดข้อความ และผู้ส่งล่าสุดต้องเปลี่ยนค่า แต่ยังตรวจข้อความใน batch, สมาชิก, ตัวตนผู้ส่ง, timestamp และ unreadCounts เดิม รวมถึงแก้เปิดห้องที่มองเห็นอยู่แล้วซ้ำและยกเลิกข้อความที่ preview เหมือนข้อความยกเลิก

หน้าแชทใช้ข้อความแยกตาม Firebase error code และบันทึก plugin/code กับ stack ใน debug Console โดยไม่บันทึกเนื้อหาแชท UID หรือ media path; permission-denied ไม่ชี้ว่าต้อง deploy เสมออีกต่อไป

| การยืนยันหลังแก้ | ผล |
|---|---|
| Rules จากไฟล์จริงใน Auth/Firestore Emulator | 25/25 ผ่าน |
| `ChatService` จริงบน Chrome กับ Emulator (หน้า Flutter release แยก) | 6/6 ผ่าน |
| Flutter tests เดิม | 7/7 ผ่าน |
| Analyzer ไฟล์ที่แก้และหน้า Flutter ทดสอบ | 0 errors, 0 warnings; 7 info lints เดิมในหน้าจอแชท |
| Firebase จริงสองบัญชีชั่วคราว ผ่าน REST ด้วย ID token ของแต่ละบัญชี | 10/10 ขั้นตอนผ่าน |
| Cleanup ของการทดสอบจริง | ลบเอกสาร 9 รายการ ตรวจว่าไม่เหลือ และลบบัญชีชั่วคราว 2 บัญชีแล้ว |

อ่าน Rules ที่เผยแพร่อยู่ก่อนแก้พบว่าตรงกับรุ่นที่มี bug จริง จึงยืนยันว่า deploy เดิมสำเร็จแล้ว แต่เงื่อนไขในไฟล์ผิด ไม่ใช่เพราะยังไม่ได้ deploy

เผยแพร่เฉพาะ Firestore Rules ไป `social-network-app-c22eb` สำเร็จเมื่อ **21 ต.ค. 2026 เวลา 11:40:31 น. (Asia/Bangkok)** และอ่านกลับจาก Rules API เพื่อตรวจเทียบกับไฟล์ที่ทดสอบ:

- Ruleset: `projects/social-network-app-c22eb/rulesets/a4db9032-e537-4cff-a03f-78b8bda0abbc`
- SHA-256 หลัง normalize line endings: `2f2cf695fc2a395810bbcc36dbf192a93f80fa692f21c3e8bb325f1da8fd04eb` ตรงกันทั้ง local และ published
- สำรอง Rules เดิม: `build/chat_diagnostics/published_before.rules`
- ผลยืนยัน release: `build/chat_diagnostics/published_after.json`
- ผล browser: `build/chat_diagnostics/chat_service_results.json`
- ผล Firebase จริงและ cleanup: `build/chat_diagnostics/live_results.json`

การทดสอบจริงครอบคลุมสร้างห้อง ส่งข้อความแรก ส่งต่อ ข้อความซ้ำ ผู้รับอ่านครบ ตอบกลับ ตัวนับอ่าน เปิดห้องซ้ำ ยกเลิกข้อความที่ preview เดิมเหมือนกัน และส่งหลังยกเลิก โดยใช้ IAM เฉพาะอ่าน release และล้างข้อมูลทดสอบ การส่ง/อ่านระหว่างบัญชีใช้ Firebase ID token ผ่าน Security Rules จริง

## การวินิจฉัยก่อนแก้

พบ regression ใน `firestore.rules` รุ่น `7f50d79` ทำให้ข้อความแรกส่งได้ แต่ข้อความถัดไปถูกปฏิเสธเมื่อชนิดข้อความหรือผู้ส่งเหมือนข้อความก่อนหน้า การ deploy ไฟล์เดิมซ้ำจะคงข้อผิดพลาดนี้ไว้

## หลักฐานช่วงวินิจฉัยก่อนแก้

ทดสอบด้วย Firebase Auth Emulator และ Firestore Emulator v1.22.0, Java 21 บนเครื่องนี้ ใช้ project `demo-linko` และผู้ใช้จำลองสามบัญชี ทุกคำขอข้อมูลวิ่งผ่าน localhost ไม่เรียกข้อมูล production และไม่มีการ deploy

ชุดทดสอบส่ง Firestore batch โดยใช้ fields และ server transforms ตรงกับ `ChatService.sendMessage`: สร้างข้อความและอัปเดตตัวอย่างห้อง, unreadCounts, lastReadAt และ hiddenFor ใน batch เดียวกัน รวมเคสสร้างห้องใหม่ผ่าน Rules แล้วส่งข้อความแรกและข้อความที่สองต่อกันจริง

| Rules / รูปแบบข้อมูลของ client | ผ่าน | ไม่ผ่าน |
|---|---:|---:|
| รุ่นที่มี bug (`7f50d79`) | 16/25 | 9 |
| รุ่นก่อน (`778fe86`) พร้อมรูปแบบข้อมูลของ service รุ่นนั้น | 16/16 | 0 |
| เปลี่ยนเฉพาะเงื่อนไขส่งข้อความ ทดลองใน Emulator | 23/25 | 2 |
| เปลี่ยนเงื่อนไขส่ง, เปิดห้องซ้ำ และยกเลิกข้อความเฉพาะใน Emulator | 25/25 | 0 |

จำนวนเคสของรุ่นก่อนน้อยกว่า เพราะไม่ทดสอบฟีเจอร์/ข้อจำกัดที่เพิ่มภายหลัง เช่น hiddenFor และการยกเลิกข้อความ รุ่นก่อนใช้ payload รุ่นก่อนด้วย โดยยังไม่มี lastMessageId และ hiddenFor

ตัวอย่างผลที่ยืนยัน regression:

| เหตุการณ์ | Rules ก่อนแก้ | เงื่อนไขทดลองใน Emulator |
|---|---|---|
| สร้างห้องใหม่และส่งข้อความแรก | HTTP 200 | HTTP 200 |
| ส่งข้อความที่สองในห้องเดียวกัน จากผู้ส่งเดิม | HTTP 403 PERMISSION_DENIED | HTTP 200 |
| ตอบกลับจากอีกบัญชีโดยยังเป็นข้อความชนิด text | HTTP 403 PERMISSION_DENIED | HTTP 200 |
| ส่งข้อความตัวอักษรเหมือนเดิมซ้ำ | HTTP 403 PERMISSION_DENIED | HTTP 200 |
| ส่งข้อความหลังยกเลิกข้อความล่าสุดของตัวเอง | HTTP 403 PERMISSION_DENIED | HTTP 200 |
| อ่าน/ส่งข้อความโดยบัญชีที่ไม่ได้อยู่ในห้อง | HTTP 403 (ถูกต้อง) | HTTP 403 (ถูกต้อง) |

ตรวจด้วยว่าข้อความจาก batch ที่ล้มเหลวไม่หลงเหลือในฐานข้อมูล และเมื่อส่งสำเร็จ unreadCounts ของผู้รับเพิ่มตามที่กำหนด เคสปฏิเสธยังครอบคลุมการปลอมผู้ส่ง, เปลี่ยนสมาชิกห้อง, แก้ lastReadAt ของอีกคน, ไม่เพิ่ม unreadCounts, อัปเดตตัวอย่างห้องโดยไม่มีข้อความ และข้อความยาวเกิน 2,000 ตัวอักษร

## สาเหตุที่ยืนยันได้

ใน `canUpdateForNewMessage()` ช่วงบรรทัด 328 มี:

```text
changed.hasAll([
  'lastMessageText', 'lastMessageType', 'lastMessageSenderId',
  'lastMessageAt', 'lastMessageId', 'unreadCounts', 'lastReadAt', 'updatedAt'
])
```

`changed` มาจาก `diff(resource.data).affectedKeys()` จึงนับเฉพาะ fields ที่ค่าเปลี่ยนจริง แม้ service เขียน `lastMessageType: 'text'` ในทุกครั้ง ถ้าค่าเดิมเป็น `text` field นี้จะไม่อยู่ใน changed และ hasAll จะเป็น false เช่นเดียวกับ lastMessageSenderId เมื่อคนเดิมส่งต่อ หรือ lastMessageText เมื่อส่งข้อความซ้ำ

Rules จึงปฏิเสธการอัปเดตเอกสารห้อง และเนื่องจากอยู่ใน batch เดียวกัน การสร้างข้อความจึงล้มเหลวไปด้วย

เงื่อนไขทดลองเอาสาม field ที่สามารถมีค่าเดิมออกจากรายการที่บังคับให้เปลี่ยน โดยยังตรวจค่าปลายทางกับข้อความที่อยู่ใน batch, ตัวตนผู้ส่ง, สมาชิกห้อง, timestamp และ unreadCounts เหมือนเดิม การเปลี่ยนเฉพาะจุดนี้ทำให้เคสส่งข้อความที่เคยล้มเหลวกลับมาผ่านทั้งหมด

พบเพิ่มเติมอีกสองเคสจากรูปแบบเดียวกัน:

- `canUpdateOwnHiddenStateOnly()` บังคับว่า hiddenFor ต้องเปลี่ยน: เปิดห้องที่ hiddenFor ของตัวเองเป็น false อยู่แล้วจึงล้มเหลว ทั้งที่ service เพียงเขียน false ซ้ำและ updatedAt
- `canUpdateForUnsentLatestMessage()` บังคับ lastMessageText ต้องเปลี่ยน: ถ้าข้อความเดิมเป็นคำว่า `ยกเลิกข้อความนี้` อยู่แล้ว จะยกเลิกข้อความล่าสุดไม่ได้

## ข้อความแจ้งเตือนทำให้วินิจฉัยคลาดเคลื่อน

`lib/screens/chat/chat_room.dart` ช่วงบรรทัด 176–183 จับข้อผิดพลาดแล้วแทนด้วย `ส่งข้อความไม่สำเร็จ ตรวจการเชื่อมต่อและ Firebase Rules` โดยไม่ได้แสดงหรือบันทึกรหัส FirebaseException จึงใช้ SnackBar นี้แยก network error ออกจาก permission-denied ไม่ได้

error CORS ของ Storage และ QUIC ของ Chrome ที่เคยเห็นอาจเกิดร่วมกัน แต่ไม่จำเป็นต่อการทำให้ regression นี้เกิดซ้ำ: เคสทดสอบข้อความตัวอักษรล้มเหลวใน localhost โดยไม่มี Storage หรือ QUIC

## ไฟล์และการรันซ้ำ

- ชุดทดสอบ: `tool/chat_rules_diagnosis.mjs`
- ผล JSON รอบล่าสุด: `build/chat_diagnostics/results.json`
- log การรัน: `build/chat_diagnostics/run.log`
- Rules ที่ทดสอบมี Git blob hash `0fc5d8e7d0bb96d18f31eab0fe6272239eade98a` ตรงกับรุ่นที่ตรวจวันที่ 21 ต.ค.

ต้องมี Java 21 ใน PATH และ Firebase CLI จากนั้นรันจากโฟลเดอร์ Linko:

```powershell
firebase.cmd --config firebase.emulator.test.json emulators:exec --only auth,firestore --project demo-linko "node tool/chat_rules_diagnosis.mjs --diagnose"
```

โหมด `--diagnose` ทดสอบรุ่นที่มี bug (`7f50d79`), รุ่นก่อน (`778fe86` พร้อม payload รุ่นนั้น) และไฟล์ Rules ปัจจุบันตามลำดับ โดยคืน Rules ปัจจุบันให้ Emulator เมื่อจบ Exit code อ้างอิงไฟล์ปัจจุบัน ต้องดูผลแต่ละ suite เพื่อเห็น regression ของรุ่นเก่า เมื่อไม่ใส่ `--diagnose` จะทดสอบเฉพาะ Rules ปัจจุบันและคืน exit code 1 เฉพาะเมื่อพบเคสไม่ผ่าน

รันการทดสอบผ่าน `ChatService` จริง (ต้องมี Java 21, Flutter และกำหนด `CHROME_EXECUTABLE` ให้ชี้ Chrome):

```powershell
firebase.cmd --config firebase.emulator.test.json emulators:exec --only auth,firestore --project demo-linko "node tool/chat_rules_diagnosis.mjs && node tool/run_chat_service_smoke.mjs"
```

ตัวรัน browser เปิดหน้า Flutter `tool/chat_service_smoke.dart` และ Chrome แยกที่พอร์ต 18090/18091 แล้วปิด process ของตัวเองเมื่อจบ ไม่ใช้ session Chrome ของผู้ใช้ ใช้หน้า Flutter release เพื่อหลีกเลี่ยงปัญหา path ของ Flutter web test runner บน Windows

หาก Flutter SDK ไม่อยู่ใน PATH สามารถตั้ง `$env:LINKO_FLUTTER_SDK` เป็นโฟลเดอร์ SDK (เช่น `C:\Users\Admin\flutter`) ตัวรันจะเรียก Dart/Flutter tool จาก SDK นั้นโดยตรง ตั้ง `$env:CHROME_EXECUTABLE` เป็น path ของ Chrome ก่อนรันตามตัวอย่างด้านบน

ช่วงวินิจฉัยก่อนผู้ใช้อนุมัติยังไม่ได้แก้ source หรือ deploy; หลังผู้ใช้อนุมัติจึงแก้และเผยแพร่ตามสถานะด้านบน ไฟล์ generated plugin ที่เปลี่ยนอยู่ก่อนเริ่มงานไม่ได้แก้ไข

ข้อจำกัด: ทดสอบข้อความตัวอักษร, metadata ข้อความสื่อ, สิทธิ์ห้อง และการอ่าน/ยกเลิกข้อความแล้ว แต่ยังไม่ได้ทดสอบ upload/download ไฟล์แนบจริงหรือกด UI ใน Chrome session เดิมของผู้ใช้หลังแก้
