// อ่าน แจ้งเตือนที่ยังไม่อ่าน และทำเครื่องหมายอ่านแล้วสำหรับบัญชีปัจจุบัน
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
  static const _socialTypes = ['like', 'comment', 'follow'];
  // กรองด้วย recipientId ให้ตรงกับเงื่อนไขอ่านใน Firestore Rules
  /// ขยายช่วงรายการได้ เพื่อให้เปิดอ่านแจ้งเตือนเก่าที่ badge ยังนับอยู่ได้
  Stream<List<AppNotification>> watchNotifications({
    bool unreadOnly = false,
    int limit = 100,
  }) {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    Query<Map<String, dynamic>> q = _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: user.uid)
        .where('type', whereIn: _socialTypes);
    if (unreadOnly) q = q.where('isRead', isEqualTo: false);
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(AppNotification.fromSnapshot).toList(),
        );
  }

  /// Stream จำนวนแจ้งเตือนที่ยังไม่อ่าน เพื่ออัปเดต badge แบบ real-time
  Stream<int> watchUnreadCount() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .where('type', whereIn: _socialTypes)
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
        .where('type', whereIn: _socialTypes)
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
