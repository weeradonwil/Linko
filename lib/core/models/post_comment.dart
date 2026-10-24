// โมเดลความคิดเห็นใต้ posts/{postId}/comments/{commentId}
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/document_values.dart';

/// แทนความคิดเห็นหนึ่งรายการ พร้อมแปลง Timestamp จาก Firestore เป็น DateTime
class PostComment {
  const PostComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  final String id; // document ID ของความคิดเห็น
  final String authorId; // UID ของผู้เขียน ใช้ตรวจสิทธิ์การลบ
  final String authorName; // ชื่อที่บันทึกไว้เพื่อแสดงในหน้าคอมเมนต์
  final String content; // ข้อความความคิดเห็น
  final DateTime?
  createdAt; // เวลาจาก Firestore; เป็น null ได้ระหว่างรอ serverTimestamp

  factory PostComment.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final timestamp = data['createdAt'];
    return PostComment(
      id: snapshot.id,
      authorId: readString(data['authorId']),
      authorName: readName(data['authorName']),
      content: readString(data['content']),
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}
