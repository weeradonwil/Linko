import 'trusted_service.dart';

// รวมการเข้าถึง posts และ post_reports รวมถึงอัปโหลด/ลบสื่อที่เป็นของโพสต์
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/post.dart';
import '../models/post_policy.dart';
import '../utils/document_values.dart';
import '../utils/avatar_thumbnail.dart';

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
  DocumentReference<Map<String, dynamic>>? _pendingCreateRef;

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

  /// อ่านโพสต์สาธารณะพร้อมโพสต์ส่วนตัวของผู้ใช้ปัจจุบัน เรียงใหม่ไปเก่า
  /// Filter.or ทำให้เงื่อนไขที่ส่งไป Firestore ตรงกับสิทธิ์ใน Rules
  Stream<List<Post>> watchFeed({int limit = 30}) {
    final userId = _currentUser.uid;
    late final StreamController<List<Post>> controller;
    final sources = <String, Map<String, Post>>{};
    final fixed = <StreamSubscription<dynamic>>[];
    final followed = <StreamSubscription<dynamic>>[];
    var cancelled = false;
    var generation = 0;

    void emit() {
      if (cancelled) return;
      final merged = <String, Post>{};
      for (final source in sources.values) {
        merged.addAll(source);
      }
      final posts =
          merged.values
              .where(
                (p) =>
                    (p.isDeleting && p.userId == userId) ||
                    (!p.isDeleting && p.hasVisibleContent),
              )
              .toList()
            // Home stays chronological; popularity ranking belongs to Explore.
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(posts.take(limit).toList());
    }

    StreamSubscription<dynamic> attach(
      String key,
      Query<Map<String, dynamic>> query, {
      int? version,
    }) => query.snapshots().listen(
      (snapshot) {
        if (cancelled || (version != null && version != generation)) return;
        sources[key] = {
          for (final doc in snapshot.docs) doc.id: Post.fromSnapshot(doc),
        };
        emit();
      },
      onError: (Object error, StackTrace stack) {
        if (!cancelled && (version == null || version == generation)) {
          controller.addError(FeedQueryException(key, error), stack);
        }
      },
    );
    controller = StreamController<List<Post>>(
      onListen: () {
        fixed.add(
          attach(
            'public',
            _posts
                .where('visibility', isEqualTo: 'public')
                .where('authorIsPrivate', isEqualTo: false)
                .orderBy('createdAt', descending: true)
                .limit(limit),
          ),
        );
        fixed.add(
          attach(
            'own',
            _posts
                .where('userId', isEqualTo: userId)
                .orderBy('createdAt', descending: true)
                .limit(limit),
          ),
        );
        fixed.add(
          _firestore
              .collection('users')
              .doc(userId)
              .collection('following')
              .snapshots()
              .listen(
                (snapshot) async {
                  final version = ++generation;
                  final previous = List<StreamSubscription<dynamic>>.of(
                    followed,
                  );
                  followed.clear();
                  await Future.wait(previous.map((s) => s.cancel()));
                  if (cancelled || version != generation) return;
                  sources.removeWhere((key, _) => key.startsWith('follow:'));
                  // Five authors per query keeps Rules document lookups below the
                  // single-query limit, and reduces the number of live listeners.
                  final ids = snapshot.docs.map((d) => d.id).toList();
                  for (var i = 0; i < ids.length; i += 5) {
                    final batch = ids.skip(i).take(5).toList();
                    followed.add(
                      attach(
                        'follow:$i',
                        _posts
                            .where('userId', whereIn: batch)
                            .where('visibility', isEqualTo: 'followers')
                            .where('authorIsPrivate', isEqualTo: false)
                            .orderBy('createdAt', descending: true)
                            .limit(limit),
                        version: version,
                      ),
                    );
                  }
                  emit();
                },
                onError: (Object error, StackTrace stack) {
                  if (!cancelled) {
                    controller.addError(
                      FeedQueryException('following-list', error),
                      stack,
                    );
                  }
                },
              ),
        );
      },
      onCancel: () async {
        cancelled = true;
        generation++;
        await Future.wait([...fixed, ...followed].map((s) => s.cancel()));
      },
    );
    return controller.stream;
  }

  /// Account privacy changes independently from post audiences.
  Future<void> updateProfilePrivacy(bool isPrivate) async {
    final userId = _currentUser.uid;
    final userRef = _firestore.collection('users').doc(userId);
    final current = (await userRef.get()).data() ?? const <String, dynamic>{};
    if ((current['isPrivate'] == true) == isPrivate &&
        current['privacyMigrationTarget'] is! bool &&
        current['privacyTarget'] is! bool) {
      // Even an unchanged setting can repair post snapshots left by an older app.
      await _migratePostAudiences(userId, isPrivate);
      if (isPrivate) await _securePrivateAvatar(userRef);
      return;
    }

    if (isPrivate) {
      // Hide each post before the profile is marked private. If migration stops,
      // the profile remains public and the next app start can safely resume it.
      await userRef.update({'privacyMigrationTarget': true});
      await _migratePostAudiences(userId, true);
      await _securePrivateAvatar(userRef, force: true);
      await userRef.update({
        'isPrivate': true,
        'privacyTarget': FieldValue.delete(),
        'privacyMigrationTarget': FieldValue.delete(),
      });
    } else {
      // Opening the profile can only reveal posts as their public ACL is restored.
      await userRef.update({
        'isPrivate': false,
        'avatarPrivateSecured': false,
        'privacyMigrationTarget': false,
      });
      await _migratePostAudiences(userId, false);
      await userRef.update({
        'privacyMigrationTarget': FieldValue.delete(),
        'privacyTarget': FieldValue.delete(),
      });
    }
  }

  /// เพิ่มฟิลด์ใหม่ให้โพสต์เก่าของเจ้าของ โดยคงโพสต์เดิมไว้เป็นสาธารณะเหมือนเดิม
  /// วิธีนี้ทำให้ข้อมูลเก่ายังใช้กับ schema ใหม่ได้หลังติดตั้ง Firestore Rules ชุดนี้
  Future<void> normalizeOwnedPosts() async {
    final userId = _currentUser.uid;
    final userSnapshot = await _firestore.collection('users').doc(userId).get();
    final data = userSnapshot.data() ?? const <String, dynamic>{};
    final migrationTarget = data['privacyMigrationTarget'];
    if (migrationTarget is bool) {
      await updateProfilePrivacy(migrationTarget);
      return;
    }
    final pending = data['privacyTarget'];
    if (pending is bool) {
      await updateProfilePrivacy(pending);
      return;
    }
    await _migratePostAudiences(userId, data['isPrivate'] == true);
    if (data['isPrivate'] == true) {
      await _securePrivateAvatar(userSnapshot.reference);
    }
  }

  // The thumbnail stays visible in cards. Replacing the old full object also
  // invalidates any download URL issued while this account was public.
  Future<void> _securePrivateAvatar(
    DocumentReference<Map<String, dynamic>> userRef, {
    bool force = false,
  }) async {
    final profile = (await userRef.get()).data() ?? const <String, dynamic>{};
    final uid = _currentUser.uid;
    final oldPath = readOptionalString(profile['avatarPath']);
    if (oldPath == null || !oldPath.startsWith('profile_images/$uid/')) return;
    final oldThumb = readOptionalString(profile['avatarThumbPath']);
    if (!force && profile['avatarPrivateSecured'] == true && oldThumb != null) {
      return;
    }
    final original = _storage.ref(oldPath);
    final bytes = await original.getData(5 * 1024 * 1024);
    if (bytes == null) {
      throw const PostServiceException('ย้ายรูปโปรไฟล์ก่อนเปิดบัญชีส่วนตัวไม่สำเร็จ');
    }
    String? newThumb;
    String? newPath;
    try {
      if (oldThumb == null) {
        newThumb = 'profile_thumbnails/$uid/avatar_${DateTime.now().microsecondsSinceEpoch}.png';
        await _storage.ref(newThumb).putData(
          await makeAvatarThumbnail(bytes),
          SettableMetadata(contentType: 'image/png'),
        );
      }
      newPath = 'profile_images/$uid/avatar_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final metadata = await original.getMetadata();
      await _storage.ref(newPath).putData(
        bytes,
        SettableMetadata(contentType: metadata.contentType ?? 'image/jpeg'),
      );
      await userRef.update({
        'avatarPath': newPath,
        'avatarThumbPath': ?newThumb,
      });
      await original.delete();
      await userRef.update({'avatarPrivateSecured': true});
    } catch (_) {
      // If the profile already points to the new path, the next login retries
      // the migration marker. Do not delete an object referenced by the profile.
      final currentPath = (await userRef.get()).data()?['avatarPath'];
      if (currentPath != newPath && newPath != null) {
        try { await _storage.ref(newPath).delete(); } catch (_) {}
      }
      if (currentPath != newPath && newThumb != null) {
        try { await _storage.ref(newThumb).delete(); } catch (_) {}
      }
      rethrow;
    }
  }

  // Update the author privacy snapshot without changing each post's audience.
  Future<void> _migratePostAudiences(String userId, bool isPrivate) async {
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> query = _posts
          .where('userId', isEqualTo: userId)
          .orderBy(FieldPath.documentId)
          .limit(200);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query.get();
      if (page.docs.isEmpty) return;
      // Re-read each document in a transaction so migration cannot replace
      // tags or audiences edited by another device after the query returned.
      for (var offset = 0; offset < page.docs.length; offset += 8) {
        await Future.wait(
          page.docs
              .skip(offset)
              .take(8)
              .map(
                (document) => _firestore.runTransaction((transaction) async {
                  final current = await transaction.get(document.reference);
                  if (!current.exists ||
                      current.data()?['isDeleting'] == true) {
                    return;
                  }
                  final data = current.data()!;
                  final post = Post.fromSnapshot(current);
                  final tags = _cleanTags(post.tags);
                  final updates = <String, dynamic>{
                    if (data['authorIsPrivate'] != isPrivate)
                      'authorIsPrivate': isPrivate,
                    if (!listEquals(
                          data['tags'] is List
                              ? data['tags'] as List
                              : const [],
                          tags,
                        ) ||
                        data['tags'] is! List)
                      'tags': tags,
                    if (data['mediaType'] != post.mediaType)
                      'mediaType': post.mediaType,
                  };
                  if (updates.isNotEmpty) {
                    updates['updatedAt'] = FieldValue.serverTimestamp();
                    transaction.update(document.reference, updates);
                  }
                }),
              ),
        );
      }
      cursor = page.docs.last;
      if (page.docs.length < 200) return;
    }
  }

  /// Schema ของ posts/{postId}: ข้อมูลโพสต์ เวลา mediaType และ path สื่อ/ภาพปก
  Future<void> createPost({
    required String content,
    required List<String> tags,
    required String visibility,
    XFile? attachment,
    List<String> taggedUserIds = const [],
  }) async {
    final user = _currentUser;
    final ownerProfile = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    final isPrivateProfile = PostPolicy.profileIsPrivate(
      ownerProfile.data() ?? const {},
    );
    final effectiveVisibility = _cleanVisibility(visibility);
    final cleanContent = content.trim();
    if (cleanContent.length > 1000) {
      throw const PostServiceException('โพสต์ต้องไม่เกิน 1,000 ตัวอักษร');
    }
    if (cleanContent.isEmpty && attachment == null) {
      throw const PostServiceException('กรุณาใส่ข้อความหรือแนบภาพ/วิดีโอ');
    }

    // Keep the same document ID when this composer retries a failed save.
    // reserveWrite can then reuse its ticket instead of consuming another slot.
    final postRef = _pendingCreateRef ??= _posts.doc();
    final ticket = await TrustedService.reserve(
      _firestore,
      postRef.path,
      taggedUserIds: taggedUserIds,
    );
    final media = attachment == null
        ? null
        : await _uploadAttachment(postRef.id, attachment);
    final name = user.displayName?.trim();

    try {
      final create = _firestore.batch();
      create.set(postRef, {
        'userId': user.uid,
        'authorName': (name == null || name.isEmpty) ? 'สมาชิก' : name,
        'content': cleanContent,
        'tags': _cleanTags(tags),
        'taggedUserIds': taggedUserIds,
        'visibility': effectiveVisibility,
        'authorIsPrivate': isPrivateProfile,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'mediaType': media?.type ?? 'none',
        if (media != null) ...{'mediaPath': media.path},
        if (media?.thumbnailPath != null) 'thumbnailPath': media!.thumbnailPath,
      });
      if (ticket != null) create.delete(ticket);
      await create.commit();
      _pendingCreateRef = null;
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
    List<String> taggedUserIds = const [],
  }) async {
    final ownerUid = _currentUser.uid;
    final ownerProfile = await _firestore
        .collection('users')
        .doc(ownerUid)
        .get();
    final isPrivateProfile = PostPolicy.profileIsPrivate(
      ownerProfile.data() ?? const {},
    );
    final effectiveVisibility = _cleanVisibility(visibility);
    final cleanContent = content.trim();
    if (cleanContent.length > 1000 || (removeMedia && newAttachment != null)) {
      throw const PostServiceException('กรุณาตรวจความยาวข้อความและไฟล์แนบ');
    }
    final existing = await _posts.doc(postId).get();
    if (!existing.exists || existing.data()?['userId'] != ownerUid) {
      throw const PostServiceException('แก้ไขได้เฉพาะโพสต์ของคุณ');
    }
    if (existing.data()?['isDeleting'] == true) {
      throw const PostServiceException(
        'โพสต์นี้กำลังถูกลบ กรุณาดำเนินการลบให้เสร็จ',
      );
    }
    final hasMedia =
        newAttachment != null ||
        (!removeMedia &&
            readOptionalString(existing.data()?['mediaPath']) != null);
    final previousMediaPath = readOptionalString(existing.data()?['mediaPath']);
    final previousThumbnailPath = readOptionalString(
      existing.data()?['thumbnailPath'],
    );
    if (!PostPolicy.hasContent(
      cleanContent,
      hasMedia: hasMedia || existing.data()?['sharedPostId'] is String,
    )) {
      throw const PostServiceException('กรุณาใส่ข้อความหรือแนบภาพ/วิดีโอ');
    }

    final ticket = await TrustedService.reserve(
      _firestore,
      existing.reference.path,
      taggedUserIds: taggedUserIds,
      update: true,
    );
    final newMedia = newAttachment == null
        ? null
        : await _uploadAttachment(postId, newAttachment);

    try {
      await _firestore.runTransaction((transaction) async {
        final current = await transaction.get(existing.reference);
        if (!current.exists ||
            current.data()?['isDeleting'] == true ||
            current.data()?['updatedAt'] != existing.data()?['updatedAt'] ||
            current.data()?['mediaPath'] != previousMediaPath ||
            current.data()?['thumbnailPath'] != previousThumbnailPath) {
          throw const PostServiceException(
            'โพสต์ถูกเปลี่ยนแปลงระหว่างบันทึก กรุณาเปิดโพสต์ใหม่แล้วลองอีกครั้ง',
          );
        }
        transaction.update(existing.reference, {
          'content': cleanContent,
          'tags': _cleanTags(tags),
          'taggedUserIds': taggedUserIds,
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
        if (ticket != null) transaction.delete(ticket);
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
      if (previousMediaPath != null &&
          _belongsToPost(previousMediaPath, ownerUid, postId)) {
        await _deleteStorageFile(previousMediaPath);
      }
      if (previousThumbnailPath != null &&
          _belongsToPost(previousThumbnailPath, ownerUid, postId)) {
        await _deleteStorageFile(previousThumbnailPath);
      }
    }
  }

  /// ลบไฟล์แนบก่อน แล้วจึงลบเอกสารโพสต์
  Future<void> deletePost(Post post) async {
    final user = _currentUser;
    if (post.userId != user.uid) {
      throw const PostServiceException('ลบได้เฉพาะโพสต์ของบัญชีที่เข้าสู่ระบบ');
    }
    final reference = _posts.doc(post.id);
    final data = await _beginPostDeletion(reference);
    if (data == null) return;
    final mediaPath = readOptionalString(data['mediaPath']);
    if (mediaPath != null && _belongsToPost(mediaPath, user.uid, post.id)) {
      await _deleteStorageFile(mediaPath);
    }
    final thumbnailPath = readOptionalString(data['thumbnailPath']);
    if (thumbnailPath != null &&
        _belongsToPost(thumbnailPath, user.uid, post.id)) {
      await _deleteStorageFile(thumbnailPath);
    }
    await _deletePostChildren(reference);
    await reference.delete();
  }

  Future<Map<String, dynamic>?> _beginPostDeletion(
    DocumentReference<Map<String, dynamic>> reference,
  ) => _firestore.runTransaction((transaction) async {
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists) return null;
    transaction.update(reference, {
      'isDeleting': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return snapshot.data();
  });

  Future<void> _deletePostChildren(
    DocumentReference<Map<String, dynamic>> post,
  ) async {
    for (final name in ['comments', 'reactions']) {
      while (true) {
        final page = await post.collection(name).limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final document in page.docs) {
          batch.delete(document.reference);
        }
        await batch.commit();
      }
    }
  }

  /// บันทึกรายงานหนึ่งรายการต่อผู้ใช้ต่อโพสต์ ป้องกันการส่งซ้ำโดยไม่ตั้งใจ
  Future<bool> reportPost({
    required Post post,
    required String reason,
    String details = '',
    bool hidePost = true,
  }) async {
    final result = await TrustedService.call('submitReport', {
      'postId': post.id,
      'reason': reason,
      'details': details,
    }, app: _firestore.app);
    if (hidePost) {
      await _firestore
          .collection('users')
          .doc(_currentUser.uid)
          .collection('hidden_posts')
          .doc(post.id)
          .set({'createdAt': FieldValue.serverTimestamp()});
    }
    return result['alreadyReported'] == true;
  }

  /// Removes a reported post and its media and child documents for an admin.
  Future<void> removeReportedPost(String postId) async {
    final user = _currentUser;
    final token = await user.getIdTokenResult(true);
    if (token.claims?['admin'] != true) {
      throw const PostServiceException('Administrator access is required.');
    }

    final postReference = _posts.doc(postId);
    final data = await _beginPostDeletion(postReference);
    if (data == null) return;
    for (final path in [
      readOptionalString(data['mediaPath']),
      readOptionalString(data['thumbnailPath']),
    ]) {
      if (path != null &&
          path.startsWith('post_media/${data['userId']}/$postId/')) {
        await _deleteStorageFile(path);
      }
    }

    await _deletePostChildren(postReference);
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
      .where((tag) => tag.isNotEmpty && tag.length <= 150)
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
