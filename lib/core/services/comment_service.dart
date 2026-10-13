// อ่าน/เขียนความคิดเห็น และสร้าง social notification ให้เจ้าของโพสต์ใน batch เดียวกัน
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/post_comment.dart';
import '../models/post.dart';

/// อ่านและเขียนความคิดเห็น พร้อมแจ้งเตือนเจ้าของโพสต์เมื่อมีผู้อื่นมาแสดงความคิดเห็น
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

  /// บันทึกความคิดเห็นและการแจ้งเตือนใน batch เดียว เพื่อไม่ให้ข้อมูลแยกจากกัน
  Future<void> addComment({required Post post, required String content}) async {
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
    final batch = _firestore.batch();
    batch.set(comment, {
      'authorId': user.uid,
      'authorName': authorName,
      'content': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // ไม่สร้างการแจ้งเตือนเมื่อเจ้าของโพสต์แสดงความคิดเห็นในโพสต์ตัวเอง
    if (post.userId.isNotEmpty && post.userId != user.uid) {
      final notification = _firestore.collection('notifications').doc();
      batch.set(notification, {
        'recipientId': post.userId,
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

    await batch.commit();
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

class CommentServiceException implements Exception {
  const CommentServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}
