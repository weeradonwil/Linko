// จัดการปฏิกิริยาต่อโพสต์ โดยเก็บหนึ่ง reaction ต่อผู้ใช้ต่อโพสต์
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// อ่านและบันทึก reaction; Firestore Rules บังคับให้เจ้าของแก้ได้เฉพาะเอกสารตนเอง
class ReactionService {
  ReactionService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const supportedReactions = {'like', 'dislike'};

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw const ReactionServiceException('กรุณาเข้าสู่ระบบก่อน');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> _reactions(String postId) =>
      _firestore.collection('posts').doc(postId).collection('reactions');

  /// ฟัง reaction ทั้งหมดของโพสต์เพื่อแสดงจำนวนและ reaction ของบัญชีปัจจุบัน
  Stream<QuerySnapshot<Map<String, dynamic>>> watchReactions(String postId) =>
      _reactions(postId).snapshots();

  /// ตั้ง reaction ที่เลือก; เลือกซ้ำอีกครั้งเพื่อลบ reaction ของตัวเอง
  Future<void> toggleReaction({
    required String postId,
    required String reaction,
  }) async {
    final uid = _uid;
    final user = _auth.currentUser!;
    if (!supportedReactions.contains(reaction)) {
      throw const ReactionServiceException('ไม่รองรับ reaction นี้');
    }
    final reference = _reactions(postId).doc(uid);
    final current = await reference.get();
    if (current.data()?['reaction'] == reaction) {
      await reference.delete();
      return;
    }
    final batch = _firestore.batch();
    batch.set(reference, {
      'uid': uid,
      'reaction': reaction,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Alert the post owner only when a Like is added or changed to Like.
    if (reaction == 'like' && current.data()?['reaction'] != 'like') {
      final post = await _firestore.collection('posts').doc(postId).get();
      final recipientId = post.data()?['userId'] as String?;
      if (recipientId != null && recipientId != uid) {
        final actorName = user.displayName?.trim();
        batch.set(_firestore.collection('notifications').doc(), {
          'recipientId': recipientId,
          'actorId': uid,
          'actorName': actorName == null || actorName.isEmpty
              ? 'สมาชิก'
              : actorName,
          'type': 'like',
          'body': '',
          'postId': postId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
  }
}

class ReactionServiceException implements Exception {
  const ReactionServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
