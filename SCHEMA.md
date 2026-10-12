Schema มี 14 collections ใช้เก็บข้อมูล
Collection หลัก 6 ตัว
- users — ข้อมูลโปรไฟล์สมาชิก
- posts — โพสต์ในฟีด
- post_reports — รายงานโพสต์
- groups — ข้อมูลกลุ่มและเพจ
- conversations — ห้องสนทนา 1-1
- usernames — ป้องกันชื่อผู้ใช้ซ้ำ
Collection ย่อย 8 ตัว
- following — รายชื่อบัญชีที่ผู้ใช้ติดตาม
- followers — รายชื่อผู้ติดตามของผู้ใช้
- follow_requests — คำขอติดตามที่รออนุมัติ
- notifications — การแจ้งเตือนของผู้ใช้
- reactions — like, dislike หรือ emoji บนโพสต์
- comments — ความคิดเห็นใต้โพสต์
- members — สมาชิกและบทบาทในกลุ่ม
- messages — ข้อความในห้องสนทนา
ก่อนเพิ่ม Week 4 โค้ดใช้ users, posts และ post_reports ส่วนรายการอื่นเป็น schema ที่วางแผนไว้; สถานะข้อมูลจริงใน Firebase Console ตรวจจากไฟล์เหล่านี้ไม่ได้

## Week 4 — ที่เพิ่มในซอร์สโค้ด
- `conversations/{conversationId}` — ผู้เข้าร่วมสองคน, ชื่อที่แสดง, ตัวนับข้อความที่ยังไม่อ่าน, เวลาอ่านข้อความล่าสุด และข้อมูลสรุปข้อความล่าสุด
- `conversations/{conversationId}/messages/{messageId}` — senderId, type (`text`/`image`/`video`), text, createdAt และ mediaPath เมื่อมีไฟล์แนบ
- `notifications/{notificationId}` — recipientId, actorId, actorName, type (`message`), body, conversationId, isRead และ createdAt
- ไฟล์แนบแชทใช้ Storage path `chat_media/{conversationId}/{senderUid}/{fileName}`; ไฟล์ภาพจำกัด 10 MB และวิดีโอ 50 MB
- `users` เพิ่ม `displayNameLower` สำหรับค้นหาชื่อ; ผู้ใช้เดิมที่ยังไม่มี field นี้ใช้ fallback ค้นหาในสมาชิก 150 รายล่าสุด
- ค้นหาโพสต์จากโพสต์สาธารณะ 80 รายการล่าสุด และคำนวณแท็กยอดนิยมจาก 100 รายการล่าสุด เพื่อให้เหมาะกับขอบเขตเดโม
