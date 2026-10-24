// โมเดลกลุ่มและโพสต์ในกลุ่ม แปลงข้อมูล Firestore เป็นข้อมูลแสดงผล
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/document_values.dart';
import 'post.dart';

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

/// ข้อมูลโพสต์กลุ่มพร้อมสื่อ แท็ก สถานะแก้ไข และสถานะงานลบที่ทำต่อได้
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
    this.tags = const [],
    this.editedAt,
    this.isDeleting = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime? createdAt;
  final String? mediaPath;
  final String mediaType;
  final String? thumbnailPath;
  final List<String> tags;
  final DateTime? editedAt;
  final bool isDeleting;

  /// แปลงเป็นข้อมูลกลาง เพื่อใช้ฟอร์มแก้ไขและหน้าความคิดเห็นร่วมกับฟีดหลัก
  Post asPost() => Post.fromData(id, {
    'userId': authorId,
    'authorName': authorName,
    'content': content,
    'tags': tags,
    'visibility': 'public',
    'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    'editedAt': editedAt == null ? null : Timestamp.fromDate(editedAt!),
    'mediaPath': mediaPath,
    'mediaType': mediaType,
    'thumbnailPath': thumbnailPath,
    'isDeleting': isDeleting,
  });

  factory GroupPost.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
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
      tags: readStrings(data['tags']),
      editedAt: data['editedAt'] is Timestamp
          ? (data['editedAt'] as Timestamp).toDate()
          : null,
      isDeleting: data['isDeleting'] == true,
    );
  }
}
