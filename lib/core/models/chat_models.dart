import 'package:cloud_firestore/cloud_firestore.dart';

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
  });
  final String id;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final String lastMessageText;
  final String lastMessageType;
  final String lastMessageSenderId;
  final DateTime? lastMessageAt;
  final int unreadCount;
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
    final d = s.data();
    final unread = Map<String, dynamic>.from(
      d['unreadCounts'] as Map? ?? const {},
    );
    return ConversationSummary(
      id: s.id,
      participantIds: List<String>.from(
        d['participantIds'] as List? ?? const [],
      ),
      participantNames: Map<String, String>.from(
        (d['participantNames'] as Map? ?? const {}).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      ),
      lastMessageText: d['lastMessageText'] as String? ?? '',
      lastMessageType: d['lastMessageType'] as String? ?? 'text',
      lastMessageSenderId: d['lastMessageSenderId'] as String? ?? '',
      lastMessageAt: _dateFrom(d['lastMessageAt']),
      unreadCount: (unread[uid] as num?)?.toInt() ?? 0,
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
  });
  final String id;
  final String senderId;
  final String type;
  final String text;
  final DateTime? createdAt;
  final String? mediaPath;
  factory ChatMessage.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> s,
  ) {
    final d = s.data();
    return ChatMessage(
      id: s.id,
      senderId: d['senderId'] as String? ?? '',
      type: d['type'] as String? ?? 'text',
      text: d['text'] as String? ?? '',
      createdAt: _dateFrom(d['createdAt']),
      mediaPath: d['mediaPath'] as String?,
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
  });
  final String id;
  final String actorId;
  final String actorName;
  final String type;
  final String body;
  final DateTime? createdAt;
  final bool isRead;
  final String? conversationId;
  factory AppNotification.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> s,
  ) {
    final d = s.data();
    return AppNotification(
      id: s.id,
      actorId: d['actorId'] as String? ?? '',
      actorName: d['actorName'] as String? ?? 'สมาชิก',
      type: d['type'] as String? ?? 'message',
      body: d['body'] as String? ?? '',
      createdAt: _dateFrom(d['createdAt']),
      isRead: d['isRead'] as bool? ?? false,
      conversationId: d['conversationId'] as String?,
    );
  }
}
