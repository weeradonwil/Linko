// อ่าน/เขียนความคิดเห็นฟีดหลักและกลุ่ม พร้อมแจ้งเตือนเฉพาะผู้รับที่มีสิทธิ์
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/post_comment.dart';
import '../models/post.dart';
import '../models/social_group.dart';

/// อ่านและเขียนความคิดเห็น พร้อมแจ้งเตือนเฉพาะผู้ติดตามเจ้าของโพสต์
class CommentService {
  CommentService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw const CommentServiceException('กรุณาเข้าสู่ระบบก่อน');
    }
    return user;
  }

  /// เลือกตำแหน่งโพสต์ให้ตรงกับฟีดหลักหรือกลุ่ม โดยใช้กติกา Comment เดียวกัน
  DocumentReference<Map<String, dynamic>> _post(String id, String? groupId) =>
      groupId == null
      ? _firestore.collection('posts').doc(id)
      : _firestore
            .collection('groups')
            .doc(groupId)
            .collection('posts')
            .doc(id);

  CollectionReference<Map<String, dynamic>> _comments(
    String postId,
    String? groupId,
  ) => _post(postId, groupId).collection('comments');

  /// ฟังความคิดเห็นแบบ real-time และเรียงจากเก่าไปใหม่เพื่อแสดงเป็นบทสนทนา
  Stream<List<PostComment>> watchComments(
    String postId, {
    int limit = 50,
    String? groupId,
  }) => _comments(postId, groupId)
      .orderBy('createdAt')
      .limitToLast(limit)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(PostComment.fromSnapshot).toList());

  /// โหลดโพสต์ที่เกี่ยวข้องเมื่อผู้ใช้เปิดการแจ้งเตือนความคิดเห็น
  Future<Post?> getPost(String postId, {String? groupId}) async {
    final snapshot = await _post(postId, groupId).get();
    if (!snapshot.exists) return null;
    return groupId == null
        ? Post.fromSnapshot(snapshot)
        : GroupPost.fromSnapshot(snapshot).asPost();
  }

  /// บันทึกก่อนแจ้งเตือน: ฟีดหลักส่งให้ผู้ติดตาม ส่วนกลุ่มส่งให้เจ้าของโพสต์ที่เป็นสมาชิก
  Future<CommentDeliveryResult> addComment({
    required Post post,
    required String content,
    String? groupId,
  }) async {
    final user = _user;
    final text = content.trim();
    if (text.isEmpty) {
      throw const CommentServiceException('พิมพ์ความคิดเห็นก่อนส่ง');
    }
    if (text.length > 1000) {
      throw const CommentServiceException(
        'ความคิดเห็นต้องไม่เกิน 1,000 ตัวอักษร',
      );
    }

    final comment = _comments(post.id, groupId).doc();
    final displayName = user.displayName?.trim();
    final authorName = displayName == null || displayName.isEmpty
        ? 'สมาชิก'
        : displayName;
    await comment.set({
      'authorId': user.uid,
      'authorName': authorName,
      'content': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // ความคิดเห็นในกลุ่มใช้สิทธิ์สมาชิกกลุ่ม ไม่ส่งข้อมูลออกไปยังผู้ติดตามนอกกลุ่ม
    if (groupId != null) {
      if (post.userId != user.uid) {
        try {
          await _firestore
              .collection('notifications')
              .doc('group_comment_${groupId}_${post.id}_${comment.id}')
              .set({
                'recipientId': post.userId,
                'actorId': user.uid,
                'actorName': authorName,
                'type': 'comment',
                'body': text,
                'groupId': groupId,
                'postId': post.id,
                'commentId': comment.id,
                'isRead': false,
                'createdAt': FieldValue.serverTimestamp(),
              });
          return const CommentDeliveryResult(
            notificationsComplete: true,
            eligibleFollowers: 1,
            notifiedFollowers: 1,
          );
        } catch (_) {
          return const CommentDeliveryResult(
            notificationsComplete: false,
            eligibleFollowers: 1,
            notifiedFollowers: 0,
          );
        }
      }
      return const CommentDeliveryResult(
        notificationsComplete: true,
        eligibleFollowers: 0,
        notifiedFollowers: 0,
      );
    }

    // ผู้ติดตามต้องเปิดโพสต์นั้นได้ก่อน จึงไม่ส่งเตือนสำหรับโพสต์ส่วนตัว
    if (post.userId.isEmpty || post.visibility == 'private') {
      return const CommentDeliveryResult(
        notificationsComplete: true,
        eligibleFollowers: 0,
        notifiedFollowers: 0,
      );
    }
    QuerySnapshot<Map<String, dynamic>> followers;
    try {
      followers = await _firestore
          .collection('users')
          .doc(post.userId)
          .collection('followers')
          .get();
    } catch (_) {
      return const CommentDeliveryResult(
        notificationsComplete: false,
        eligibleFollowers: null,
        notifiedFollowers: 0,
      );
    }
    final recipients = followers.docs
        .where((follower) => follower.id != user.uid)
        .toList();
    var notifiedFollowers = 0;
    final notifications = _firestore.collection('notifications');

    // Each write has its own Rules access-call budget. Bound parallel requests
    // instead of putting many distinct follower checks into one atomic batch.
    const concurrency = 8;
    for (var offset = 0; offset < recipients.length; offset += concurrency) {
      final end = (offset + concurrency).clamp(0, recipients.length);
      final deliveries = await Future.wait(
        recipients.sublist(offset, end).map((follower) async {
          final notification = notifications.doc(
            'comment_${comment.id}_${follower.id}',
          );
          try {
            await notification.set({
              'recipientId': follower.id,
              'actorId': user.uid,
              'actorName': authorName,
              'type': 'comment',
              'body': text,
              'postId': post.id,
              'commentId': comment.id,
              'isRead': false,
              'createdAt': FieldValue.serverTimestamp(),
            });
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      notifiedFollowers += deliveries.where((delivered) => delivered).length;
    }
    return CommentDeliveryResult(
      notificationsComplete: notifiedFollowers == recipients.length,
      eligibleFollowers: recipients.length,
      notifiedFollowers: notifiedFollowers,
    );
  }

  /// ลบความคิดเห็นของบัญชีปัจจุบัน โดย Firestore Rules ตรวจสิทธิ์เจ้าของซ้ำอีกชั้น
  Future<void> deleteComment({
    required String postId,
    required String commentId,
    String? groupId,
  }) async {
    _user;
    await _comments(postId, groupId).doc(commentId).delete();
  }
}

/// ผลการแจ้งเตือนแยกจากผลบันทึก Comment เพื่อรายงานกรณีส่งได้ไม่ครบ
class CommentDeliveryResult {
  const CommentDeliveryResult({
    required this.notificationsComplete,
    required this.eligibleFollowers,
    required this.notifiedFollowers,
  });

  final bool notificationsComplete;
  final int? eligibleFollowers;
  final int notifiedFollowers;
}

class CommentServiceException implements Exception {
  const CommentServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}
