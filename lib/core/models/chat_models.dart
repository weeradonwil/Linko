// โมเดลแปลงข้อมูล conversations และ messages จาก Firestore ให้หน้าจอใช้งานได้สะดวก
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/document_values.dart';

// Firestore serverTimestamp จะกลายเป็น Timestamp; รองรับ DateTime ระหว่างทดสอบด้วย
DateTime? _dateFrom(dynamic v) => v is Timestamp
    ? v.toDate()
    : v is DateTime
    ? v
    : null;

/// ข้อมูลสรุปจาก conversations สำหรับรายการแชทและจำนวนข้อความที่ยังไม่อ่าน
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.participantIds,
    required this.participantNames,
    required this.lastMessageText,
    required this.lastMessageType,
    required this.lastMessageSenderId,
    required this.lastMessageAt,
    required this.unreadCount,
    this.isHidden = false,
  });
  final String id;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final String lastMessageText;
  final String lastMessageType;
  final String lastMessageSenderId;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isHidden;
  String peerId(String uid) =>
      participantIds.firstWhere((id) => id != uid, orElse: () => '');
  String peerName(String uid) {
    final n = participantNames[peerId(uid)]?.trim();
    return n == null || n.isEmpty ? 'สมาชิก' : n;
  }

  factory ConversationSummary.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> s,
    String uid,
  ) {
    return ConversationSummary.fromData(s.id, s.data(), uid);
  }

  factory ConversationSummary.fromData(
    String id,
    Map<String, dynamic> d,
    String uid,
  ) {
    final unread = readMap(d['unreadCounts']);
    return ConversationSummary(
      id: id,
      participantIds: readStrings(d['participantIds']),
      participantNames: Map<String, String>.from(
        readMap(d['participantNames'])
            .map((k, v) => MapEntry(k.toString(), v.toString())),
      ),
      lastMessageText: readString(d['lastMessageText']),
      lastMessageType: readString(d['lastMessageType'], 'text'),
      lastMessageSenderId: readString(d['lastMessageSenderId']),
      lastMessageAt: _dateFrom(d['lastMessageAt']),
      unreadCount: readCount(unread[uid]),
      isHidden: readMap(d['hiddenFor'])[uid] == true,
    );
  }
}

/// ข้อความใน conversations/{conversationId}/messages; mediaPath ชี้ไปยังไฟล์ใน Storage
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.type,
    required this.text,
    required this.createdAt,
    this.mediaPath,
    this.isUnsent = false,
  });
  final String id;
  final String senderId;
  final String type;
  final String text;
  final DateTime? createdAt;
  final String? mediaPath;
  final bool isUnsent;
  factory ChatMessage.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> s,
  ) {
    final d = s.data();
    return ChatMessage(
      id: s.id,
      senderId: readString(d['senderId']),
      type: readString(d['type'], 'text'),
      text: readString(d['text']),
      createdAt: _dateFrom(d['createdAt']),
      mediaPath: readOptionalString(d['mediaPath']),
      isUnsent: d['type'] == 'deleted',
    );
  }
}

/// การแจ้งเตือนจาก notifications โดย recipientId เป็นเจ้าของรายการ
class AppNotification {
  const AppNotification({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.type,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.conversationId,
    this.postId,
    this.commentId,
    this.groupId,
  });
  final String id;
  final String actorId;
  final String actorName;
  final String type;
  final String body;
  final DateTime? createdAt;
  final bool isRead;
  final String? conversationId;
  final String? postId;
  final String? commentId;
  final String? groupId;
  factory AppNotification.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> s,
  ) {
    final d = s.data();
    return AppNotification(
      id: s.id,
      actorId: readString(d['actorId']),
      actorName: readName(d['actorName']),
      type: readString(d['type'], 'message'),
      body: readString(d['body']),
      createdAt: _dateFrom(d['createdAt']),
      isRead: d['isRead'] == true,
      conversationId: readOptionalString(d['conversationId']),
      postId: readOptionalString(d['postId']),
      commentId: readOptionalString(d['commentId']),
      groupId: readOptionalString(d['groupId']),
    );
  }
}
