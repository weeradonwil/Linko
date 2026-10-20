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
      throw const FollowServiceException('Follow action failed.');
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

  DocumentReference<Map<String, dynamic>> _request(String targetUid) =>
      _firestore
          .collection('users')
          .doc(targetUid)
          .collection('follow_requests')
          .doc(_uid);

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

  /// Reports whether the current account has a pending request for this profile.
  Stream<bool> watchHasRequested(String targetUid) =>
      _request(targetUid).snapshots().map((snapshot) => snapshot.exists);

  /// Streams requests that the profile owner can approve or reject.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchFollowRequests(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('follow_requests')
          .orderBy('createdAt')
          .snapshots();

  /// บันทึกความสัมพันธ์ทั้งสองด้านเพื่อให้หน้าโปรไฟล์นับจำนวนได้ตรงกัน
  Future<void> follow(String targetUid) async {
    final uid = _uid;
    if (uid == targetUid) {
      throw const FollowServiceException('Follow action failed.');
    }
    final followerReference = _follower(targetUid);
    final alreadyFollowing = await followerReference.get();
    if (alreadyFollowing.exists) return;

    final target = await _firestore.collection('users').doc(targetUid).get();
    if (!target.exists) {
      throw const FollowServiceException('Follow action failed.');
    }
    if (target.data()?['isPrivate'] == true) {
      await requestFollow(targetUid);
      return;
    }

    final batch = _firestore.batch();
    final data = {'uid': uid, 'createdAt': FieldValue.serverTimestamp()};
    batch.set(followerReference, data);
    batch.set(_following(targetUid), {
      'uid': targetUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.delete(_request(targetUid));

    await batch.commit();

    // Keep the follow relationship even if the optional notification rule is
    // not deployed yet or notification delivery is temporarily unavailable.
    final user = _auth.currentUser!;
    final actorName = user.displayName?.trim();
    try {
      await _firestore.collection('notifications').add({
        'recipientId': targetUid,
        'actorId': uid,
        'actorName': actorName == null || actorName.isEmpty
            ? 'สมาชิก'
            : actorName,
        'type': 'follow',
        'body': '',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // A notification failure must not undo a successful follow.
    }
  }

  /// Sends a request instead of creating the follower relationship immediately.
  Future<void> requestFollow(String targetUid) async {
    final uid = _uid;
    if (uid == targetUid) {
      throw const FollowServiceException('Follow action failed.');
    }
    final target = await _firestore.collection('users').doc(targetUid).get();
    if (target.data()?['isPrivate'] != true) {
      await follow(targetUid);
      return;
    }
    final follower = await _follower(targetUid).get();
    if (follower.exists) return;
    final request = _request(targetUid);
    if ((await request.get()).exists) return;
    await request.set({'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
  }

  /// Removes the current user's pending request.
  Future<void> cancelFollowRequest(String targetUid) =>
      _request(targetUid).delete();

  /// Approves a pending request and creates both sides of the follow relationship.
  Future<void> approveFollowRequest(String requesterUid) async {
    final uid = _uid;
    final request = _firestore
        .collection('users')
        .doc(uid)
        .collection('follow_requests')
        .doc(requesterUid);
    final follower = _firestore
        .collection('users')
        .doc(uid)
        .collection('followers')
        .doc(requesterUid);
    final following = _firestore
        .collection('users')
        .doc(requesterUid)
        .collection('following')
        .doc(uid);
    if ((await follower.get()).exists) {
      await request.delete();
      return;
    }
    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(follower, {'uid': requesterUid, 'createdAt': now});
    batch.set(following, {'uid': uid, 'createdAt': now});
    batch.delete(request);
    final actorName = _auth.currentUser?.displayName?.trim();
    await batch.commit();
    try {
      await _firestore.collection('notifications').add({
        'recipientId': requesterUid,
        'actorId': uid,
        'actorName': actorName == null || actorName.isEmpty
            ? 'Member'
            : actorName,
        'type': 'follow',
        'body': '',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // The accepted relationship remains valid if notification delivery fails.
    }
  }

  /// Rejects a request without changing either account's following list.
  Future<void> rejectFollowRequest(String requesterUid) => _firestore
      .collection('users')
      .doc(_uid)
      .collection('follow_requests')
      .doc(requesterUid)
      .delete();

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
