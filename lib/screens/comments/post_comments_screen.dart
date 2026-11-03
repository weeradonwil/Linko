import '../../core/widgets/content_visibility.dart';

// หน้าความคิดเห็นของโพสต์ แสดงรายการสดและเปิดให้สมาชิกเพิ่ม/ลบคอมเมนต์ของตน
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/models/post.dart';
import '../../core/models/post_comment.dart';
import '../../core/services/comment_service.dart';
import '../../core/utils/firebase_error_message.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/post_stats_bar.dart';
import '../../core/widgets/tagged_post_content.dart';
import '../profile/profile.dart';

/// แสดงความคิดเห็นของโพสต์ฟีดหลักหรือกลุ่ม โดย CommentService เลือกตำแหน่งและ Rules ที่ตรงกัน
class PostCommentsScreen extends StatefulWidget {
  const PostCommentsScreen({
    super.key,
    required this.user,
    required this.post,
    this.groupId,
  });

  final User user;
  final Post post;
  final String? groupId;

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  final _service = CommentService();
  final _textController = TextEditingController();
  bool _sending = false;
  int _limit = 50;
  int _statsRefreshKey = 0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final result = await _service.addComment(
        post: widget.post,
        content: _textController.text,
        groupId: widget.groupId,
      );
      if (!mounted) return;
      _textController.clear();
      setState(() => _statsRefreshKey++);
      if (!result.notificationsComplete && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.groupId != null
                  ? 'ส่งความคิดเห็นแล้ว แต่แจ้งเจ้าของโพสต์ไม่สำเร็จ'
                  : result.eligibleFollowers == null
                  ? 'ส่งความคิดเห็นแล้ว แต่โหลดรายชื่อผู้ติดตามเพื่อแจ้งเตือนไม่สำเร็จ'
                  : 'ส่งความคิดเห็นแล้ว แต่แจ้งเตือนผู้ติดตามได้ ${result.notifiedFollowers}/${result.eligibleFollowers} คน',
            ),
          ),
        );
      }
      if (mounted) FocusScope.of(context).unfocus();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is CommentServiceException
                  ? error.message
                  : firebaseErrorMessage(error, action: 'ส่งความคิดเห็น'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(PostComment comment) async {
    try {
      await _service.deleteComment(
        postId: widget.post.id,
        commentId: comment.id,
        groupId: widget.groupId,
      );
      if (mounted) setState(() => _statsRefreshKey++);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is CommentServiceException
                  ? error.message
                  : firebaseErrorMessage(error, action: 'ลบความคิดเห็น'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ความคิดเห็น')),
      body: Column(
        children: [
          _PostPreview(post: widget.post, viewer: widget.user),
          PostStatsBar(
            post: widget.post,
            groupId: widget.groupId,
            refreshKey: _statsRefreshKey,
          ),
          Expanded(
            child: StreamBuilder<List<PostComment>>(
              stream: _service.watchComments(
                widget.post.id,
                limit: _limit,
                groupId: widget.groupId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        firebaseErrorMessage(
                          snapshot.error,
                          action: 'โหลดความคิดเห็น',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final comments = snapshot.data ?? const <PostComment>[];
                if (comments.isEmpty) {
                  return Center(
                    child: Text(
                      'ยังไม่มีความคิดเห็น เริ่มพูดคุยได้เลย',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount:
                      comments.length + (comments.length >= _limit ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    if (comments.length >= _limit && index == 0) {
                      return TextButton(
                        onPressed: () => setState(() => _limit += 50),
                        child: const Text('โหลดความคิดเห็นก่อนหน้า'),
                      );
                    }
                    final comment =
                        comments[index - (comments.length >= _limit ? 1 : 0)];
                    return ContentVisibility(
                      authorId: comment.authorId,
                      child: _CommentTile(
                        comment: comment,
                        viewer: widget.user,
                        canDelete:
                            comment.authorId == widget.user.uid ||
                            widget.post.userId == widget.user.uid,
                        onDelete: () => _delete(comment),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MemberAvatar(uid: widget.user.uid, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'เขียนความคิดเห็น...',
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'ส่งความคิดเห็น',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  const _PostPreview({required this.post, required this.viewer});
  final Post post;
  final User viewer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ProfileScreen(user: viewer, profileUid: post.userId),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  MemberAvatar(uid: post.userId, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child:
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(post.userId)
                              .snapshots(),
                          builder: (context, snapshot) {
                            final profileName = snapshot.data
                                ?.data()?['displayName'];
                            final name =
                                profileName is String &&
                                    profileName.trim().isNotEmpty
                                ? profileName.trim()
                                : post.authorName;
                            return Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            );
                          },
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (post.content.isNotEmpty || post.taggedUserIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            TaggedPostContent(
              post: post,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              selectable: false,
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.viewer,
    required this.canDelete,
    required this.onDelete,
  });

  final PostComment comment;
  final User viewer;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    void openProfile() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileScreen(user: viewer, profileUid: comment.authorId),
      ),
    );

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      // ใช้ชื่อโปรไฟล์ปัจจุบันแทนชื่อสำเนาที่เก็บไว้ในคอมเมนต์เก่า
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(comment.authorId)
          .snapshots(),
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data?.data();
        final currentName = profile?['displayName'];
        final authorName =
            currentName is String && currentName.trim().isNotEmpty
            ? currentName.trim()
            : comment.authorName;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: openProfile,
              customBorder: const CircleBorder(),
              child: MemberAvatar(uid: comment.authorId, radius: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ชื่อและเวลาวางเป็นหัวแยกจากกล่องเนื้อหาคอมเมนต์
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: openProfile,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTime(comment.createdAt),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(comment.content),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (canDelete)
              PopupMenuButton<String>(
                tooltip: 'จัดการความคิดเห็น',
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('ลบความคิดเห็น')),
                ],
              ),
          ],
        );
      },
    );
  }
}

String _relativeTime(DateTime? date) {
  if (date == null) return 'เมื่อสักครู่';
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'เมื่อสักครู่';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} นาทีที่แล้ว';
  if (elapsed.inDays < 1) return '${elapsed.inHours} ชั่วโมงที่แล้ว';
  return '${date.day}/${date.month}/${date.year}';
}
