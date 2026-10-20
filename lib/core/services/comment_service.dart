// อ่าน/เขียนความคิดเห็น และแจ้งเตือนผู้ติดตามเจ้าของโพสต์
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/post_comment.dart';
import '../models/post.dart';

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

  CollectionReference<Map<String, dynamic>> _comments(String postId) =>
      _firestore.collection('posts').doc(postId).collection('comments');

  /// ฟังความคิดเห็นแบบ real-time และเรียงจากเก่าไปใหม่เพื่อแสดงเป็นบทสนทนา
  Stream<List<PostComment>> watchComments(String postId) => _comments(postId)
      .orderBy('createdAt')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(PostComment.fromSnapshot).toList());

  /// โหลดโพสต์ที่เกี่ยวข้องเมื่อผู้ใช้เปิดการแจ้งเตือนความคิดเห็น
  Future<Post?> getPost(String postId) async {
    final snapshot = await _firestore.collection('posts').doc(postId).get();
    if (!snapshot.exists) return null;
    return Post.fromSnapshot(snapshot);
  }

  /// บันทึกความคิดเห็นก่อน แล้วส่งแจ้งเตือนให้ผู้ติดตามโดยไม่แจ้งเตือนเจ้าของโพสต์โดยตรง
  Future<CommentDeliveryResult> addComment({
    required Post post,
    required String content,
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

    final comment = _comments(post.id).doc();
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

    // Firestore จำกัด 500 writes ต่อ batch; ส่งแจ้งเตือนเป็นชุดละ 450 รายการ
    for (var offset = 0; offset < recipients.length; offset += 450) {
      final batch = _firestore.batch();
      final end = (offset + 450).clamp(0, recipients.length);
      for (final follower in recipients.sublist(offset, end)) {
        final notification = notifications.doc(
          'comment_${comment.id}_${follower.id}',
        );
        batch.set(notification, {
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
      }
      try {
        await batch.commit();
        notifiedFollowers += end - offset;
      } catch (_) {
        // Comment ถูกบันทึกแล้ว; แจ้งผลการเตือนแยกเพื่อไม่ให้ผู้ใช้ส่งซ้ำ
        return CommentDeliveryResult(
          notificationsComplete: false,
          eligibleFollowers: recipients.length,
          notifiedFollowers: notifiedFollowers,
        );
      }
    }
    return CommentDeliveryResult(
      notificationsComplete: true,
      eligibleFollowers: recipients.length,
      notifiedFollowers: notifiedFollowers,
    );
  }

  /// ลบความคิดเห็นของบัญชีปัจจุบัน โดย Firestore Rules ตรวจสิทธิ์เจ้าของซ้ำอีกชั้น
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    _user;
    await _comments(postId).doc(commentId).delete();
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
