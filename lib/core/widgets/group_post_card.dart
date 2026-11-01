import 'post_action_button.dart';
import 'content_visibility.dart';
import 'shared_post_card.dart';
import 'reaction_people_sheet.dart';

// การ์ดโพสต์กลุ่ม: แสดงสื่อ แท็ก ปฏิกิริยา ความคิดเห็น และเมนูจัดการตามสิทธิ์
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/social_group.dart';
import '../models/social_reaction.dart';
import '../services/group_reaction_service.dart';
import '../services/group_service.dart';
import '../utils/document_values.dart';
import '../../screens/comments/post_comments_screen.dart';
import '../../screens/create_post/create_post.dart';
import '../../screens/profile/profile.dart';
import 'post_media.dart';
import 'member_avatar.dart';
import 'post_report_dialog.dart';
import 'social_reaction_picker.dart';

/// รวมการใช้งานโพสต์กลุ่มไว้จุดเดียว และใช้ฟอร์ม/หน้าความคิดเห็นร่วมกับฟีดหลัก
class GroupPostCard extends StatefulWidget {
  const GroupPostCard({
    required this.groupId,
    required this.post,
    required this.user,
    this.canModerate = false,
    super.key,
  });
  final String groupId;
  final GroupPost post;
  final User user;
  final bool canModerate;

  @override
  State<GroupPostCard> createState() => _GroupPostCardState();
}

class _GroupPostCardState extends State<GroupPostCard> {
  final _groups = GroupService();
  final _reactions = GroupReactionService();
  bool _busy = false;
  bool get _ownsPost => widget.post.authorId == widget.user.uid;

  /// กันการกดซ้ำและคืนสถานะปุ่มเมื่อส่งสำเร็จหรือถูก Rules ปฏิเสธ
  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = widget.post.isDeleting
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('ลบโพสต์นี้?'),
              content: const Text(
                'โพสต์ สื่อ ความคิดเห็น และปฏิกิริยาจะถูกลบถาวร',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('ลบโพสต์'),
                ),
              ],
            ),
          );
    if (confirmed != true || !mounted) return;
    await _perform(
      () => _groups.deletePost(groupId: widget.groupId, postId: widget.post.id),
    );
  }

  Future<void> _report() async {
    final draft = await showDialog<PostReportDraft>(
      context: context,
      builder: (_) => const PostReportDialog(),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      final already = await _groups.reportPost(
        groupId: widget.groupId,
        post: widget.post,
        reason: draft.reason,
        details: draft.details,
        hidePost: draft.hidePost,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              already ? 'คุณรายงานโพสต์นี้แล้ว' : 'ได้รับรายงานแล้ว',
            ),
          ),
        );
      }
    });
  }

  void _comments() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PostCommentsScreen(
        user: widget.user,
        post: widget.post.asPost(),
        groupId: widget.groupId,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    if (post.isDeleting) {
      if (!_ownsPost && !widget.canModerate) return const SizedBox.shrink();
      return Card(
        child: ListTile(
          title: const Text('กำลังลบโพสต์'),
          trailing: TextButton(
            onPressed: _busy ? null : _delete,
            child: const Text('ลบต่อ'),
          ),
        ),
      );
    }
    final date = post.createdAt?.toLocal();
    return ContentVisibility(
      authorId: widget.post.authorId,
      postKey: 'group_${widget.groupId}_${widget.post.id}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MemberAvatar(uid: post.authorId, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfileScreen(
                            user: widget.user,
                            profileUid: post.authorId,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.authorName,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            date == null
                                ? 'เมื่อสักครู่'
                                : '${date.day}/${date.month}/${date.year} '
                                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                                      '${post.editedAt == null ? '' : ' · แก้ไขแล้ว'}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: !_busy,
                    tooltip: 'จัดการโพสต์',
                    onSelected: (value) {
                      if (value == 'edit') {
                        Navigator.of(context).push(
                          MaterialPageRoute<bool>(
                            builder: (_) => CreatePostScreen(
                              user: widget.user,
                              post: post.asPost(),
                              groupId: widget.groupId,
                            ),
                          ),
                        );
                      }
                      if (value == 'delete') _delete();
                      if (value == 'report') _report();
                    },
                    itemBuilder: (_) => [
                      if (_ownsPost)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('แก้ไขโพสต์'),
                        ),
                      if (_ownsPost || widget.canModerate)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('ลบโพสต์'),
                        ),
                      if (!_ownsPost)
                        const PopupMenuItem(
                          value: 'report',
                          child: Text('รายงานโพสต์'),
                        ),
                    ],
                  ),
                ],
              ),
              if (post.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(post.content),
                ),
              if (post.tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: post.tags
                      .map((tag) => Chip(label: Text('#$tag')))
                      .toList(),
                ),
              if (post.mediaPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: PostMedia(
                    path: post.mediaPath!,
                    type: post.mediaType,
                    thumbnailPath: post.thumbnailPath,
                  ),
                ),
              if (post.sharedPostId != null)
                SharedPostCard(postId: post.sharedPostId!),
              const Divider(height: 24),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _reactions.watchReactions(widget.groupId, post.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('โหลดปฏิกิริยาไม่สำเร็จ');
                  }
                  final counts = {
                    for (final reaction in SocialReaction.options)
                      reaction.id: 0,
                  };
                  String? mine;
                  for (final doc
                      in snapshot.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                    final reaction = readOptionalString(doc.data()['reaction']);
                    if (reaction != null && counts.containsKey(reaction)) {
                      counts[reaction] = counts[reaction]! + 1;
                    }
                    if (doc.id == widget.user.uid) mine = reaction;
                  }
                  final selected = SocialReaction.byId(mine);
                  Future<void> react(String value) => _perform(
                    () => _reactions.toggleReaction(
                      groupId: widget.groupId,
                      postId: post.id,
                      reaction: value,
                    ),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReactionSummaryBar(
                        counts: counts,
                        path:
                            'groups/${widget.groupId}/posts/${post.id}/reactions',
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: PostActionButton(
                              icon: Icons.thumb_up_alt_outlined,
                              emoji:
                                  selected != null && selected.id != 'dislike'
                                  ? selected.emoji
                                  : null,
                              label:
                                  selected != null && selected.id != 'dislike'
                                  ? selected.label
                                  : 'ถูกใจ',
                              color:
                                  selected != null && selected.id != 'dislike'
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              onPressed: _busy ? null : () => react('like'),
                              onLongPress: _busy
                                  ? null
                                  : (anchor) async {
                                      final choice =
                                          await SocialReactionPicker.show(
                                            anchor,
                                          );
                                      if (choice != null && mounted) {
                                        await react(choice);
                                      }
                                    },
                            ),
                          ),
                          Expanded(
                            child: PostActionButton(
                              icon: mine == 'dislike'
                                  ? Icons.thumb_down_alt
                                  : Icons.thumb_down_alt_outlined,
                              label: 'ไม่ถูกใจ',
                              color: mine == 'dislike'
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                              onPressed: _busy ? null : () => react('dislike'),
                            ),
                          ),
                          Expanded(
                            child: PostActionButton(
                              icon: Icons.mode_comment_outlined,
                              label: 'ความคิดเห็น',
                              onPressed: _comments,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
