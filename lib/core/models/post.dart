// โมเดลโพสต์เก็บข้อมูลที่ใช้ในฟีดและแปลงชนิดข้อมูลจาก Firestore
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/document_values.dart';

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
    this.thumbnailPath,
    this.editedAt,
    this.isDeleting = false,
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

  /// Latest edit time; null means this post has not been edited.
  final DateTime? editedAt;
  final bool isDeleting;

  /// คำค้นของโพสต์ ใช้แสดงเป็นป้ายกำกับและต่อยอดทำหน้าค้นหาตามแท็ก
  final List<String> tags;

  /// public คือสมาชิกที่ล็อกอินเห็นได้; private คือเห็นได้เฉพาะเจ้าของ
  final String visibility;

  /// Path ใน Firebase Storage; อ่านผ่าน SDK เพื่อให้ Storage Rules ตรวจสิทธิ์ทุกครั้ง
  final String? mediaPath;

  /// ชนิดสื่อที่แนบ: none, image หรือ video
  final String mediaType;

  /// Path ภาพตัวอย่างของวิดีโอ; ใช้แสดงเฟรมก่อนเริ่มเล่นไฟล์จริง
  final String? thumbnailPath;

  /// อ่าน document แล้วสร้าง Post; ใช้เวลาปัจจุบันชั่วคราวหาก serverTimestamp
  /// ยังไม่ได้รับค่ากลับมาในระหว่างบันทึกแบบออฟไลน์
  factory Post.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    return Post.fromData(snapshot.id, snapshot.data() ?? const {});
  }

  factory Post.fromData(String id, Map<String, dynamic> data) {
    final storedAuthorName = readString(data['authorName']).trim();
    final path = readOptionalString(data['mediaPath']);
    final storedType = readString(data['mediaType']);
    final mediaType = const {'none', 'image', 'video'}.contains(storedType)
        ? storedType
        : path == null
        ? 'none'
        : RegExp(r'\.(mp4|mov|m4v|webm)$', caseSensitive: false).hasMatch(path)
        ? 'video'
        : 'image';

    return Post(
      id: id,
      userId: readString(data['userId']),
      authorName: storedAuthorName.isEmpty ? 'สมาชิก' : storedAuthorName,
      content: readString(data['content']),
      createdAt:
          readDate(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      editedAt: readDate(data['editedAt']),
      isDeleting: data['isDeleting'] == true,
      tags: readStrings(data['tags']),
      // โพสต์รุ่นก่อนที่ยังไม่มี visibility ให้คงพฤติกรรมเดิมคือเป็นสาธารณะ
      visibility: readString(data['visibility'], 'public'),
      mediaPath: path,
      mediaType: mediaType,
      thumbnailPath: readOptionalString(data['thumbnailPath']),
    );
  }
}
