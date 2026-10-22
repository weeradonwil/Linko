// จัดการสร้าง ค้นหา เข้าร่วม และโพสต์ข้อความในกลุ่ม
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/social_group.dart';
import '../utils/document_values.dart';

/// คุยกับ Firestore สำหรับกลุ่มและสมาชิก โดย Rules ตรวจสิทธิ์ทุกการเขียน
class GroupService {
  GroupService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw const GroupServiceException('กรุณาเข้าสู่ระบบก่อน');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');

  /// แสดง metadata ของกลุ่มให้สมาชิกที่เข้าสู่ระบบเลือกกลุ่มได้
  Stream<List<SocialGroup>> watchDiscoverableGroups() =>
      _groups.snapshots().map((snapshot) {
        final groups = snapshot.docs.map(SocialGroup.fromSnapshot).toList();
        groups.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
        return groups;
      });

  /// ฟังโพสต์ในกลุ่มจากเก่าไปใหม่ตามลำดับเวลา
  Stream<List<GroupPost>> watchPosts(String groupId, {int limit = 30}) =>
      _groups
          .doc(groupId)
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map(GroupPost.fromSnapshot).toList(),
          );

  /// ฟังสถานะสมาชิกและจำนวนสมาชิกแบบสด
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMembers(String groupId) =>
      _groups.doc(groupId).collection('members').snapshots();

  /// สถานะสมาชิกของบัญชีปัจจุบัน อ่านได้แม้เอกสารสมาชิกยังไม่มี
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMembership(
    String groupId,
  ) => _groups.doc(groupId).collection('members').doc(_uid).snapshots();

  /// คำขอของบัญชีปัจจุบัน หรือของสมาชิกที่เป็นเจ้าของกลุ่ม
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchJoinRequest(
    String groupId,
  ) => _groups.doc(groupId).collection('join_requests').doc(_uid).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchJoinRequests(
    String groupId,
  ) => _groups
      .doc(groupId)
      .collection('join_requests')
      .orderBy('createdAt')
      .snapshots();

  /// Fetches a real member count for groups created before the count field.
  Future<int> _memberCountForTransaction(
    DocumentSnapshot<Map<String, dynamic>> group,
  ) async {
    final count = group.data()?['memberCount'];
    if (count is int) return count;
    return (await group.reference.collection('members').get()).size;
  }

  /// Backfills the count for a legacy private group when its owner can read it.
  Future<void> ensureMemberCount(String groupId) async {
    final groupRef = _groups.doc(groupId);
    final group = await groupRef.get();
    final data = group.data();
    if (!group.exists || data?['memberCount'] is int) return;
    if (data?['ownerId'] != _uid) return;
    final count = (await groupRef.collection('members').get()).size;
    await groupRef.update({'memberCount': count});
  }

  /// สร้างกลุ่มและเพิ่มเจ้าของเป็นสมาชิกด้วย batch เดียว
  Future<String> createGroup({
    required String name,
    required String description,
    required String visibility,
    XFile? avatar,
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
      'memberCount': 1,
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
    if (avatar != null) {
      String? uploadedPath;
      try {
        uploadedPath = await _uploadGroupAvatar(group.id, avatar);
        await group.update({
          'avatarPath': uploadedPath,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        if (uploadedPath != null) {
          try {
            await _deleteStorageFile(uploadedPath);
          } catch (_) {}
        }
        try {
          await group.collection('members').doc(uid).delete();
          await group.delete();
        } catch (_) {
          // Preserve the original upload error if rollback is denied.
        }
        rethrow;
      }
    }
    return group.id;
  }

  /// แก้ชื่อและคำอธิบาย โดยให้ Rules ตรวจว่าเป็นเจ้าของกลุ่ม
  Future<void> updateGroup({
    required String groupId,
    required String name,
    required String description,
    XFile? avatar,
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
    final group = _groups.doc(groupId);
    final before = await group.get();
    if (!before.exists || before.data()?['isDeleting'] == true) {
      throw const GroupServiceException('กลุ่มนี้กำลังถูกลบ');
    }
    final oldAvatarPath = readOptionalString(before.data()?['avatarPath']);
    String? newAvatarPath;
    if (avatar != null) {
      newAvatarPath = await _uploadGroupAvatar(groupId, avatar);
    }
    final updates = <String, dynamic>{
      'name': cleanName,
      'description': description.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (newAvatarPath != null) updates['avatarPath'] = newAvatarPath;
    try {
      await _firestore.runTransaction((transaction) async {
        final current = await transaction.get(group);
        if (!current.exists ||
            current.data()?['isDeleting'] == true ||
            current.data()?['updatedAt'] != before.data()?['updatedAt']) {
          throw const GroupServiceException(
            'ข้อมูลกลุ่มเปลี่ยนระหว่างบันทึก กรุณาเปิดกลุ่มใหม่แล้วลองอีกครั้ง',
          );
        }
        transaction.update(group, updates);
      });
    } catch (_) {
      if (newAvatarPath != null) {
        try {
          await _deleteStorageFile(newAvatarPath);
        } catch (_) {}
      }
      rethrow;
    }
    if (newAvatarPath != null) {
      if (oldAvatarPath != null &&
          oldAvatarPath != newAvatarPath &&
          oldAvatarPath.startsWith('group_images/$groupId/')) {
        try {
          await _deleteStorageFile(oldAvatarPath);
        } catch (_) {
          // Keep the updated avatar even if the previous file cannot be removed.
        }
      }
    }
  }

  /// ลบโพสต์ สมาชิก และเอกสารกลุ่มเป็นชุด เพื่อไม่ให้ข้อมูลย่อยค้างอยู่
  Future<void> deleteGroup(String groupId) async {
    final group = _groups.doc(groupId);
    final data = await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(group);
      if (!current.exists || current.data()?['ownerId'] != _uid) {
        throw const GroupServiceException('ลบได้เฉพาะกลุ่มที่คุณเป็นเจ้าของ');
      }
      transaction.update(group, {
        'isDeleting': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return current;
    });
    final members = await group.collection('members').get();
    final posts = await group.collection('posts').get();
    final joinRequests = await group.collection('join_requests').get();
    final avatarPath = readOptionalString(data.data()?['avatarPath']);
    if (avatarPath != null && avatarPath.startsWith('group_images/$groupId/')) {
      await _deleteStorageFile(avatarPath);
    }
    for (final post in posts.docs) {
      final reactions = await post.reference.collection('reactions').get();
      for (var start = 0; start < reactions.docs.length; start += 450) {
        final batch = _firestore.batch();
        final end = (start + 450).clamp(0, reactions.docs.length);
        for (final reaction in reactions.docs.sublist(start, end)) {
          batch.delete(reaction.reference);
        }
        await batch.commit();
      }
    }
    // ลบโพสต์ก่อน เพราะการลบโพสต์ต้องอาศัยสถานะสมาชิกที่ยังมีอยู่
    for (final post in posts.docs) {
      final mediaPath = readOptionalString(post.data()['mediaPath']);
      final thumbnailPath = readOptionalString(post.data()['thumbnailPath']);
      for (final path in [mediaPath, thumbnailPath]) {
        if (path != null && path.startsWith('group_media/$groupId/')) {
          try {
            await _storage.ref(path).delete();
          } on FirebaseException catch (error) {
            if (error.code != 'object-not-found') rethrow;
          }
        }
      }
    }
    for (final documents in [posts.docs, members.docs, joinRequests.docs]) {
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

  Future<String> _uploadGroupAvatar(String groupId, XFile file) async {
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
    final mime = file.mimeType?.toLowerCase() ?? '';
    if (!mime.startsWith('image/') && !imageExtensions.contains(extension)) {
      throw const GroupServiceException('รูปกลุ่มต้องเป็นไฟล์ภาพ');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw const GroupServiceException('รูปกลุ่มต้องมีขนาดไม่เกิน 5 MB');
    }
    final safeExtension = imageExtensions.contains(extension)
        ? extension
        : 'jpg';
    final path =
        'group_images/$groupId/$_uid/avatar_${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    try {
      await _storage
          .ref(path)
          .putData(
            bytes,
            SettableMetadata(
              contentType: mime.isNotEmpty ? mime : 'image/jpeg',
            ),
          );
      return path;
    } catch (_) {
      try {
        await _deleteStorageFile(path);
      } catch (_) {}
      rethrow;
    }
  }

  /// เข้าร่วมกลุ่มสาธารณะทันทีและอัปเดตจำนวนสมาชิกใน transaction เดียวกัน
  Future<void> joinGroup(SocialGroup group) async {
    final user = _auth.currentUser;
    final uid = _uid;
    final groupRef = _groups.doc(group.id);
    final memberRef = groupRef.collection('members').doc(uid);
    final groupBefore = await groupRef.get();
    if (!groupBefore.exists || groupBefore.data()?['visibility'] != 'public') {
      throw const GroupServiceException('กลุ่มนี้เป็นส่วนตัว');
    }
    final oldCount = await _memberCountForTransaction(groupBefore);
    await _firestore.runTransaction((transaction) async {
      final currentGroup = await transaction.get(groupRef);
      final currentMember = await transaction.get(memberRef);
      if (!currentGroup.exists ||
          currentGroup.data()?['visibility'] != 'public') {
        throw const GroupServiceException('ไม่พบกลุ่มสาธารณะนี้');
      }
      if (currentMember.exists) return;
      final count = currentGroup.data()?['memberCount'] as int? ?? oldCount;
      transaction.update(groupRef, {'memberCount': count + 1});
      transaction.set(memberRef, {
        'uid': uid,
        'displayName': user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : 'สมาชิก',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// ส่งคำขอเข้ากลุ่มส่วนตัว; transaction ป้องกันคำขอซ้ำและสมาชิกซ้ำ
  Future<void> requestToJoin(SocialGroup group) async {
    final user = _auth.currentUser;
    final uid = _uid;
    final groupRef = _groups.doc(group.id);
    final memberRef = groupRef.collection('members').doc(uid);
    final requestRef = groupRef.collection('join_requests').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final currentGroup = await transaction.get(groupRef);
      final member = await transaction.get(memberRef);
      final request = await transaction.get(requestRef);
      if (!currentGroup.exists ||
          currentGroup.data()?['visibility'] != 'private') {
        throw const GroupServiceException('กลุ่มนี้ไม่ได้เปิดรับคำขอส่วนตัว');
      }
      if (currentGroup.data()?['ownerId'] == uid || member.exists) return;
      if (request.exists) {
        throw const GroupServiceException('ส่งคำขอไปแล้ว กำลังรออนุมัติ');
      }
      transaction.set(requestRef, {
        'uid': uid,
        'displayName': user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : 'สมาชิก',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// ยกเลิกได้เฉพาะคำขอของบัญชีปัจจุบัน
  Future<void> cancelJoinRequest(String groupId) async {
    final requestRef = _groups
        .doc(groupId)
        .collection('join_requests')
        .doc(_uid);
    await requestRef.delete();
  }

  /// อนุมัติคำขอด้วย owner หรือ Firebase admin claim เท่านั้น.
  Future<void> approveJoinRequest({
    required String groupId,
    required String requesterUid,
  }) async {
    final user = _auth.currentUser;
    final uid = _uid;
    final admin = (await user!.getIdTokenResult()).claims?['admin'] == true;
    final groupRef = _groups.doc(groupId);
    final memberRef = groupRef.collection('members').doc(requesterUid);
    final requestRef = groupRef.collection('join_requests').doc(requesterUid);
    final groupBefore = await groupRef.get();
    if (!groupBefore.exists) {
      throw const GroupServiceException('ไม่พบกลุ่มนี้');
    }
    final oldCount = await _memberCountForTransaction(groupBefore);

    await _firestore.runTransaction((transaction) async {
      final currentGroup = await transaction.get(groupRef);
      final request = await transaction.get(requestRef);
      final member = await transaction.get(memberRef);
      final data = currentGroup.data();
      if (!currentGroup.exists || data?['visibility'] != 'private') {
        throw const GroupServiceException('กลุ่มนี้ไม่ใช่กลุ่มส่วนตัว');
      }
      if (data?['ownerId'] != uid && !admin) {
        throw const GroupServiceException('ไม่มีสิทธิ์อนุมัติคำขอเข้ากลุ่ม');
      }
      if (!request.exists) {
        throw const GroupServiceException('คำขอนี้ไม่อยู่ในรายการแล้ว');
      }
      if (member.exists) {
        transaction.delete(requestRef);
        return;
      }
      final memberData = request.data() ?? const <String, dynamic>{};
      final count = data?['memberCount'] as int? ?? oldCount;
      transaction.update(groupRef, {'memberCount': count + 1});
      transaction.set(memberRef, {
        'uid': requesterUid,
        'displayName': memberData['displayName'] as String? ?? 'สมาชิก',
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(requestRef);
    });
  }

  /// ปฏิเสธคำขอโดยลบเอกสารคำขอ; สมาชิกยังไม่ถูกสร้าง
  Future<void> rejectJoinRequest({
    required String groupId,
    required String requesterUid,
  }) async {
    final user = _auth.currentUser;
    final uid = _uid;
    final admin = (await user!.getIdTokenResult()).claims?['admin'] == true;
    final groupRef = _groups.doc(groupId);
    final requestRef = groupRef.collection('join_requests').doc(requesterUid);
    await _firestore.runTransaction((transaction) async {
      final group = await transaction.get(groupRef);
      final request = await transaction.get(requestRef);
      if (!group.exists || (group.data()?['ownerId'] != uid && !admin)) {
        throw const GroupServiceException('ไม่มีสิทธิ์ปฏิเสธคำขอเข้ากลุ่ม');
      }
      if (request.exists) transaction.delete(requestRef);
    });
  }

  /// ออกจากกลุ่มได้ ยกเว้นเจ้าของที่ต้องโอนหรือลบกลุ่มก่อน
  Future<void> leaveGroup(SocialGroup group) async {
    final uid = _uid;
    if (group.ownerId == uid) {
      throw const GroupServiceException('เจ้าของกลุ่มไม่สามารถออกจากกลุ่มได้');
    }
    final groupRef = _groups.doc(group.id);
    final memberRef = groupRef.collection('members').doc(uid);
    final groupBefore = await groupRef.get();
    final oldCount = groupBefore.exists
        ? await _memberCountForTransaction(groupBefore)
        : 0;
    await _firestore.runTransaction((transaction) async {
      final currentGroup = await transaction.get(groupRef);
      final member = await transaction.get(memberRef);
      if (!currentGroup.exists || !member.exists) return;
      final count = currentGroup.data()?['memberCount'] as int? ?? oldCount;
      transaction.update(groupRef, {'memberCount': count > 0 ? count - 1 : 0});
      transaction.delete(memberRef);
    });
  }

  /// เพิ่มโพสต์ข้อความสั้นลงใน feed ของกลุ่ม
  Future<void> addPost({
    required String groupId,
    required String content,
    XFile? attachment,
  }) async {
    final text = content.trim();
    if ((text.isEmpty && attachment == null) || text.length > 1000) {
      throw const GroupServiceException('โพสต์ต้องมี 1–1,000 ตัวอักษร');
    }
    final user = _auth.currentUser;
    final post = _groups.doc(groupId).collection('posts').doc();
    final media = attachment == null
        ? null
        : await _uploadGroupMedia(groupId, post.id, attachment);
    try {
      await post.set({
        'authorId': _uid,
        'authorName': user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : 'สมาชิก',
        'content': text,
        'createdAt': FieldValue.serverTimestamp(),
        'mediaType': media?.type ?? 'none',
        if (media != null) 'mediaPath': media.path,
        if (media?.thumbnailPath != null) 'thumbnailPath': media!.thumbnailPath,
      });
    } catch (_) {
      if (media != null) {
        await _deleteStorageFile(media.path);
        if (media.thumbnailPath != null) {
          await _deleteStorageFile(media.thumbnailPath!);
        }
      }
      rethrow;
    }
  }

  Future<({String path, String type, String? thumbnailPath})> _uploadGroupMedia(
    String groupId,
    String postId,
    XFile file,
  ) async {
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    final mime = file.mimeType?.toLowerCase() ?? '';
    const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
    const videoExtensions = {'mp4', 'mov', 'm4v', 'webm'};
    final type =
        mime.startsWith('image/') || imageExtensions.contains(extension)
        ? 'image'
        : mime.startsWith('video/') || videoExtensions.contains(extension)
        ? 'video'
        : null;
    if (type == null) {
      throw const GroupServiceException('รองรับเฉพาะไฟล์ภาพหรือวิดีโอ');
    }

    final bytes = await file.readAsBytes();
    final maxBytes = type == 'image' ? 10 * 1024 * 1024 : 50 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw GroupServiceException(
        type == 'image'
            ? 'รูปภาพต้องมีขนาดไม่เกิน 10 MB'
            : 'วิดีโอต้องมีขนาดไม่เกิน 50 MB',
      );
    }

    final safeExtension = type == 'image'
        ? imageExtensions.contains(extension)
              ? extension
              : 'jpg'
        : videoExtensions.contains(extension)
        ? extension
        : 'mp4';
    final basePath = 'group_media/$groupId/$postId/$_uid';
    final mediaPath =
        '$basePath/media_${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    final contentType = mime.isNotEmpty
        ? mime
        : type == 'image'
        ? 'image/jpeg'
        : 'video/mp4';
    await _storage
        .ref(mediaPath)
        .putData(bytes, SettableMetadata(contentType: contentType));

    String? thumbnailPath;
    if (type == 'video' &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final thumbnail = await VideoThumbnail.thumbnailData(
          video: file.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 720,
          timeMs: 1000,
          quality: 68,
        );
        if (thumbnail != null) {
          final path =
              '$basePath/thumbnail_${DateTime.now().microsecondsSinceEpoch}.jpg';
          await _storage
              .ref(path)
              .putData(thumbnail, SettableMetadata(contentType: 'image/jpeg'));
          thumbnailPath = path;
        }
      } catch (_) {
        // The video remains usable when thumbnail generation is unavailable.
      }
    }
    return (path: mediaPath, type: type, thumbnailPath: thumbnailPath);
  }

  Future<void> _deleteStorageFile(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }
}

class GroupServiceException implements Exception {
  const GroupServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
