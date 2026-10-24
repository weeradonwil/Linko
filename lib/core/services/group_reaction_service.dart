// จัดการ Like/Dislike ของโพสต์ในกลุ่ม โดยเก็บหนึ่งรายการต่อสมาชิกต่อโพสต์
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/document_values.dart';

/// อ่านและเปลี่ยนปฏิกิริยาใน groups/{groupId}/posts/{postId}/reactions/{uid}
class GroupReactionService {
  GroupReactionService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const supportedReactions = {
    'like',
    'love',
    'haha',
    'wow',
    'sad',
    'angry',
    'dislike',
  };

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
    final batch = _firestore.batch();
    batch.set(reference, {
      'uid': uid,
      'reaction': reaction,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // แจ้งเฉพาะเจ้าของโพสต์ที่ยังอยู่ในกลุ่ม และบันทึกพร้อม Like ใน batch เดียว
    if (reaction == 'like') {
      final group = _firestore.collection('groups').doc(groupId);
      final post = await group.collection('posts').doc(postId).get();
      final author = readString(post.data()?['authorId']);
      if (author.isNotEmpty &&
          author != uid &&
          (await group.collection('members').doc(author).get()).exists) {
        batch.set(_firestore.collection('notifications').doc(), {
          'recipientId': author,
          'actorId': uid,
          'actorName': readName(_auth.currentUser?.displayName),
          'type': 'like',
          'body': '',
          'groupId': groupId,
          'postId': postId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }
}

class GroupReactionException implements Exception {
  const GroupReactionException(this.message);

  final String message;

  @override
  String toString() => message;
}
