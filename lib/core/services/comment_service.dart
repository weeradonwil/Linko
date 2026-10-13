import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/post_comment.dart';
import '../models/post.dart';

/// Reads and writes comments and creates an in-app notification for the post owner.
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

  /// Streams a post's comments in chronological order for the conversation view.
  Stream<List<PostComment>> watchComments(String postId) => _comments(postId)
      .orderBy('createdAt')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(PostComment.fromSnapshot).toList());

  /// Loads a post when opening a comment notification.
  Future<Post?> getPost(String postId) async {
    final snapshot = await _firestore.collection('posts').doc(postId).get();
    if (!snapshot.exists) return null;
    return Post.fromSnapshot(snapshot);
  }

  /// Saves a comment and its notification together so they cannot get out of sync.
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

    // Do not notify someone about their own comment on their own post.
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

  /// Deletes only the signed-in user's own comment; Firestore Rules enforce ownership too.
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
