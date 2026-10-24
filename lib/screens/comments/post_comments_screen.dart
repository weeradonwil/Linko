// หน้าความคิดเห็นของโพสต์ แสดงรายการสดและเปิดให้สมาชิกเพิ่ม/ลบคอมเมนต์ของตน
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/post.dart';
import '../../core/models/post_comment.dart';
import '../../core/services/comment_service.dart';
import '../../core/utils/firebase_error_message.dart';

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
          _PostPreview(post: widget.post),
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
                    return _CommentTile(
                      comment: comment,
                      canDelete:
                          comment.authorId == widget.user.uid ||
                          widget.post.userId == widget.user.uid,
                      onDelete: () => _delete(comment),
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
                  CircleAvatar(
                    radius: 18,
                    child: Text(_initial(widget.user.displayName)),
                  ),
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
  const _PostPreview({required this.post});
  final Post post;

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
          Text(post.authorName, style: Theme.of(context).textTheme.titleSmall),
          if (post.content.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(post.content, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
  });

  final PostComment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 19, child: Text(_initial(comment.authorName))),
        const SizedBox(width: 10),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.authorName,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(comment.content),
                  const SizedBox(height: 5),
                  Text(
                    _relativeTime(comment.createdAt),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
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
  }
}

String _initial(String? name) {
  final value = name?.trim() ?? '';
  return value.isEmpty ? 'ส' : value.characters.first.toUpperCase();
}

String _relativeTime(DateTime? date) {
  if (date == null) return 'เมื่อสักครู่';
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'เมื่อสักครู่';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} นาทีที่แล้ว';
  if (elapsed.inDays < 1) return '${elapsed.inHours} ชั่วโมงที่แล้ว';
  return '${date.day}/${date.month}/${date.year}';
}
