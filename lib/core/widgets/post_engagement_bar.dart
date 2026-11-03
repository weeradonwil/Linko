// แถบปฏิกิริยาที่ใช้ในโปรไฟล์และหน้า Explore ให้ทำงานเหมือนแถบในฟีด
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/social_reaction.dart';
import '../services/reaction_service.dart';
import '../utils/document_values.dart';
import 'post_action_button.dart';
import 'post_comment_count_button.dart';
import 'social_reaction_picker.dart';

class PostEngagementBar extends StatefulWidget {
  const PostEngagementBar({
    super.key,
    required this.post,
    required this.onComment,
  });

  final Post post;
  final Future<void> Function() onComment;

  @override
  State<PostEngagementBar> createState() => _PostEngagementBarState();
}

class _PostEngagementBarState extends State<PostEngagementBar> {
  final _reactionService = ReactionService();

  Future<void> _setReaction(String reaction) async {
    try {
      await _reactionService.toggleReaction(
        postId: widget.post.id,
        reaction: reaction,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกความรู้สึกไม่สำเร็จ: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _reactionService.watchReactions(widget.post.id),
    builder: (context, snapshot) {
      final docs = snapshot.data?.docs ?? const [];
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final own = docs.where((doc) => doc.id == currentUid);
      final selectedReaction = own.isEmpty
          ? null
          : SocialReaction.byId(
              readOptionalString(own.first.data()['reaction']),
            );
      final ownId = selectedReaction?.id;
      final counts = <String, int>{
        for (final item in SocialReaction.options) item.id: 0,
      };
      for (final doc in docs) {
        final id = SocialReaction.byId(
          readOptionalString(doc.data()['reaction']),
        )?.id;
        if (id != null && counts.containsKey(id)) counts[id] = counts[id]! + 1;
      }
      // The visible count includes likes and emoji reactions, but not dislikes.
      final likeCount = counts.entries
          .where((entry) => entry.key != 'dislike')
          .fold<int>(0, (total, entry) => total + entry.value);
      final colors = Theme.of(context).colorScheme;

      return Column(
        children: [
          Divider(color: colors.outlineVariant, height: 1),
          Row(
            children: [
              Expanded(
                child: PostActionButton(
                  icon: ownId == 'like'
                      ? Icons.thumb_up_alt
                      : Icons.thumb_up_alt_outlined,
                  emoji: ownId == null || ownId == 'dislike'
                      ? null
                      : selectedReaction?.emoji,
                  label: ownId == null || ownId == 'dislike'
                      ? 'ถูกใจ'
                      : selectedReaction!.label,
                  color: ownId != null && ownId != 'dislike'
                      ? colors.primary
                      : null,
                  inlineCount: likeCount,
                  onPressed: () => _setReaction('like'),
                  onLongPress: (buttonContext) async {
                    final value = await SocialReactionPicker.show(
                      buttonContext,
                    );
                    if (value != null) _setReaction(value);
                  },
                ),
              ),
              Expanded(
                child: PostActionButton(
                  icon: ownId == 'dislike'
                      ? Icons.thumb_down_alt
                      : Icons.thumb_down_alt_outlined,
                  label: 'ไม่ถูกใจ',
                  color: ownId == 'dislike' ? colors.error : null,
                  onPressed: () => _setReaction('dislike'),
                ),
              ),
              Expanded(
                child: PostCommentCountButton(
                  postId: widget.post.id,
                  onPressed: widget.onComment,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
