// จัดการสร้าง ค้นหา เข้าร่วม และโพสต์ข้อความในกลุ่ม
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/social_group.dart';

/// คุยกับ Firestore สำหรับกลุ่มและสมาชิก โดย Rules ตรวจสิทธิ์ทุกการเขียน
class GroupService {
  GroupService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw const GroupServiceException('กรุณาเข้าสู่ระบบก่อน');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');

  /// แสดงกลุ่มสาธารณะและกลุ่มส่วนตัวที่บัญชีปัจจุบันเป็นเจ้าของ
  Stream<List<SocialGroup>> watchDiscoverableGroups() => _groups
      .where('visibility', isEqualTo: 'public')
      .snapshots()
      .map((snapshot) {
        final groups = snapshot.docs.map(SocialGroup.fromSnapshot).toList();
        groups.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
        return groups;
      });

  /// ฟังโพสต์ในกลุ่มจากเก่าไปใหม่ตามลำดับเวลา
  Stream<List<GroupPost>> watchPosts(String groupId) => _groups
      .doc(groupId)
      .collection('posts')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(GroupPost.fromSnapshot).toList());

  /// ฟังสถานะสมาชิกและจำนวนสมาชิกแบบสด
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMembers(String groupId) =>
      _groups.doc(groupId).collection('members').snapshots();

  /// สร้างกลุ่มและเพิ่มเจ้าของเป็นสมาชิกด้วย batch เดียว
  Future<String> createGroup({
    required String name,
    required String description,
    required String visibility,
  }) async {
    final user = _auth.currentUser;
    final uid = _uid;
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 60) {
      throw const GroupServiceException('ชื่อกลุ่มต้องมี 1–60 ตัวอักษร');
    }
    if (description.trim().length > 300) {
      throw const GroupServiceException(
        'คำอธิบายกลุ่มต้องไม่เกิน 300 ตัวอักษร',
      );
    }
    final group = _groups.doc();
    final batch = _firestore.batch();
    batch.set(group, {
      'name': cleanName,
      'description': description.trim(),
      'ownerId': uid,
      'visibility': visibility == 'private' ? 'private' : 'public',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(group.collection('members').doc(uid), {
      'uid': uid,
      'displayName': user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : 'สมาชิก',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return group.id;
  }

  /// แก้ชื่อและคำอธิบาย โดยให้ Rules ตรวจว่าเป็นเจ้าของกลุ่ม
  Future<void> updateGroup({
    required String groupId,
    required String name,
    required String description,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 60) {
      throw const GroupServiceException('ชื่อกลุ่มต้องมี 1–60 ตัวอักษร');
    }
    if (description.trim().length > 300) {
      throw const GroupServiceException(
        'คำอธิบายกลุ่มต้องไม่เกิน 300 ตัวอักษร',
      );
    }
    await _groups.doc(groupId).update({
      'name': cleanName,
      'description': description.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ลบโพสต์ สมาชิก และเอกสารกลุ่มเป็นชุด เพื่อไม่ให้ข้อมูลย่อยค้างอยู่
  Future<void> deleteGroup(String groupId) async {
    final group = _groups.doc(groupId);
    final data = await group.get();
    if (!data.exists || data.data()?['ownerId'] != _uid) {
      throw const GroupServiceException('ลบได้เฉพาะกลุ่มที่คุณเป็นเจ้าของ');
    }
    final members = await group.collection('members').get();
    final posts = await group.collection('posts').get();
    // ลบโพสต์ก่อน เพราะการลบโพสต์ต้องอาศัยสถานะสมาชิกที่ยังมีอยู่
    for (final documents in [posts.docs, members.docs]) {
      for (var start = 0; start < documents.length; start += 450) {
        final batch = _firestore.batch();
        final end = (start + 450).clamp(0, documents.length);
        for (final document in documents.sublist(start, end)) {
          batch.delete(document.reference);
        }
        await batch.commit();
      }
    }
    await group.delete();
  }

  /// เข้าร่วมได้เฉพาะกลุ่มสาธารณะ; เอกสารสมาชิกใช้ UID เป็น document ID
  Future<void> joinGroup(SocialGroup group) async {
    final user = _auth.currentUser;
    final uid = _uid;
    if (group.visibility != 'public') {
      throw const GroupServiceException('กลุ่มนี้เป็นส่วนตัว');
    }
    await _groups.doc(group.id).collection('members').doc(uid).set({
      'uid': uid,
      'displayName': user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : 'สมาชิก',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// ออกจากกลุ่มได้ ยกเว้นเจ้าของที่ต้องโอนหรือลบกลุ่มก่อน
  Future<void> leaveGroup(SocialGroup group) async {
    final uid = _uid;
    if (group.ownerId == uid) {
      throw const GroupServiceException('เจ้าของกลุ่มไม่สามารถออกจากกลุ่มได้');
    }
    await _groups.doc(group.id).collection('members').doc(uid).delete();
  }

  /// เพิ่มโพสต์ข้อความสั้นลงใน feed ของกลุ่ม
  Future<void> addPost({
    required String groupId,
    required String content,
  }) async {
    final text = content.trim();
    if (text.isEmpty || text.length > 1000) {
      throw const GroupServiceException('โพสต์ต้องมี 1–1,000 ตัวอักษร');
    }
    final user = _auth.currentUser;
    await _groups.doc(groupId).collection('posts').add({
      'authorId': _uid,
      'authorName': user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : 'สมาชิก',
      'content': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

class GroupServiceException implements Exception {
  const GroupServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
