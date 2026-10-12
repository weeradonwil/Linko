import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_models.dart';

/// รวมการอ่าน/เขียนห้องแชท ข้อความ และไฟล์แนบของผู้ใช้ที่ล็อกอิน
class ChatService {
  ChatService({
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
    final u = _auth.currentUser;
    if (u == null)
      throw const ChatServiceException('กรุณาเข้าสู่ระบบก่อนใช้แชท');
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');
  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');
  // โหลดเฉพาะห้องของผู้ใช้ แล้วเรียงตามเวลาข้อความล่าสุด
  Stream<List<ConversationSummary>> watchConversations() {
    final uid = _uid;
    return _conversations
        .where('participantIds', arrayContains: uid)
        .snapshots()
        .map((s) {
          final items = s.docs
              .where(
                (d) => (d.data()['participantIds'] as List? ?? []).length == 2,
              )
              .map((d) => ConversationSummary.fromSnapshot(d, uid))
              .toList();
          items.sort(
            (a, b) =>
                (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                    .compareTo(
                      a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                    ),
          );
          return items;
        });
  }

  // ฟัง 100 ข้อความล่าสุดและเรียงตามเวลาส่งจากเก่าไปใหม่
  Stream<List<ChatMessage>> watchMessages(String id) => _conversations
      .doc(id)
      .collection('messages')
      .orderBy('createdAt')
      .limitToLast(100)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromSnapshot).toList());
  /// สร้าง ID เดิมให้คู่สมาชิกเดิมเสมอ และใช้ transaction ป้องกันห้องซ้ำ
  Future<String> openConversation({
    required String peerId,
    required String peerName,
  }) async {
    final uid = _uid;
    if (uid == peerId)
      throw const ChatServiceException('ไม่สามารถเริ่มแชทกับบัญชีตัวเองได้');
    final ids = [uid, peerId]..sort();
    final id = base64Url
        .encode(utf8.encode(ids[0] + '|' + ids[1]))
        .replaceAll('=', '');
    final ref = _conversations.doc(id);
    await _firestore.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) return;
      final me = _auth.currentUser!;
      final name = me.displayName?.trim();
      tx.set(ref, {
        'participantIds': ids,
        'participantNames': {
          uid: name == null || name.isEmpty ? 'สมาชิก' : name,
          peerId: peerName.trim().isEmpty ? 'สมาชิก' : peerName.trim(),
        },
        'unreadCounts': {uid: 0, peerId: 0},
        'lastReadAt': {uid: FieldValue.serverTimestamp()},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return id;
  }

  // เก็บเวลาอ่านและจำนวนที่ยังไม่อ่านแยกตาม UID ของผู้ใช้แต่ละคน
  Future<void> markRead(String id) async {
    final uid = _uid;
    await _conversations.doc(id).update({
      FieldPath(['unreadCounts', uid]): 0,
      FieldPath(['lastReadAt', uid]): FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// บันทึกข้อความ อัปเดตตัวอย่างห้อง และสร้างแจ้งเตือนใน batch เดียว
  /// หาก batch ล้มเหลว จะลบไฟล์ที่อัปโหลดค้างไว้เพื่อลดไฟล์กำพร้า
  Future<void> sendMessage({
    required String conversationId,
    required String peerId,
    String text = '',
    XFile? attachment,
  }) async {
    final user = _auth.currentUser;
    if (user == null)
      throw const ChatServiceException('กรุณาเข้าสู่ระบบก่อนใช้แชท');
    final body = text.trim();
    if (body.isEmpty && attachment == null) return;
    String? path;
    var type = 'text';
    if (attachment != null) {
      final m = await _uploadAttachment(conversationId, attachment);
      path = m.path;
      type = m.type;
    }
    final ref = _conversations.doc(conversationId);
    final conv = await ref.get();
    final ids = List<String>.from(
      conv.data()?['participantIds'] as List? ?? const [],
    );
    if (!conv.exists || !ids.contains(user.uid) || !ids.contains(peerId)) {
      if (path != null) await _deleteMedia(path);
      throw const ChatServiceException(
        'ไม่พบห้องสนทนาหรือไม่มีสิทธิ์ส่งข้อความ',
      );
    }
    final preview = body.isNotEmpty
        ? body
        : type == 'image'
        ? 'ส่งรูปภาพให้คุณ'
        : 'ส่งวิดีโอให้คุณ';
    final batch = _firestore.batch();
    final msg = ref.collection('messages').doc();
    batch.set(msg, {
      'senderId': user.uid,
      'type': type,
      'text': body,
      if (path != null) 'mediaPath': path,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {
      'lastMessageText': preview,
      'lastMessageType': type,
      'lastMessageSenderId': user.uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      FieldPath(['unreadCounts', peerId]): FieldValue.increment(1),
      FieldPath(['unreadCounts', user.uid]): 0,
      FieldPath(['lastReadAt', user.uid]): FieldValue.serverTimestamp(),
    });
    final notice = _notifications.doc();
    batch.set(notice, {
      'recipientId': peerId,
      'actorId': user.uid,
      'actorName': user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'สมาชิก',
      'type': 'message',
      'body': preview,
      'conversationId': conversationId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } catch (_) {
      if (path != null) await _deleteMedia(path);
      rethrow;
    }
  }

  // ตรวจชนิดและขนาดไฟล์ก่อนอัปโหลด; path ต้องตรงกับ storage.rules
  Future<({String path, String type})> _uploadAttachment(
    String convId,
    XFile file,
  ) async {
    final ext = file.name.split('.').last.toLowerCase();
    const images = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
    const videos = {'mp4', 'mov', 'm4v', 'webm'};
    final type = images.contains(ext)
        ? 'image'
        : videos.contains(ext)
        ? 'video'
        : null;
    if (type == null)
      throw const ChatServiceException('รองรับเฉพาะไฟล์ภาพหรือวิดีโอ');
    final max = type == 'image' ? 10 * 1024 * 1024 : 50 * 1024 * 1024;
    if (await file.length() > max)
      throw ChatServiceException(
        type == 'image'
            ? 'ภาพต้องมีขนาดไม่เกิน 10 MB'
            : 'วิดีโอต้องมีขนาดไม่เกิน 50 MB',
      );
    final bytes = await file.readAsBytes();
    if (bytes.length > max)
      throw const ChatServiceException('ไฟล์มีขนาดใหญ่เกินกำหนด');
    final uid = _uid;
    final name =
        'media_' + DateTime.now().microsecondsSinceEpoch.toString() + '.' + ext;
    final path = 'chat_media/' + convId + '/' + uid + '/' + name;
    await _storage
        .ref(path)
        .putData(
          bytes,
          SettableMetadata(contentType: file.mimeType ?? (type + '/' + ext)),
        );
    return (path: path, type: type);
  }

  Future<void> _deleteMedia(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}

class ChatServiceException implements Exception {
  const ChatServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
