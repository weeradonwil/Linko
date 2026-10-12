import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_models.dart';

/// อ่านและปรับสถานะการแจ้งเตือนของผู้ใช้ปัจจุบันใน Firestore
class NotificationService {
  NotificationService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  // กรองด้วย recipientId ให้ตรงกับเงื่อนไขอ่านใน Firestore Rules
  Stream<List<AppNotification>> watchNotifications({bool unreadOnly = false}) {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    Query<Map<String, dynamic>> q = _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: user.uid);
    if (unreadOnly) q = q.where('isRead', isEqualTo: false);
    return q.limit(100).snapshots().map((s) {
      final a = s.docs.map(AppNotification.fromSnapshot).toList();
      a.sort(
        (x, y) => (y.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(x.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      return a;
    });
  }

  /// Stream จำนวนแจ้งเตือนที่ยังไม่อ่าน เพื่ออัปเดต badge แบบ real-time
  Stream<int> watchUnreadCount() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  Future<void> markRead(String id) =>
      _firestore.collection('notifications').doc(id).update({'isRead': true});
  // แบ่งการอัปเดตเป็นชุดเพื่อไม่ให้เกินจำนวน writes ต่อ Firestore batch
  Future<void> markAllRead() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final s = await _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();
    for (var i = 0; i < s.docs.length; i += 400) {
      final b = _firestore.batch();
      final end = (i + 400).clamp(0, s.docs.length);
      for (final d in s.docs.sublist(i, end)) {
        b.update(d.reference, {'isRead': true});
      }
      await b.commit();
    }
  }
}
