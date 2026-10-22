// โมเดลกลุ่มและโพสต์ในกลุ่ม แปลงข้อมูล Firestore เป็นข้อมูลแสดงผล
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/document_values.dart';

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
    this.isDeleting = false,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String visibility;
  final DateTime? createdAt;
  final String? avatarPath;
  final int? memberCount;
  final bool isDeleting;

  factory SocialGroup.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final timestamp = data['createdAt'];
    return SocialGroup(
      id: snapshot.id,
      name: readName(data['name'], 'กลุ่มไม่มีชื่อ'),
      description: readString(data['description']),
      ownerId: readString(data['ownerId']),
      visibility: readString(data['visibility'], 'public'),
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
      avatarPath: readOptionalString(data['avatarPath']),
      memberCount: data['memberCount'] == null
          ? null
          : readCount(data['memberCount']),
      isDeleting: data['isDeleting'] == true,
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
      uid: readString(data['uid'], snapshot.id),
      displayName: readName(data['displayName']),
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
      authorId: readString(data['authorId']),
      authorName: readName(data['authorName']),
      content: readString(data['content']),
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
      mediaPath: readOptionalString(data['mediaPath']),
      mediaType: readString(data['mediaType'], 'none'),
      thumbnailPath: readOptionalString(data['thumbnailPath']),
    );
  }
}
