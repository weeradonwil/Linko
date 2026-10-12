import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

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
    return _posts
        .where(
          Filter.or(
            Filter('visibility', isEqualTo: 'public'),
            // Firestore Rules รับรองได้ว่าผลลัพธ์มีเฉพาะโพสต์ public
            // หรือโพสต์ที่เจ้าของตรงกับบัญชีปัจจุบัน
            Filter('userId', isEqualTo: userId),
          ),
        )
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Post.fromSnapshot).toList());
  }

  /// เพิ่มฟิลด์ใหม่ให้โพสต์เก่าของเจ้าของ โดยคงโพสต์เดิมไว้เป็นสาธารณะเหมือนเดิม
  /// วิธีนี้ทำให้ข้อมูลเก่ายังใช้กับ schema ใหม่ได้หลังติดตั้ง Firestore Rules ชุดนี้
  Future<void> normalizeOwnedPosts() async {
    final userId = _currentUser.uid;
    final snapshot = await _posts.where('userId', isEqualTo: userId).get();
    final postsNeedingUpdate = snapshot.docs.where(
      (document) =>
          !document.data().containsKey('visibility') ||
          !document.data().containsKey('tags') ||
          !document.data().containsKey('mediaType'),
    );

    // Firestore จำกัดจำนวนการเขียนต่อ batch; แบ่งชุดละ 400 รายการ
    final documents = postsNeedingUpdate.toList();
    for (var start = 0; start < documents.length; start += 400) {
      final batch = _firestore.batch();
      final end = (start + 400).clamp(0, documents.length);
      for (final document in documents.sublist(start, end)) {
        final data = document.data();
        batch.update(document.reference, {
          if (!data.containsKey('visibility')) 'visibility': 'public',
          if (!data.containsKey('tags')) 'tags': <String>[],
          if (!data.containsKey('mediaType')) 'mediaType': 'none',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  /// Schema ของ posts/{postId}: userId, authorName, content, tags, visibility,
  /// createdAt, updatedAt, mediaType (none/image/video) และ mediaPath (ถ้ามีสื่อ)
  Future<void> createPost({
    required String content,
    required List<String> tags,
    required String visibility,
    XFile? attachment,
  }) async {
    final user = _currentUser;
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
        'visibility': _cleanVisibility(visibility),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'mediaType': media?.type ?? 'none',
        if (media != null) ...{
          'mediaPath': media.path,
        },
      });
    } catch (_) {
      // ถ้าบันทึกข้อมูลโพสต์ไม่ได้ ให้ลบไฟล์ที่เพิ่งอัปโหลดเพื่อไม่ทิ้งไฟล์กำพร้า
      if (media != null) await _deleteStorageFile(media.path);
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
    XFile? newAttachment,
    bool removeMedia = false,
  }) async {
    final ownerUid = _currentUser.uid;
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
        'visibility': _cleanVisibility(visibility),
        'updatedAt': FieldValue.serverTimestamp(),
        if (newMedia != null) ...{
          'mediaPath': newMedia.path,
          'mediaType': newMedia.type,
        },
        if (removeMedia) ...{
          'mediaPath': FieldValue.delete(),
          'mediaType': 'none',
        },
      });
    } catch (_) {
      if (newMedia != null) {
        await _deleteStorageFile(newMedia.path);
      }
      rethrow;
    }

    // ลบสื่อเก่าหลัง Firestore เปลี่ยนไปใช้ไฟล์ใหม่เรียบร้อยแล้ว
    if ((newMedia != null || removeMedia) &&
        oldMediaPath != null &&
        _belongsToPost(oldMediaPath, ownerUid, postId)) {
      await _deleteStorageFile(oldMediaPath);
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

  Future<({String path, String type})> _uploadAttachment(
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
    // ตั้งชื่อไฟล์ใหม่ทุกครั้ง เพื่อให้การแทนสื่อไม่เขียนทับ path เก่าก่อน update สำเร็จ
    final uniqueName =
        'media_${DateTime.now().microsecondsSinceEpoch}.$extension';
    final path = 'post_media/$userId/$postId/$uniqueName';
    final reference = _storage.ref(path);
    await reference.putData(bytes, SettableMetadata(contentType: contentType));

    return (path: path, type: type);
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

/// ข้อผิดพลาดที่ตรวจพบก่อนส่งข้อมูลหรืออัปโหลดไป Firebase
class PostServiceException implements Exception {
  const PostServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
