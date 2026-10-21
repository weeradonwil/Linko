// จัดการ Like/Dislike ของโพสต์ในกลุ่ม โดยเก็บหนึ่งรายการต่อสมาชิกต่อโพสต์
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// อ่านและเปลี่ยนปฏิกิริยาใน groups/{groupId}/posts/{postId}/reactions/{uid}
class GroupReactionService {
  GroupReactionService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const supportedReactions = {'like', 'dislike'};

  CollectionReference<Map<String, dynamic>> _reactions(
    String groupId,
    String postId,
  ) => _firestore
      .collection('groups')
      .doc(groupId)
      .collection('posts')
      .doc(postId)
      .collection('reactions');

  /// ฟังรายการล่าสุดให้หน้าจอคำนวณจำนวนและแสดงปฏิกิริยาของผู้ใช้
  Stream<QuerySnapshot<Map<String, dynamic>>> watchReactions(
    String groupId,
    String postId,
  ) => _reactions(groupId, postId).snapshots();

  /// กดแบบเดิมเพื่อลบ หรือกดอีกแบบเพื่อแทนค่า โดยใช้ UID เป็น ID ป้องกันรายการซ้ำ
  Future<void> toggleReaction({
    required String groupId,
    required String postId,
    required String reaction,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const GroupReactionException('Sign in first.');
    if (!supportedReactions.contains(reaction)) {
      throw const GroupReactionException('Unsupported reaction.');
    }
    final reference = _reactions(groupId, postId).doc(uid);
    final current = await reference.get();
    if (current.data()?['reaction'] == reaction) {
      await reference.delete();
      return;
    }
    await reference.set({
      'uid': uid,
      'reaction': reaction,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class GroupReactionException implements Exception {
  const GroupReactionException(this.message);

  final String message;

  @override
  String toString() => message;
}
