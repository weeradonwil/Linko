// จัดการความสัมพันธ์ติดตามและอ่านจำนวนผู้ติดตามของสมาชิก
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// บันทึกความสัมพันธ์ทั้งฝั่งผู้ติดตามและผู้ที่ถูกติดตามใน batch เดียว
class FollowService {
  FollowService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw const FollowServiceException('กรุณาเข้าสู่ระบบก่อน');
    }
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> _follower(String ownerUid) =>
      _firestore
          .collection('users')
          .doc(ownerUid)
          .collection('followers')
          .doc(_uid);

  DocumentReference<Map<String, dynamic>> _following(String targetUid) =>
      _firestore
          .collection('users')
          .doc(_uid)
          .collection('following')
          .doc(targetUid);

  /// ฟังรายชื่อผู้ติดตามแบบ real-time
  Stream<QuerySnapshot<Map<String, dynamic>>> watchFollowers(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('followers')
          .snapshots();

  /// ฟังรายชื่อบัญชีที่ผู้ใช้ติดตาม
  Stream<QuerySnapshot<Map<String, dynamic>>> watchFollowing(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('following')
          .snapshots();

  /// ฟังว่าบัญชีปัจจุบันติดตามโปรไฟล์นี้อยู่หรือไม่
  Stream<bool> watchIsFollowing(String targetUid) =>
      _following(targetUid).snapshots().map((snapshot) => snapshot.exists);

  /// บันทึกความสัมพันธ์ทั้งสองด้านเพื่อให้หน้าโปรไฟล์นับจำนวนได้ตรงกัน
  Future<void> follow(String targetUid) async {
    final uid = _uid;
    if (uid == targetUid) {
      throw const FollowServiceException('ไม่สามารถติดตามบัญชีตัวเองได้');
    }
    final batch = _firestore.batch();
    final data = {'uid': uid, 'createdAt': FieldValue.serverTimestamp()};
    batch.set(_follower(targetUid), data);
    batch.set(_following(targetUid), {
      'uid': targetUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// ลบความสัมพันธ์ทั้งสองด้านใน batch เดียว
  Future<void> unfollow(String targetUid) async {
    final batch = _firestore.batch();
    batch.delete(_follower(targetUid));
    batch.delete(_following(targetUid));
    await batch.commit();
  }
}

class FollowServiceException implements Exception {
  const FollowServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
