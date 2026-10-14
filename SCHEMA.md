# Linko Firestore Schema

เอกสารนี้อธิบาย path ที่แอปอ่าน/เขียนอยู่ในปัจจุบัน ให้ตรวจ `firestore.rules` ประกอบก่อนเปลี่ยนฟิลด์หรือสิทธิ์

## Collections หลัก

### `users/{uid}`

- `uid`, `displayName`, `displayNameLower`, `isPrivate`, `createdAt`
- เจ้าของแก้ชื่อที่แสดงและค่า `isPrivate` ได้; อีเมลล็อกอินอยู่ใน Firebase Authentication ไม่ได้เก็บในเอกสารนี้

### `posts/{postId}`

- `userId`, `authorName`, `content`, `tags`, `visibility`, `createdAt`, `updatedAt`, `editedAt`, `mediaType`, `mediaPath`
- `editedAt` มีเมื่อผู้เขียนแก้โพสต์; `mediaPath` มีเมื่อแนบรูปหรือวิดีโอ

### `groups/{groupId}`

- `name`, `description`, `ownerId`, `visibility`, `createdAt`, `updatedAt`
- โค้ดหน้าจอสร้างกลุ่มเป็นกลุ่มสาธารณะ; เจ้าของแก้ชื่อ/คำอธิบายและลบกลุ่มได้

### `conversations/{conversationId}`

- `participantIds`, `participantNames`, `unreadCounts`, `lastReadAt`, `createdAt`, `updatedAt`
- `lastMessageText`, `lastMessageType`, `lastMessageSenderId`, `lastMessageAt` เพิ่มเมื่อมีข้อความ

### `notifications/{notificationId}`

- `recipientId`, `actorId`, `actorName`, `type`, `body`, `isRead`, `createdAt`
- Comment เพิ่ม `postId` และ `commentId`; ID ใช้รูปแบบ `comment_{commentId}_{recipientUid}` เพื่อป้องกันรายการซ้ำ

### `post_reports/{reportId}`

- `postId`, `postOwnerId`, `reporterUid`, `reason`, `details`, `status`, `createdAt`
- หนึ่งผู้ใช้ส่งรายงานได้หนึ่งรายการต่อโพสต์ตาม ID `{postId}_{reporterUid}`

## Subcollections

### ความสัมพันธ์ติดตาม

- `users/{profileUid}/followers/{followerUid}`: `uid` ของผู้ติดตามและ `createdAt`
- `users/{followerUid}/following/{profileUid}`: `uid` ของโปรไฟล์ที่ติดตามและ `createdAt`
- FollowService เขียน/ลบสอง path นี้ด้วย batch เดียวเพื่อรักษาความสอดคล้อง

### Reaction และ Comment

- `posts/{postId}/reactions/{uid}`: `uid`, `reaction`, `updatedAt`; หนึ่งผู้ใช้เลือกได้หนึ่งค่า (`like`, `love`, `haha`, `wow`, `sad`, `angry`)
- `posts/{postId}/comments/{commentId}`: `authorId`, `authorName`, `content`, `createdAt`
- เมื่อมี Comment ในโพสต์สาธารณะ ระบบส่ง notification เฉพาะสมาชิกใน `users/{postOwnerUid}/followers`; ผู้แสดงความคิดเห็นจะไม่ได้แจ้งเตือนตัวเอง

### กลุ่ม

- `groups/{groupId}/members/{uid}`: `uid`, `displayName`, `createdAt`
- `groups/{groupId}/posts/{groupPostId}`: `authorId`, `authorName`, `content`, `createdAt`
- สมาชิกอ่าน/เขียนโพสต์ในกลุ่มได้; เจ้าของกลุ่มลบโพสต์และเอกสารย่อยเมื่อลบกลุ่มได้

### แชท

- `conversations/{conversationId}/messages/{messageId}`: `senderId`, `type`, `text`, `createdAt`, `mediaPath` เมื่อเป็นไฟล์แนบ
- ไฟล์แนบเก็บใน Storage ที่ `chat_media/{conversationId}/{senderUid}/{fileName}`; ภาพไม่เกิน 10 MiB และวิดีโอไม่เกิน 50 MiB

## หมายเหตุ

- ผู้ใช้ยืนยัน Deploy Rules และ Indexes รุ่นปัจจุบันไปยัง `social-network-app-c22eb` แล้ว; หลังเปลี่ยนไฟล์ Rules/Indexes อีกให้ Deploy ใหม่และทดสอบสิทธิ์ด้วยสองบัญชี
- โปรไฟล์ส่วนตัวและการอนุมัติคำขอติดตามยังไม่ได้ทำงานครบ แม้ schema มี `isPrivate`
- Group Feed รองรับข้อความเท่านั้น; ยังไม่รองรับสื่อหรือ reaction
