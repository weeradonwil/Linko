# Linko Firestore and Storage Schema

เอกสารนี้สรุป path ที่แอปใช้อยู่ ให้ตรวจ `firestore.rules` และ `storage.rules` ประกอบก่อนเปลี่ยนข้อมูลหรือสิทธิ์

## Collections หลัก

### `users/{uid}`

- `uid`, `displayName`, `displayNameLower`, `bio`, `isPrivate`, `createdAt`; อาจมี `avatarPath`
- เจ้าของแก้ชื่อ, Bio, รูปโปรไฟล์ และสถานะส่วนตัวได้
- รูปโปรไฟล์เก็บที่ `profile_images/{uid}/{fileName}`; ผู้ใช้ที่ล็อกอินอ่านได้ เจ้าของเท่านั้นที่เขียน/ลบได้

### `posts/{postId}`

- `userId`, `authorName`, `content`, `tags`, `visibility`, `authorIsPrivate`, `createdAt`, `updatedAt`, `mediaType`
- อาจมี `editedAt`, `mediaPath`, `thumbnailPath`
- `visibility`: `public`, `followers` หรือ `private`; การอ่านโพสต์ผู้ติดตามต้องมีเอกสารอนุมัติใน `users/{ownerUid}/followers/{viewerUid}`
- สื่อเก็บที่ `post_media/{ownerUid}/{postId}/{fileName}`; ภาพปกวิดีโออาจอยู่ในโฟลเดอร์เดียวกัน

### `post_reports/{reportId}`

- `postId`, `postOwnerId`, `reporterUid`, `reason`, `details`, `status`, `createdAt`
- หลังตรวจสอบอาจมี `reviewedBy`, `reviewedAt`; สถานะที่หน้าผู้ดูแลใช้คือ `open`, `resolved`, `dismissed`, `removed`
- ID รายงานมีรูปแบบ `{postId}_{reporterUid}`; การลบโพสต์จากรายงานต้องใช้บัญชีที่มี custom claim `admin: true`

### `groups/{groupId}` และโพสต์ในกลุ่ม

- กลุ่ม: `name`, `description`, `ownerId`, `visibility`, `memberCount`, `createdAt`, `updatedAt`; อาจมี `avatarPath`
- `groups/{groupId}/posts/{postId}`: `authorId`, `authorName`, `content`, `createdAt`, `mediaType`; อาจมี `mediaPath`, `thumbnailPath`
- สมาชิกเก็บใน `groups/{groupId}/members/{uid}`; `memberCount` เปลี่ยนพร้อมการเพิ่ม/ลบสมาชิก
- คำขอกลุ่มส่วนตัวเก็บใน `groups/{groupId}/join_requests/{requesterUid}` โดยมี `uid`, `displayName`, `createdAt`; เจ้าของหรือผู้ดูแลที่มี `admin: true` อนุมัติ/ปฏิเสธได้
- reaction อยู่ที่ `groups/{groupId}/posts/{postId}/reactions/{uid}` เป็น `like` หรือ `dislike`
- รูปประจำกลุ่มเก็บที่ `group_images/{groupId}/{ownerUid}/{fileName}`; เจ้าของกลุ่มเป็นผู้เปลี่ยนรูป
- สื่อโพสต์เก็บที่ `group_media/{groupId}/{postId}/{ownerUid}/{fileName}`; สมาชิกในกลุ่มอ่านได้

### `conversations/{conversationId}`

- `participantIds`, `participantNames`, `unreadCounts`, `lastReadAt`, `createdAt`, `updatedAt`; อาจมี `hiddenFor`
- ข้อมูลสรุปข้อความล่าสุด: `lastMessageText`, `lastMessageType`, `lastMessageSenderId`, `lastMessageAt`, `lastMessageId`
- ข้อความอยู่ใน `conversations/{conversationId}/messages/{messageId}`: `senderId`, `type`, `text`, `createdAt`; อาจมี `mediaPath`
- ยกเลิกข้อความโดยเปลี่ยนเป็น `type: deleted`; ซ่อนห้องเป็นสถานะเฉพาะผู้ใช้ ไม่ลบข้อความของอีกฝ่าย
- ไฟล์แนบอยู่ใน `chat_media/{conversationId}/{senderUid}/{fileName}`

### `notifications/{notificationId}`

- `recipientId`, `actorId`, `actorName`, `type`, `body`, `isRead`, `createdAt`
- Like Notification มี `postId` และส่งให้เจ้าของโพสต์; Comment Notification มี `postId`/`commentId` และส่งให้ผู้ติดตามเจ้าของโพสต์; Follow Notification แจ้งบัญชีที่ถูกติดตาม

## Subcollections

### Follow และคำขอติดตาม

- `users/{profileUid}/followers/{followerUid}` และ `users/{followerUid}/following/{profileUid}` เก็บความสัมพันธ์ที่ได้รับอนุมัติ
- `users/{profileUid}/follow_requests/{requesterUid}` เก็บคำขอที่รอเจ้าของอนุมัติ; ผู้รับคำขออนุมัติหรือปฏิเสธได้

### Reactions และ Comments

- `posts/{postId}/reactions/{uid}`: `uid`, `reaction`, `updatedAt`; reaction คือ `like` หรือ `dislike`
- `posts/{postId}/comments/{commentId}`: `authorId`, `authorName`, `content`, `createdAt`

## ข้อจำกัดการอัปโหลด

- รูปภาพไม่เกิน 10 MiB; วิดีโอไม่เกิน 50 MiB
- Rules ใน working tree มีการเปลี่ยนหลัง deploy ครั้งก่อน ต้อง deploy และทดสอบสิทธิ์บนโปรเจกต์ Firebase เป้าหมายก่อนใช้งานจริง
