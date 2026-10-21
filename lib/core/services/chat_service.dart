// จัดการการสนทนา ข้อความ การอ่านแล้ว/ยังไม่อ่าน และไฟล์แนบของบัญชีปัจจุบัน
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_models.dart';

/// รวมการอ่าน/เขียนห้องแชท ข้อความ และไฟล์แนบของผู้ใช้ที่ล็อกอิน
class ChatService {
  /// รับ Firebase instance แยกได้ เพื่อทดสอบหลายบัญชีกับ Emulator โดยใช้ service ตัวจริง
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
              .where((conversation) => !conversation.isHidden)
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
      if ((await tx.get(ref)).exists) {
        // เปิดห้องเดิมด้วย false ซ้ำได้; Rules ต้องไม่บังคับว่า hiddenFor ต้องเปลี่ยนค่า
        tx.update(ref, {
          FieldPath(['hiddenFor', uid]): false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
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

  /// ซ่อนห้องแชทเฉพาะบัญชีนี้ โดยเก็บข้อความของทั้งสองฝ่ายไว้ในห้องเดิม
  Future<void> hideConversation(String conversationId) async {
    final uid = _uid;
    await _conversations.doc(conversationId).update({
      FieldPath(['hiddenFor', uid]): true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// แทนข้อความที่ส่งด้วยสถานะยกเลิกที่ผู้ร่วมสนทนาทั้งสองฝ่ายเห็น
  Future<void> unsendMessage({
    required String conversationId,
    required ChatMessage message,
  }) async {
    final uid = _uid;
    if (message.senderId != uid || message.isUnsent) {
      throw const ChatServiceException('ยกเลิกได้เฉพาะข้อความที่คุณส่ง');
    }
    final conversationRef = _conversations.doc(conversationId);
    final messageRef = conversationRef.collection('messages').doc(message.id);
    final batch = _firestore.batch();
    batch.update(messageRef, {
      'type': 'deleted',
      'text': 'ยกเลิกข้อความนี้',
      'mediaPath': FieldValue.delete(),
      'deletedAt': FieldValue.serverTimestamp(),
    });
    final latestMessages = await conversationRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (latestMessages.docs.isNotEmpty &&
        latestMessages.docs.first.id == message.id) {
      batch.update(conversationRef, {
        'lastMessageText': 'ยกเลิกข้อความนี้',
        'lastMessageType': 'deleted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    if (message.mediaPath != null) {
      try {
        await _deleteMedia(message.mediaPath!);
      } catch (_) {
        // ยกเลิกข้อความสำเร็จแล้ว แม้ลบไฟล์แนบไม่สำเร็จก็ไม่ย้อนผลการยกเลิก
      }
    }
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

  /// บันทึกข้อความ ตัวอย่างห้อง และตัวนับยังไม่อ่านใน batch เดียว
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
    // เขียน batch ได้ทันทีโดยไม่อ่าน conversation ซ้ำก่อนส่ง; Firestore Rules
    // ตรวจสมาชิกและปฏิเสธ batch หากห้องหรือผู้ใช้ไม่มีสิทธิ์ ช่วยลดหนึ่งรอบเครือข่าย
    final ref = _conversations.doc(conversationId);
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
    // แสดงกิจกรรมแชทผ่าน unread ของห้อง ไม่สร้างรายการ social notification
    // คนเดิมส่งต่อหรือส่งข้อความซ้ำได้; Rules ตรวจค่าจริง ไม่บังคับให้ทุก field ต่างจากเดิม
    batch.update(ref, {
      'lastMessageText': preview,
      'lastMessageType': type,
      'lastMessageSenderId': user.uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageId': msg.id,
      'updatedAt': FieldValue.serverTimestamp(),
      FieldPath(['unreadCounts', peerId]): FieldValue.increment(1),
      FieldPath(['unreadCounts', user.uid]): 0,
      FieldPath(['lastReadAt', user.uid]): FieldValue.serverTimestamp(),
      FieldPath(['hiddenFor', user.uid]): false,
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

  /// ลบไฟล์แนบที่ไม่ใช้งานแล้ว; ถ้าไฟล์ถูกลบไปก่อนถือว่างานสำเร็จ
  Future<void> _deleteMedia(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}

/// ข้อผิดพลาดตามเงื่อนไขของแชทที่เตรียมข้อความสำหรับแสดงให้ผู้ใช้แล้ว
class ChatServiceException implements Exception {
  const ChatServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
