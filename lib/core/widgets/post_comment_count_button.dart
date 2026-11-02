import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'post_action_button.dart';

/// อ่านยอดจาก comments จริง ไม่พึ่งตัวเลขที่แอปเขียนเองลงในโพสต์
class PostCommentCountButton extends StatefulWidget {
  const PostCommentCountButton({
    super.key,
    required this.postId,
    required this.onPressed,
    this.groupId,
  });

  final String postId;
  final String? groupId;
  final Future<void> Function() onPressed;

  @override
  State<PostCommentCountButton> createState() => _PostCommentCountButtonState();
}

class _PostCommentCountButtonState extends State<PostCommentCountButton> {
  late Future<int> _count = _loadCount();

  Future<int> _loadCount() async {
    final firestore = FirebaseFirestore.instance;
    final post = widget.groupId == null
        ? firestore.collection('posts').doc(widget.postId)
        : firestore
              .collection('groups')
              .doc(widget.groupId)
              .collection('posts')
              .doc(widget.postId);
    final result = await post.collection('comments').count().get();
    return result.count ?? 0;
  }

  Future<void> _openComments() async {
    await widget.onPressed();
    if (mounted) setState(() => _count = _loadCount());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _count,
    builder: (context, snapshot) => PostActionButton(
      icon: Icons.mode_comment_outlined,
      label: 'ความคิดเห็น',
      badgeCount: snapshot.data ?? 0,
      onPressed: _openComments,
    ),
  );
}
