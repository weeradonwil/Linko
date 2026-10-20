// โมเดลกลุ่มและโพสต์ในกลุ่ม แปลงข้อมูล Firestore เป็นข้อมูลแสดงผล
import 'package:cloud_firestore/cloud_firestore.dart';

/// ข้อมูลกลุ่มที่แสดงในรายการกลุ่มและหน้ารายละเอียด
class SocialGroup {
  const SocialGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.visibility,
    required this.createdAt,
    this.avatarPath,
    this.memberCount,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String visibility;
  final DateTime? createdAt;
  final String? avatarPath;
  final int? memberCount;

  factory SocialGroup.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final timestamp = data['createdAt'];
    return SocialGroup(
      id: snapshot.id,
      name: data['name'] as String? ?? 'กลุ่มไม่มีชื่อ',
      description: data['description'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      visibility: data['visibility'] as String? ?? 'public',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
      avatarPath: data['avatarPath'] as String?,
      memberCount: data['memberCount'] as int?,
    );
  }
}

/// คำขอเข้ากลุ่มส่วนตัวที่รอเจ้าของอนุมัติ
class GroupJoinRequest {
  const GroupJoinRequest({
    required this.uid,
    required this.displayName,
    required this.createdAt,
  });

  final String uid;
  final String displayName;
  final DateTime? createdAt;

  factory GroupJoinRequest.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final timestamp = data['createdAt'];
    return GroupJoinRequest(
      uid: data['uid'] as String? ?? snapshot.id,
      displayName: data['displayName'] as String? ?? 'สมาชิก',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

/// โพสต์ข้อความอย่างง่ายที่อยู่ภายในกลุ่ม
class GroupPost {
  const GroupPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.mediaPath,
    this.mediaType = 'none',
    this.thumbnailPath,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime? createdAt;
  final String? mediaPath;
  final String mediaType;
  final String? thumbnailPath;

  factory GroupPost.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final timestamp = data['createdAt'];
    return GroupPost(
      id: snapshot.id,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'สมาชิก',
      content: data['content'] as String? ?? '',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
      mediaPath: data['mediaPath'] as String?,
      mediaType: data['mediaType'] as String? ?? 'none',
      thumbnailPath: data['thumbnailPath'] as String?,
    );
  }
}
