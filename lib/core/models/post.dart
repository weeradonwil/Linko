import 'package:cloud_firestore/cloud_firestore.dart';

/// ตัวแทนข้อมูลโพสต์หนึ่งรายการในฟีด พร้อมแปลงข้อมูล Firestore เป็นชนิด Dart
class Post {
  const Post({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.content,
    required this.createdAt,
    required this.tags,
    required this.visibility,
    required this.mediaPath,
    this.mediaType = 'none',
  });

  /// ID ของ document ใน posts; ใช้ระบุรายการเวลาแก้ไขหรือลบ
  final String id;

  /// UID เจ้าของโพสต์; ใช้เทียบกับผู้ใช้ปัจจุบันและตรวจ Firestore Rules
  final String userId;

  /// ชื่อที่แสดงบนการ์ดโพสต์ เป็นสำเนาจากชื่อผู้เขียนตอนสร้างโพสต์
  final String authorName;

  /// เนื้อหาข้อความของโพสต์
  final String content;

  /// เวลาโพสต์จาก Firestore; ใช้เรียงฟีดจากใหม่ไปเก่า
  final DateTime createdAt;

  /// คำค้นของโพสต์ ใช้แสดงเป็นป้ายกำกับและต่อยอดทำหน้าค้นหาตามแท็ก
  final List<String> tags;

  /// public คือสมาชิกที่ล็อกอินเห็นได้; private คือเห็นได้เฉพาะเจ้าของ
  final String visibility;

  /// Path ใน Firebase Storage; อ่านผ่าน SDK เพื่อให้ Storage Rules ตรวจสิทธิ์ทุกครั้ง
  final String? mediaPath;

  /// ชนิดสื่อที่แนบ: none, image หรือ video
  final String mediaType;

  /// อ่าน document แล้วสร้าง Post; ใช้เวลาปัจจุบันชั่วคราวหาก serverTimestamp
  /// ยังไม่ได้รับค่ากลับมาในระหว่างบันทึกแบบออฟไลน์
  factory Post.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final timestamp = data['createdAt'] as Timestamp?;
    final storedAuthorName = data['authorName'] as String?;

    return Post(
      id: snapshot.id,
      userId: data['userId'] as String? ?? '',
      authorName: (storedAuthorName == null || storedAuthorName.trim().isEmpty)
          ? 'สมาชิก'
          : storedAuthorName.trim(),
      content: data['content'] as String? ?? '',
      createdAt: timestamp?.toDate() ?? DateTime.now(),
      tags: List<String>.from(data['tags'] as List? ?? const []),
      // โพสต์รุ่นก่อนที่ยังไม่มี visibility ให้คงพฤติกรรมเดิมคือเป็นสาธารณะ
      visibility: data['visibility'] as String? ?? 'public',
      mediaPath: data['mediaPath'] as String?,
      mediaType: data['mediaType'] as String? ?? 'none',
    );
  }
}
