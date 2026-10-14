// จัดการปฏิกิริยาต่อโพสต์ โดยเก็บหนึ่ง reaction ต่อผู้ใช้ต่อโพสต์
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/social_reaction.dart';

/// อ่านและบันทึก reaction; Firestore Rules บังคับให้เจ้าของแก้ได้เฉพาะเอกสารตนเอง
class ReactionService {
  ReactionService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static final supportedReactions = SocialReaction.options
      .map((reaction) => reaction.id)
      .toSet();

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
    if (!supportedReactions.contains(reaction)) {
      throw const ReactionServiceException('ไม่รองรับ reaction นี้');
    }
    final reference = _reactions(postId).doc(_uid);
    final current = await reference.get();
    if (current.data()?['reaction'] == reaction) {
      await reference.delete();
      return;
    }
    await reference.set({
      'uid': _uid,
      'reaction': reaction,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class ReactionServiceException implements Exception {
  const ReactionServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
