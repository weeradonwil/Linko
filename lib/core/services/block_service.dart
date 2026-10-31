import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// เก็บบล็อกของใครของมัน อีกฝ่ายอ่านรายชื่อทั้งหมดของเราไม่ได้
class BlockService {
  BlockService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  String get _uid => _auth.currentUser!.uid;
  CollectionReference<Map<String, dynamic>> get _blocks =>
      _db.collection('users').doc(_uid).collection('blocks');

  Stream<Set<String>> watchBlockedIds() => _blocks.snapshots().map(
    (snapshot) => snapshot.docs.map((doc) => doc.id).toSet(),
  );
  Stream<bool> watchBlocked(String peer) =>
      _blocks.doc(peer).snapshots().map((doc) => doc.exists);

  // อ่าน edge ที่มีตัวเราอยู่ด้วย เพื่อซ่อนทั้งกรณีเราบล็อกและถูกอีกฝ่ายบล็อก
  Stream<Set<String>> watchRestrictedIds() => _db
      .collection('block_edges')
      .where('participants', arrayContains: _uid)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (doc) => doc.data()['actorId'] == _uid
                  ? doc.data()['targetId'] as String
                  : doc.data()['actorId'] as String,
            )
            .toSet(),
      );

  Future<void> setBlocked(String peer, bool blocked) async {
    if (peer == _uid) throw StateError('บล็อกตัวเองไม่ได้นะ');
    if (blocked) {
      final create = _db.batch();
      create.set(_blocks.doc(peer), {
        'uid': peer,
        'createdAt': FieldValue.serverTimestamp(),
      });
      create.set(_db.collection('block_edges').doc('${_uid}_$peer'), {
        'actorId': _uid,
        'targetId': peer,
        'participants': [_uid, peer],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await create.commit();
      // ล้างการติดตามทั้งสองทางใน batch แยก บล็อกยังสำเร็จแม้ cleanup ต้องลองใหม่
      final batch = _db.batch();
      for (final path in [
        'users/$_uid/following/$peer',
        'users/$peer/followers/$_uid',
        'users/$peer/following/$_uid',
        'users/$_uid/followers/$peer',
        'users/$_uid/follow_requests/$peer',
        'users/$peer/follow_requests/$_uid',
      ]) {
        batch.delete(_db.doc(path));
      }
      await batch.commit();
    } else {
      final remove = _db.batch();
      remove.delete(_blocks.doc(peer));
      remove.delete(_db.collection('block_edges').doc('${_uid}_$peer'));
      await remove.commit();
    }
  }
}
