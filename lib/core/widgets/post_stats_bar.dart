import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/social_reaction.dart';
import 'reaction_people_sheet.dart';

/// Shows the post totals in one place; tapping the reaction total opens its people list.
class PostStatsBar extends StatelessWidget {
  const PostStatsBar({
    super.key,
    required this.post,
    this.groupId,
    this.refreshKey = 0,
  });

  final Post post;
  final String? groupId;
  final int refreshKey;

  String get _postPath =>
      groupId == null ? 'posts/${post.id}' : 'groups/$groupId/posts/${post.id}';

  @override
  Widget build(BuildContext context) {
    final reactionPath = '$_postPath/reactions';
    final commentsQuery = FirebaseFirestore.instance.collection(
      '$_postPath/comments',
    );
    final shareCountFuture = groupId == null
        ? FirebaseFirestore.instance
              .collection('posts')
              .where('sharedPostId', isEqualTo: post.id)
              .where('visibility', isEqualTo: 'public')
              .where('authorIsPrivate', isEqualTo: false)
              .count()
              .get()
              .then((snapshot) => snapshot.count ?? 0)
        : Future<int>.value(0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(reactionPath)
                    .snapshots(),
                builder: (context, snapshot) {
                  final counts = <String, int>{};
                  for (final doc in snapshot.data?.docs ?? const []) {
                    final id = doc.data()['reaction'];
                    if (id is String && id != 'dislike') {
                      counts[id] = (counts[id] ?? 0) + 1;
                    }
                  }
                  final total = counts.values.fold<int>(0, (a, b) => a + b);
                  final topReaction = counts.entries.isEmpty
                      ? null
                      : counts.entries.reduce(
                          (a, b) => a.value >= b.value ? a : b,
                        );
                  final emoji = topReaction == null
                      ? '👍'
                      : SocialReaction.byId(topReaction.key)?.emoji ?? '👍';
                  return _StatButton(
                    label: '$total $emoji',
                    selected: false,
                    onTap: () => _showPeople(context, reactionPath),
                  );
                },
              ),
              const SizedBox(width: 8),
              FutureBuilder<AggregateQuerySnapshot>(
                key: ValueKey('comments-$refreshKey-$_postPath'),
                future: commentsQuery.count().get(),
                builder: (context, snapshot) => _StatButton(
                  label: '${snapshot.data?.count ?? 0} ความคิดเห็น',
                  selected: true,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 8),
              FutureBuilder<int>(
                key: ValueKey('shares-$refreshKey-$_postPath'),
                future: shareCountFuture,
                builder: (context, snapshot) => _StatButton(
                  label: '${snapshot.data ?? 0} แชร์',
                  selected: false,
                  onTap: null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPeople(BuildContext context, String reactionPath) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .8,
        child: ReactionPeopleSheet(path: reactionPath),
      ),
    );
  }
}

class _StatButton extends StatelessWidget {
  const _StatButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? colors.primary : colors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
