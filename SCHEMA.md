# Linko Firestore and Storage Schema

เอกสารนี้สรุป path ที่แอปใช้อยู่ ให้ตรวจ `firestore.rules` และ `storage.rules` ประกอบก่อนเปลี่ยนข้อมูลหรือสิทธิ์

## Collections หลัก

### `users/{uid}`

- `uid`, `displayName`, `displayNameLower`, `bio`, `isPrivate`, `createdAt`; อาจมี `avatarPath`
- เจ้าของแก้ชื่อ, Bio, รูปโปรไฟล์ และสถานะส่วนตัวได้
- `privacyTarget` เป็น boolean ชั่วคราวของงานเปลี่ยน audience; โพสต์ใหม่ใช้ target ทันที งานอ่านโพสต์เป็นหน้า ๆ ละ 200 และทำ transaction ต่อเอกสารโดยขนานสูงสุด 8 งาน การเปลี่ยนเป็นส่วนตัวจะตั้ง `isPrivate: true` หลังปรับโพสต์ครบ แล้วลบ target ทิ้ง หากงานหยุดสามารถทำต่อได้
- AuthGate ตรวจและเติมฟิลด์โปรไฟล์ที่ขาดก่อนเปิด Home; Rules ตรวจชนิดข้อมูลและเจ้าของ UID
- รูปโปรไฟล์เก็บที่ `profile_images/{uid}/{fileName}`; ผู้ใช้ที่ล็อกอินอ่านได้ เจ้าของเท่านั้นที่เขียน/ลบได้

### `posts/{postId}`

- `userId`, `authorName`, `content`, `tags`, `visibility`, `authorIsPrivate`, `createdAt`, `updatedAt`, `mediaType`
- อาจมี `editedAt`, `mediaPath`, `thumbnailPath`
- `tags` เป็นรายการ string ไม่เกิน 5 รายการ; โพสต์ต้องมีข้อความหรือสื่อแนบ
- `isDeleting: true` ปิดการแก้โพสต์/เพิ่มความคิดเห็นและ reaction ระหว่างลบ สื่อตามด้วย comments/reactions ถูกลบก่อนเอกสารแม่ เจ้าของสามารถลองลบต่อหากเครือข่ายขัดข้อง
- `visibility`: `public`, `followers` หรือ `private`; การอ่านโพสต์ผู้ติดตามต้องมีเอกสารอนุมัติใน `users/{ownerUid}/followers/{viewerUid}`
- สื่อเก็บที่ `post_media/{ownerUid}/{postId}/{fileName}`; ภาพปกวิดีโออาจอยู่ในโฟลเดอร์เดียวกัน

### `post_reports/{reportId}`

- `postId`, `postOwnerId`, `reporterUid`, `reason`, `details`, `status`, `createdAt`
- หลังตรวจสอบอาจมี `reviewedBy`, `reviewedAt`; สถานะที่หน้าผู้ดูแลใช้คือ `open`, `resolved`, `dismissed`, `removed`
- ID รายงานมีรูปแบบ `{postId}_{reporterUid}`; การลบโพสต์จากรายงานต้องใช้บัญชีที่มี custom claim `admin: true`

### `groups/{groupId}` และโพสต์ในกลุ่ม

- กลุ่ม: `name`, `description`, `ownerId`, `visibility`, `memberCount`, `createdAt`, `updatedAt`; อาจมี `avatarPath`
- `isDeleting: true` ปิดการเพิ่มสมาชิก คำขอ โพสต์ reaction และรูปกลุ่มระหว่างลบ; เจ้าของลบสื่อของสมาชิกเพื่อ cleanup ได้
- `groups/{groupId}/posts/{postId}`: `authorId`, `authorName`, `content`, `createdAt`, `mediaType`; อาจมี `mediaPath`, `thumbnailPath`
- สมาชิกเก็บใน `groups/{groupId}/members/{uid}`; `memberCount` เปลี่ยนพร้อมการเพิ่ม/ลบสมาชิก
- คำขอกลุ่มส่วนตัวเก็บใน `groups/{groupId}/join_requests/{requesterUid}` โดยมี `uid`, `displayName`, `createdAt`; เจ้าของหรือผู้ดูแลที่มี `admin: true` อนุมัติ/ปฏิเสธได้
- reaction อยู่ที่ `groups/{groupId}/posts/{postId}/reactions/{uid}` เป็น `like`, `love`, `haha`, `wow`, `sad`, `angry` หรือ `dislike`
- รูปประจำกลุ่มเก็บที่ `group_images/{groupId}/{ownerUid}/{fileName}`; เจ้าของกลุ่มเป็นผู้เปลี่ยนรูป
- สื่อโพสต์เก็บที่ `group_media/{groupId}/{postId}/{ownerUid}/{fileName}`; สมาชิกในกลุ่มอ่านได้

### `conversations/{conversationId}`

- `participantIds`, `participantNames`, `unreadCounts`, `lastReadAt`, `createdAt`, `updatedAt`; อาจมี `hiddenFor`
- ข้อมูลสรุปข้อความล่าสุด: `lastMessageText`, `lastMessageType`, `lastMessageSenderId`, `lastMessageAt`, `lastMessageId`
- ข้อความอยู่ใน `conversations/{conversationId}/messages/{messageId}`: `senderId`, `type`, `text`, `createdAt`; อาจมี `mediaPath`
- ยกเลิกข้อความโดยเปลี่ยนเป็น `type: deleted`; ซ่อนห้องเป็นสถานะเฉพาะผู้ใช้ ไม่ลบข้อความของอีกฝ่าย
- การสร้างห้องใหม่ต้องมี approved follow จากผู้เริ่มถึงผู้รับ; ห้องเดิมยังสนทนาต่อได้ การส่งข้อความต้องเขียนข้อความและ summary ในชุดเดียวกัน และตั้ง `hiddenFor` ของทั้งสองฝ่ายเป็น false เพื่อให้ข้อความใหม่แสดงห้องอีกครั้ง
- `unreadCounts` ของห้องใหม่ต้องเป็นเลขศูนย์แยกตามผู้ร่วมสนทนา; ค่าที่ไม่ใช่ตัวเลขในเอกสารเก่ารองรับการกลับมา increment เป็น 1 เมื่อมีข้อความใหม่
- ไฟล์แนบอยู่ใน `chat_media/{conversationId}/{senderUid}/{fileName}`

### `notifications/{notificationId}`

- `recipientId`, `actorId`, `actorName`, `type`, `body`, `isRead`, `createdAt`
- Like Notification มี `postId` และส่งให้เจ้าของโพสต์; Comment Notification มี `postId`/`commentId` และส่งให้ผู้ติดตามเจ้าของโพสต์; Follow Notification แจ้งบัญชีที่ถูกติดตาม
- Comment ถูกบันทึกก่อนการแจ้งเตือน แต่ละ notification เขียนแยกคำขอโดยขนานไม่เกิน 8 เพื่อไม่ใช้ Rules access-call budget ของ batch เดียวร่วมกัน ผู้ใช้จะเห็นผลส่งไม่ครบตามจริง

## Subcollections

### Follow และคำขอติดตาม

- `users/{profileUid}/followers/{followerUid}` และ `users/{followerUid}/following/{profileUid}` เก็บความสัมพันธ์ที่ได้รับอนุมัติ
- `users/{profileUid}/follow_requests/{requesterUid}` เก็บคำขอที่รอเจ้าของอนุมัติ; ผู้รับคำขออนุมัติหรือปฏิเสธได้

### Reactions และ Comments

- `posts/{postId}/reactions/{uid}`: `uid`, `reaction`, `updatedAt`; รองรับ 7 ค่าเดียวกับโพสต์ในกลุ่ม
- `posts/{postId}/comments/{commentId}`: `authorId`, `authorName`, `content`, `createdAt`

## ส่วนเพิ่มเติมรอบ 24 ตุลาคม 2026

- `groups/{groupId}/posts/{postId}` เพิ่ม `tags`, `updatedAt`, `editedAt` และ `isDeleting` โดยเอกสารรุ่นเก่าที่ไม่มีฟิลด์เหล่านี้ยังอ่านได้
- `groups/{groupId}/posts/{postId}/comments/{commentId}` ใช้ `authorId`, `authorName`, `content`, `createdAt` เหมือนความคิดเห็นฟีดหลัก; อ่าน/เขียนได้ตามสิทธิ์สมาชิกกลุ่ม
- `post_reports` ของกลุ่มเพิ่ม `groupId` และใช้ ID `group_{groupId}_{postId}_{reporterUid}`; ผู้ดูแลใช้คิวกลางเดียวกันกับรายงานฟีดหลัก
- `notifications` ของกลุ่มเพิ่ม `groupId`; Like/Comment แจ้งเจ้าของโพสต์ที่ยังอยู่ในกลุ่ม และเปิดกลับไปยังความคิดเห็นของโพสต์กลุ่ม
- การลบโพสต์กลุ่มตั้ง `isDeleting` ก่อนปิดการเขียน Comment/Reaction แล้วลบสื่อและข้อมูลย่อยทีละหน้า สามารถกดลบต่อเมื่อเน็ตขาดระหว่างงานได้
- การค้นหาสมาชิกมี document cursor รวมข้อมูลเก่าที่ไม่มีฟิลด์สำหรับ index; ปุ่มค้นต่อไล่ได้ทุกหน้า
- การแจ้งเตือนเริ่ม 100 รายการและขยายช่วงได้ครั้งละ 100
- วิดีโออ่านผ่าน Firebase SDK โดยตรง แล้วสร้างไฟล์ชั่วคราวบนมือถือหรือ Blob URL บนเว็บ; ล้างทรัพยากรเมื่อปิดตัวเล่น

## ข้อจำกัดการอัปโหลดปัจจุบัน

- รูปภาพไม่เกิน 10 MiB; วิดีโอไม่เกิน 50 MiB
- รูปโปรไฟล์และรูปประจำกลุ่มไม่เกิน 5 MiB
- Rules ใน working tree มีการเปลี่ยนหลัง deploy ครั้งก่อน ต้อง deploy และทดสอบสิทธิ์บนโปรเจกต์ Firebase เป้าหมายก่อนใช้งานจริง

## การโหลดรายการ

- Feed เริ่ม 30 โพสต์และขยายครั้งละ 30; ทุก source เรียง `createdAt` จากใหม่ไปเก่า รวมผู้ติดตามครั้งละ 5 UID ต่อ listener และยกเลิก listener เก่าเมื่อรายชื่อเปลี่ยน
- Profile/Group posts เริ่ม 30, Chat/Comments เริ่ม 50 และเพิ่มเมื่อกดโหลดก่อนหน้า โดยขยายหน้าต่าง real-time query
- Explore/Search โพสต์ใช้ document cursor; ค้นในโพสต์สาธารณะเป็นหน้า ๆ ละ 80 เอกสาร และกดค้นต่อในข้อมูลเก่าได้ แท็กยอดนิยมยังคำนวณจาก 100 โพสต์ล่าสุด
- ระบบค้นหานี้ยังไม่ใช่ full-text search index และ real-time windows มีค่าอ่าน/หน่วยความจำเพิ่มเมื่อโหลดข้อมูลมากขึ้น
