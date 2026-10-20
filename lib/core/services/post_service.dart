// รวมการเข้าถึง posts และ post_reports รวมถึงอัปโหลด/ลบสื่อที่เป็นของโพสต์
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/post.dart';

/// จัดการสร้าง อ่าน แก้ไข และลบโพสต์
/// หน้าจอเรียก service นี้แทนการติดต่อ Firebase โดยตรง
class PostService {
  PostService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  /// ใช้ UID จาก Firebase Auth ปัจจุบันเสมอ ไม่เชื่อ UID ที่ส่งมาจาก widget
  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) {
      throw const PostServiceException('กรุณาเข้าสู่ระบบก่อนดำเนินการ');
    }
    return user;
  }

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('post_reports');

  /// อ่านโพสต์สาธารณะพร้อมโพสต์ส่วนตัวของผู้ใช้ปัจจุบัน เรียงใหม่ไปเก่า
  /// Filter.or ทำให้เงื่อนไขที่ส่งไป Firestore ตรงกับสิทธิ์ใน Rules
  Stream<List<Post>> watchFeed() {
    final userId = _currentUser.uid;
    final controller = StreamController<List<Post>>();
    final sourcePosts = <String, Map<String, Post>>{};
    final subscriptions = <StreamSubscription<dynamic>>[];
    final followedSubscriptions = <StreamSubscription<dynamic>>[];

    void emitPosts() {
      final merged = <String, Post>{};
      for (final source in sourcePosts.values) {
        merged.addAll(source);
      }
      final result = merged.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (result.length > 100) result.removeRange(100, result.length);
      if (!controller.isClosed) controller.add(result);
    }

    void reportFeedError(String sourceId, Object error, StackTrace stackTrace) {
      debugPrint('Feed query [$sourceId] failed: $error');
      if (!controller.isClosed) {
        controller.addError(FeedQueryException(sourceId, error), stackTrace);
      }
    }

    void attach(String sourceId, Query<Map<String, dynamic>> query) {
      subscriptions.add(
        query.snapshots().listen(
          (snapshot) {
            sourcePosts[sourceId] = {
              for (final doc in snapshot.docs) doc.id: Post.fromSnapshot(doc),
            };
            emitPosts();
          },
          onError: (Object error, StackTrace stackTrace) {
            reportFeedError(sourceId, error, stackTrace);
          },
        ),
      );
    }

    attach(
      'public',
      _posts
          .where('visibility', isEqualTo: 'public')
          .orderBy('createdAt', descending: true)
          .limit(50),
    );
    attach('own', _posts.where('userId', isEqualTo: userId).limit(50));

    subscriptions.add(
      _firestore
          .collection('users')
          .doc(userId)
          .collection('following')
          .snapshots()
          .listen(
            (following) async {
              await Future.wait(
                followedSubscriptions.map(
                  (subscription) => subscription.cancel(),
                ),
              );
              followedSubscriptions.clear();
              sourcePosts.removeWhere((key, _) => key.startsWith('follow:'));
              for (final followed in following.docs) {
                final sourceId = 'follow:${followed.id}';
                final subscription = _posts
                    .where('userId', isEqualTo: followed.id)
                    .where('visibility', isEqualTo: 'followers')
                    .orderBy('createdAt', descending: true)
                    .limit(30)
                    .snapshots()
                    .listen(
                      (snapshot) {
                        sourcePosts[sourceId] = {
                          for (final doc in snapshot.docs)
                            doc.id: Post.fromSnapshot(doc),
                        };
                        emitPosts();
                      },
                      onError: (Object error, StackTrace stackTrace) {
                        reportFeedError(sourceId, error, stackTrace);
                      },
                    );
                followedSubscriptions.add(subscription);
              }
              emitPosts();
            },
            onError: (Object error, StackTrace stackTrace) {
              reportFeedError('following-list', error, stackTrace);
            },
          ),
    );

    controller.onCancel = () async {
      await Future.wait([
        ...subscriptions.map((subscription) => subscription.cancel()),
        ...followedSubscriptions.map((subscription) => subscription.cancel()),
      ]);
    };
    return controller.stream;
  }

  /// Updates account privacy and affected post audiences in one atomic batch.
  Future<void> updateProfilePrivacy(bool isPrivate) async {
    final userId = _currentUser.uid;
    final userRef = _firestore.collection('users').doc(userId);
    final userSnapshot = await userRef.get();
    final wasPrivate = userSnapshot.data()?['isPrivate'] == true;
    if (wasPrivate == isPrivate) return;

    final snapshot = await _posts.where('userId', isEqualTo: userId).get();
    final affected = snapshot.docs.where((post) {
      final data = post.data();
      final visibility = data['visibility'] as String? ?? 'public';
      final targetVisibility = isPrivate && visibility == 'public'
          ? 'followers'
          : !isPrivate && visibility == 'followers'
          ? 'public'
          : visibility;
      return targetVisibility != visibility ||
          data['authorIsPrivate'] != isPrivate ||
          !data.containsKey('visibility');
    }).toList();
    if (affected.length > 499) {
      throw const PostServiceException(
        'Too many posts to change profile privacy in one atomic update.',
      );
    }

    final batch = _firestore.batch();
    for (final post in affected) {
      batch.update(post.reference, {
        'visibility':
            isPrivate && (post.data()['visibility'] ?? 'public') == 'public'
            ? 'followers'
            : !isPrivate && post.data()['visibility'] == 'followers'
            ? 'public'
            : post.data()['visibility'] ?? (isPrivate ? 'followers' : 'public'),
        'authorIsPrivate': isPrivate,
      });
    }
    batch.update(userRef, {'isPrivate': isPrivate});
    await batch.commit();
  }

  /// เพิ่มฟิลด์ใหม่ให้โพสต์เก่าของเจ้าของ โดยคงโพสต์เดิมไว้เป็นสาธารณะเหมือนเดิม
  /// วิธีนี้ทำให้ข้อมูลเก่ายังใช้กับ schema ใหม่ได้หลังติดตั้ง Firestore Rules ชุดนี้
  Future<void> normalizeOwnedPosts() async {
    final userId = _currentUser.uid;
    final userSnapshot = await _firestore.collection('users').doc(userId).get();
    final isPrivateProfile = userSnapshot.data()?['isPrivate'] == true;
    final snapshot = await _posts.where('userId', isEqualTo: userId).get();
    final postsNeedingUpdate = snapshot.docs.where(
      (document) =>
          !document.data().containsKey('visibility') ||
          !document.data().containsKey('tags') ||
          !document.data().containsKey('mediaType') ||
          document.data()['authorIsPrivate'] != isPrivateProfile ||
          (isPrivateProfile && document.data()['visibility'] == 'public'),
    );

    // Firestore จำกัดจำนวนการเขียนต่อ batch; แบ่งชุดละ 400 รายการ
    final documents = postsNeedingUpdate.toList();
    for (var start = 0; start < documents.length; start += 400) {
      final batch = _firestore.batch();
      final end = (start + 400).clamp(0, documents.length);
      for (final document in documents.sublist(start, end)) {
        final data = document.data();
        batch.update(document.reference, {
          if (!data.containsKey('visibility') ||
              (isPrivateProfile && data['visibility'] == 'public'))
            'visibility': isPrivateProfile ? 'followers' : 'public',
          'authorIsPrivate': isPrivateProfile,
          if (!data.containsKey('tags')) 'tags': <String>[],
          if (!data.containsKey('mediaType')) 'mediaType': 'none',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  /// Schema ของ posts/{postId}: ข้อมูลโพสต์ เวลา mediaType และ path สื่อ/ภาพปก
  Future<void> createPost({
    required String content,
    required List<String> tags,
    required String visibility,
    XFile? attachment,
  }) async {
    final user = _currentUser;
    final ownerProfile = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    final isPrivateProfile = ownerProfile.data()?['isPrivate'] == true;
    final effectiveVisibility = isPrivateProfile && visibility == 'public'
        ? 'followers'
        : _cleanVisibility(visibility);
    final cleanContent = content.trim();
    if (cleanContent.isEmpty && attachment == null) {
      throw const PostServiceException('กรุณาใส่ข้อความหรือแนบภาพ/วิดีโอ');
    }

    final postRef = _posts.doc();
    final media = attachment == null
        ? null
        : await _uploadAttachment(postRef.id, attachment);
    final name = user.displayName?.trim();

    try {
      await postRef.set({
        'userId': user.uid,
        'authorName': (name == null || name.isEmpty) ? 'สมาชิก' : name,
        'content': cleanContent,
        'tags': _cleanTags(tags),
        'visibility': effectiveVisibility,
        'authorIsPrivate': isPrivateProfile,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'mediaType': media?.type ?? 'none',
        if (media != null) ...{'mediaPath': media.path},
        if (media?.thumbnailPath != null) 'thumbnailPath': media!.thumbnailPath,
      });
    } catch (_) {
      // ถ้าบันทึกข้อมูลโพสต์ไม่ได้ ให้ลบไฟล์ที่เพิ่งอัปโหลดเพื่อไม่ทิ้งไฟล์กำพร้า
      if (media != null) {
        await _deleteStorageFile(media.path);
        if (media.thumbnailPath != null) {
          await _deleteStorageFile(media.thumbnailPath!);
        }
      }
      rethrow;
    }
  }

  /// แก้ข้อความ แท็ก การมองเห็น และสื่อ โดยคงเจ้าของกับเวลาเดิมไว้
  Future<void> updatePost({
    required String postId,
    required String content,
    required List<String> tags,
    required String visibility,
    required String? oldMediaPath,
    required String? oldThumbnailPath,
    XFile? newAttachment,
    bool removeMedia = false,
  }) async {
    final ownerUid = _currentUser.uid;
    final ownerProfile = await _firestore
        .collection('users')
        .doc(ownerUid)
        .get();
    final isPrivateProfile = ownerProfile.data()?['isPrivate'] == true;
    final effectiveVisibility = isPrivateProfile && visibility == 'public'
        ? 'followers'
        : _cleanVisibility(visibility);
    final cleanContent = content.trim();
    if (cleanContent.isEmpty && newAttachment == null && !removeMedia) {
      throw const PostServiceException('กรุณาใส่ข้อความหรือแนบภาพ/วิดีโอ');
    }

    final newMedia = newAttachment == null
        ? null
        : await _uploadAttachment(postId, newAttachment);

    try {
      await _posts.doc(postId).update({
        'content': cleanContent,
        'tags': _cleanTags(tags),
        'visibility': effectiveVisibility,
        'authorIsPrivate': isPrivateProfile,
        'updatedAt': FieldValue.serverTimestamp(),
        // Keep an explicit marker so old updatedAt migration values do not look edited.
        'editedAt': FieldValue.serverTimestamp(),
        if (newMedia != null) ...{
          'mediaPath': newMedia.path,
          'mediaType': newMedia.type,
          if (newMedia.thumbnailPath != null)
            'thumbnailPath': newMedia.thumbnailPath
          else
            'thumbnailPath': FieldValue.delete(),
        },
        if (removeMedia) ...{
          'mediaPath': FieldValue.delete(),
          'mediaType': 'none',
          'thumbnailPath': FieldValue.delete(),
        },
      });
    } catch (_) {
      if (newMedia != null) {
        await _deleteStorageFile(newMedia.path);
        if (newMedia.thumbnailPath != null) {
          await _deleteStorageFile(newMedia.thumbnailPath!);
        }
      }
      rethrow;
    }

    // ลบสื่อเก่าหลัง Firestore เปลี่ยนไปใช้ไฟล์ใหม่เรียบร้อยแล้ว
    if (newMedia != null || removeMedia) {
      if (oldMediaPath != null &&
          _belongsToPost(oldMediaPath, ownerUid, postId)) {
        await _deleteStorageFile(oldMediaPath);
      }
      if (oldThumbnailPath != null &&
          _belongsToPost(oldThumbnailPath, ownerUid, postId)) {
        await _deleteStorageFile(oldThumbnailPath);
      }
    }
  }

  /// ลบไฟล์แนบก่อน แล้วจึงลบเอกสารโพสต์
  Future<void> deletePost(Post post) async {
    final user = _currentUser;
    if (post.userId != user.uid) {
      throw const PostServiceException('ลบได้เฉพาะโพสต์ของบัญชีที่เข้าสู่ระบบ');
    }
    final mediaPath = post.mediaPath;
    if (mediaPath != null && _belongsToPost(mediaPath, user.uid, post.id)) {
      await _deleteStorageFile(mediaPath);
    }
    final thumbnailPath = post.thumbnailPath;
    if (thumbnailPath != null &&
        _belongsToPost(thumbnailPath, user.uid, post.id)) {
      await _deleteStorageFile(thumbnailPath);
    }
    await _posts.doc(post.id).delete();
  }

  /// บันทึกรายงานหนึ่งรายการต่อผู้ใช้ต่อโพสต์ ป้องกันการส่งซ้ำโดยไม่ตั้งใจ
  Future<void> reportPost({
    required Post post,
    required String reason,
    String details = '',
  }) async {
    final reporter = _currentUser;
    final reportId = '${post.id}_${reporter.uid}';
    await _reports.doc(reportId).set({
      'postId': post.id,
      'postOwnerId': post.userId,
      'reporterUid': reporter.uid,
      'reason': reason,
      'details': details.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes a reported post and its media and child documents for an admin.
  Future<void> removeReportedPost(String postId) async {
    final user = _currentUser;
    final token = await user.getIdTokenResult(true);
    if (token.claims?['admin'] != true) {
      throw const PostServiceException('Administrator access is required.');
    }

    final postReference = _posts.doc(postId);
    final snapshot = await postReference.get();
    if (!snapshot.exists) return;
    final data = snapshot.data()!;
    for (final path in [
      data['mediaPath'] as String?,
      data['thumbnailPath'] as String?,
    ]) {
      if (path != null &&
          path.startsWith('post_media/${data['userId']}/$postId/')) {
        await _deleteStorageFile(path);
      }
    }

    for (final childCollection in ['comments', 'reactions']) {
      final children = await postReference.collection(childCollection).get();
      for (var start = 0; start < children.docs.length; start += 450) {
        final batch = _firestore.batch();
        final end = (start + 450).clamp(0, children.docs.length);
        for (final child in children.docs.sublist(start, end)) {
          batch.delete(child.reference);
        }
        await batch.commit();
      }
    }
    await postReference.delete();
  }

  Future<({String path, String type, String? thumbnailPath})> _uploadAttachment(
    String postId,
    XFile file,
  ) async {
    final userId = _currentUser.uid;
    final type = _mediaTypeForFile(file);
    final isImage = type == 'image';
    final maxBytes = isImage ? 10 * 1024 * 1024 : 50 * 1024 * 1024;
    // ตรวจขนาดก่อนอ่านไฟล์เข้าหน่วยความจำ แล้วตรวจซ้ำกับ bytes ที่อัปโหลดจริง
    // เพื่อปฏิเสธไฟล์ใหญ่ตั้งแต่ต้นและกันกรณีขนาดไฟล์เปลี่ยนระหว่างอ่าน
    if (await file.length() > maxBytes) {
      throw PostServiceException(
        isImage
            ? 'ภาพต้องมีขนาดไม่เกิน 10 MB'
            : 'วิดีโอต้องมีขนาดไม่เกิน 50 MB',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw PostServiceException(
        isImage
            ? 'ภาพต้องมีขนาดไม่เกิน 10 MB'
            : 'วิดีโอต้องมีขนาดไม่เกิน 50 MB',
      );
    }

    final extension = _fileExtension(file.name, isImage ? 'jpg' : 'mp4');
    final contentType = file.mimeType ?? _contentTypeForExtension(extension);
    // สร้างภาพตัวอย่างเฉพาะบน Android/iOS; แพลตฟอร์มอื่นยังอัปโหลดวิดีโอได้
    final thumbnailBytes = isImage
        ? null
        : await _createVideoThumbnail(file.path);
    // ตั้งชื่อไฟล์ใหม่ทุกครั้ง เพื่อให้การแทนสื่อไม่เขียนทับ path เก่าก่อน update สำเร็จ
    final uniqueName =
        'media_${DateTime.now().microsecondsSinceEpoch}.$extension';
    final path = 'post_media/$userId/$postId/$uniqueName';
    final reference = _storage.ref(path);
    await reference.putData(bytes, SettableMetadata(contentType: contentType));

    String? thumbnailPath;
    if (thumbnailBytes != null) {
      final thumbnailName =
          'thumbnail_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final candidatePath = 'post_media/$userId/$postId/$thumbnailName';
      try {
        await _storage
            .ref(candidatePath)
            .putData(
              thumbnailBytes,
              SettableMetadata(contentType: 'image/jpeg'),
            );
        thumbnailPath = candidatePath;
      } catch (_) {
        // ภาพปกเป็นส่วนเสริม; เก็บวิดีโอได้แม้สร้างหรืออัปโหลดภาพปกไม่สำเร็จ
        await _deleteStorageFile(candidatePath);
      }
    }

    return (path: path, type: type, thumbnailPath: thumbnailPath);
  }

  /// สร้าง JPEG ขนาดเล็กจากเฟรมแรกที่มีภาพ เพื่อลดเวลารอเฟรมจากวิดีโอจริง
  Future<Uint8List?> _createVideoThumbnail(String videoPath) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        timeMs: 1000,
        quality: 68,
      );
    } catch (_) {
      // ถอดเฟรมไม่ได้ก็ยังอัปโหลดวิดีโอต้นฉบับต่อได้
      return null;
    }
  }

  Future<void> _deleteStorageFile(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (error) {
      // ลบไฟล์ที่ไม่มีอยู่แล้วถือว่าสำเร็จ; error อื่นส่งต่อเพื่อแจ้งผู้ใช้
      if (error.code != 'object-not-found') rethrow;
    }
  }

  List<String> _cleanTags(List<String> tags) => tags
      .map((tag) => tag.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .take(5)
      .toList();

  String _cleanVisibility(String visibility) =>
      visibility == 'private' ? 'private' : 'public';

  /// ป้องกันไฟล์ที่ไม่ใช่ภาพ/วิดีโอ และป้องกัน MIME type ขัดกับนามสกุลไฟล์
  String _mediaTypeForFile(XFile file) {
    final extension = _fileExtension(file.name, '').toLowerCase();
    const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
    const videoExtensions = {'mp4', 'mov', 'm4v', 'webm'};
    final extensionType = imageExtensions.contains(extension)
        ? 'image'
        : videoExtensions.contains(extension)
        ? 'video'
        : null;
    final mimeType = file.mimeType?.toLowerCase();
    final mimeTypeCategory = mimeType?.startsWith('image/') == true
        ? 'image'
        : mimeType?.startsWith('video/') == true
        ? 'video'
        : null;

    if (extensionType == null ||
        (mimeType != null && mimeTypeCategory == null) ||
        (mimeTypeCategory != null && mimeTypeCategory != extensionType)) {
      throw const PostServiceException('รองรับเฉพาะไฟล์ภาพหรือวิดีโอที่กำหนด');
    }
    return extensionType;
  }

  String _contentTypeForExtension(String extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'mov' => 'video/quicktime',
    'm4v' => 'video/x-m4v',
    'webm' => 'video/webm',
    _ => 'video/mp4',
  };

  bool _belongsToPost(String path, String userId, String postId) =>
      path.startsWith('post_media/$userId/$postId/');

  String _fileExtension(String name, String fallback) {
    final match = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(name);
    return match?.group(1)?.toLowerCase() ?? fallback;
  }
}

/// Adds the Firestore query source to an error so feed access failures are
/// easier to distinguish between public, own, following, and followed posts.
class FeedQueryException implements Exception {
  const FeedQueryException(this.sourceId, this.cause);

  final String sourceId;
  final Object cause;

  @override
  String toString() => '[$sourceId] $cause';
}

/// ข้อผิดพลาดที่ตรวจพบก่อนส่งข้อมูลหรืออัปโหลดไป Firebase
class PostServiceException implements Exception {
  const PostServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
