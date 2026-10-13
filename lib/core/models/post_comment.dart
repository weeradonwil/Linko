import 'package:cloud_firestore/cloud_firestore.dart';

/// A comment stored under posts/{postId}/comments/{commentId}.
class PostComment {
  const PostComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime? createdAt;

  factory PostComment.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final timestamp = data['createdAt'];
    return PostComment(
      id: snapshot.id,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'สมาชิก',
      content: data['content'] as String? ?? '',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}
