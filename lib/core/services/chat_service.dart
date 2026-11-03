import 'trusted_service.dart';

// จัดการการสนทนา ข้อความ การอ่านแล้ว/ยังไม่อ่าน และไฟล์แนบของบัญชีปัจจุบัน
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/chat_models.dart';
import '../utils/document_values.dart';

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
    if (u == null) {
      throw const ChatServiceException('กรุณาเข้าสู่ระบบก่อนใช้แชท');
    }
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

  // คนที่ลบแชทจะเห็นเฉพาะข้อความใหม่ ส่วนอีกฝ่ายยังเห็นประวัติเดิม
  Stream<List<ChatMessage>> watchMessages(String id, {int limit = 100}) {
    final uid = _uid;
    final room = _conversations.doc(id);
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    roomSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    messagesSubscription;
    Timestamp? cutoff;
    var listeningToMessages = false;
    var generation = 0;
    var session = 0;
    late final StreamController<List<ChatMessage>> controller;

    controller = StreamController<List<ChatMessage>>.broadcast(
      onListen: () {
        final activeSession = ++session;
        roomSubscription = room.snapshots().listen((snapshot) async {
          if (activeSession != session) return;
          final value = readMap(snapshot.data()?['clearedAt'])[uid];
          final nextCutoff = value is Timestamp ? value : null;
          if (listeningToMessages && nextCutoff == cutoff) return;
          if (listeningToMessages && nextCutoff != cutoff) {
            // อีกเครื่องลบแชทอยู่: เอาข้อความเก่าออกก่อนเริ่ม query ใหม่
            controller.add(const <ChatMessage>[]);
          }
          cutoff = nextCutoff;
          listeningToMessages = true;
          final currentGeneration = ++generation;
          await messagesSubscription?.cancel();
          if (controller.isClosed ||
              activeSession != session ||
              currentGeneration != generation) {
            return;
          }

          Query<Map<String, dynamic>> query = room
              .collection('messages')
              .orderBy('createdAt');
          if (nextCutoff != null) {
            query = query.where('createdAt', isGreaterThan: nextCutoff);
          }
          messagesSubscription = query
              .limitToLast(limit)
              .snapshots()
              .listen(
                (snapshot) {
                  if (currentGeneration != generation || controller.isClosed) {
                    return;
                  }
                  controller.add(
                    snapshot.docs.map(ChatMessage.fromSnapshot).toList(),
                  );
                },
                onError: (Object error, StackTrace stackTrace) {
                  if (!controller.isClosed && currentGeneration == generation) {
                    controller.addError(error, stackTrace);
                  }
                },
              );
        }, onError: controller.addError);
      },
      onCancel: () async {
        session++;
        generation++;
        listeningToMessages = false;
        final oldRoom = roomSubscription;
        final oldMessages = messagesSubscription;
        roomSubscription = null;
        messagesSubscription = null;
        await oldRoom?.cancel();
        await oldMessages?.cancel();
      },
    );
    return controller.stream;
  }

  /// สร้าง ID เดิมให้คู่สมาชิกเดิมเสมอ และใช้ transaction ป้องกันห้องซ้ำ
  Future<String> openConversation({
    required String peerId,
    required String peerName,
  }) async {
    final uid = _uid;
    if (uid == peerId) {
      throw const ChatServiceException('ไม่สามารถเริ่มแชทกับบัญชีตัวเองได้');
    }
    final ids = [uid, peerId]..sort();
    final id = base64Url
        .encode(utf8.encode('${ids[0]}|${ids[1]}'))
        .replaceAll('=', '');
    final ref = _conversations.doc(id);
    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) {
        // ห้องที่เคยลบในแอปรุ่นเก่ามีแค่ hiddenFor; เติมจุดตัดประวัติครั้งแรก
        if (readMap(existing.data()?['hiddenFor'])[uid] == true &&
            readMap(existing.data()?['clearedAt'])[uid] is! Timestamp) {
          tx.update(ref, {
            FieldPath(['hiddenFor', uid]): true,
            FieldPath(['clearedAt', uid]): FieldValue.serverTimestamp(),
            FieldPath(['unreadCounts', uid]): 0,
            FieldPath(['lastReadAt', uid]): FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        // เปิดจากโปรไฟล์ได้ แต่ห้องยังไม่กลับเข้ารายการจนมีข้อความใหม่
        return;
      }
      final followsPeer = await tx.get(
        _firestore
            .collection('users')
            .doc(peerId)
            .collection('followers')
            .doc(uid),
      );
      if (!followsPeer.exists) {
        throw const ChatServiceException('ติดตามบัญชีนี้ก่อนเริ่มส่งข้อความ');
      }
      final me = _auth.currentUser!;
      final name = me.displayName?.trim();
      tx.set(ref, {
        'participantIds': ids,
        'participantNames': {
          uid: boundedString(
            name == null || name.isEmpty ? 'สมาชิก' : name,
            60,
          ),
          peerId: boundedString(readName(peerName), 60),
        },
        'unreadCounts': {uid: 0, peerId: 0},
        'lastReadAt': {uid: FieldValue.serverTimestamp()},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return id;
  }

  /// ลบประวัติที่บัญชีนี้มองเห็น โดยไม่แตะข้อความที่อีกฝ่ายยังเก็บไว้
  Future<void> hideConversation(String conversationId) async {
    final uid = _uid;
    await _conversations.doc(conversationId).update({
      FieldPath(['hiddenFor', uid]): true,
      FieldPath(['clearedAt', uid]): FieldValue.serverTimestamp(),
      FieldPath(['unreadCounts', uid]): 0,
      FieldPath(['lastReadAt', uid]): FieldValue.serverTimestamp(),
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
    String? mediaPath;
    final thumbnailPath = message.thumbnailPath;
    await _firestore.runTransaction((transaction) async {
      final room = await transaction.get(conversationRef);
      final stored = await transaction.get(messageRef);
      if (!stored.exists || stored.data()?['senderId'] != uid) {
        throw const ChatServiceException('ไม่พบข้อความที่คุณส่ง');
      }
      if (stored.data()?['type'] == 'deleted') return;
      mediaPath = readOptionalString(stored.data()?['mediaPath']);
      transaction.update(messageRef, {
        'type': 'deleted',
        'text': 'ยกเลิกข้อความนี้',
        'mediaPath': FieldValue.delete(),
        'sharedPostId': FieldValue.delete(),
        'deletedAt': FieldValue.serverTimestamp(),
      });
      // A concurrent send changes the room version, causing this transaction
      // to retry rather than replacing a newer message preview.
      if (room.data()?['lastMessageId'] == message.id) {
        transaction.update(conversationRef, {
          'lastMessageText': 'ยกเลิกข้อความนี้',
          'lastMessageType': 'deleted',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    if (mediaPath != null) {
      try {
        await _deleteMedia(mediaPath!);
      } catch (_) {
        // ยกเลิกข้อความสำเร็จแล้ว แม้ลบไฟล์แนบไม่สำเร็จก็ไม่ย้อนผลการยกเลิก
      }
    }
    if (thumbnailPath != null) {
      try {
        await _deleteMedia(thumbnailPath);
      } catch (_) {
        // The unsent message stays removed if optional preview cleanup fails.
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
    if (user == null) {
      throw const ChatServiceException('กรุณาเข้าสู่ระบบก่อนใช้แชท');
    }
    final body = text.trim();
    if (body.isEmpty && attachment == null) return;
    if (body.length > 2000) {
      throw const ChatServiceException('ข้อความต้องไม่เกิน 2,000 ตัวอักษร');
    }
    final msg = _conversations.doc(conversationId).collection('messages').doc();
    final ticket = await TrustedService.reserve(_firestore, msg.path);
    String? path;
    String? thumbnailPath;
    var type = 'text';
    if (attachment != null) {
      final m = await _uploadAttachment(conversationId, attachment);
      path = m.path;
      type = m.type;
      thumbnailPath = m.thumbnailPath;
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
    if (ticket != null) batch.delete(ticket);
    batch.set(msg, {
      'senderId': user.uid,
      'type': type,
      'text': body,
      'mediaPath': ?path,
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
      FieldPath(['hiddenFor', peerId]): false,
    });
    try {
      await batch.commit();
    } catch (_) {
      for (final uploadedPath in [path, thumbnailPath]) {
        if (uploadedPath == null) continue;
        try {
          await _deleteMedia(uploadedPath);
        } catch (_) {
          // Cleanup errors should not hide the original message-send failure.
        }
      }
      rethrow;
    }
  }

  // ตรวจชนิดและขนาดไฟล์ก่อนอัปโหลด; path ต้องตรงกับ storage.rules
  Future<({String path, String type, String? thumbnailPath})> _uploadAttachment(
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
    if (type == null) {
      throw const ChatServiceException('รองรับเฉพาะไฟล์ภาพหรือวิดีโอ');
    }
    final max = type == 'image' ? 10 * 1024 * 1024 : 50 * 1024 * 1024;
    if (await file.length() > max) {
      throw ChatServiceException(
        type == 'image'
            ? 'ภาพต้องมีขนาดไม่เกิน 10 MB'
            : 'วิดีโอต้องมีขนาดไม่เกิน 50 MB',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > max) {
      throw const ChatServiceException('ไฟล์มีขนาดใหญ่เกินกำหนด');
    }
    final uid = _uid;
    final mediaId = DateTime.now().microsecondsSinceEpoch;
    final thumbnailBytes = type == 'video'
        ? await _createVideoThumbnail(file.path)
        : null;
    String? thumbnailPath;
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      thumbnailPath = 'chat_media/$convId/$uid/thumbnail_$mediaId.jpg';
      try {
        await _storage
            .ref(thumbnailPath)
            .putData(
              thumbnailBytes,
              SettableMetadata(contentType: 'image/jpeg'),
            );
      } catch (_) {
        // ถ้าเก็บภาพปกไม่สำเร็จ ห้องแชทจะใช้เฟรมแรกที่หยุดนิ่งแทน
        try {
          await _deleteMedia(thumbnailPath);
        } catch (_) {
          // ไฟล์ภาพปกที่ค้างไว้ลบภายหลังได้
        }
        thumbnailPath = null;
      }
    }
    final name = 'media_$mediaId${thumbnailPath == null ? '' : '_thumb'}.$ext';
    final path = 'chat_media/$convId/$uid/$name';
    try {
      await _storage
          .ref(path)
          .putData(
            bytes,
            SettableMetadata(contentType: file.mimeType ?? ('$type/$ext')),
          );
    } catch (_) {
      if (thumbnailPath != null) {
        try {
          await _deleteMedia(thumbnailPath);
        } catch (_) {
          // เก็บ error ตอนอัปโหลดวิดีโอไว้ แม้ลบภาพปกไม่สำเร็จ
        }
      }
      rethrow;
    }
    return (path: path, type: type, thumbnailPath: thumbnailPath);
  }

  // สร้างภาพปกบนมือถือ ถ้าทำไม่ได้ วิดีโอยังส่งได้และจะแสดงเฟรมแรกแทน
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
        // ใช้เฟรมแรก เผื่อคลิปสั้นจนไม่มีเฟรมที่ 1 วินาที
        timeMs: 0,
        quality: 68,
      );
    } catch (_) {
      return null;
    }
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
