import 'social_reaction.dart';

/// Combines likes and emoji reactions while keeping dislikes separate.
class ReactionSummary {
  static Map<String, int> visible(Map<String, int> counts) {
    final result = <String, int>{};
    final combinedReactionCount = SocialReaction.options
        .where((reaction) => reaction.id != 'dislike')
        .fold<int>(0, (sum, reaction) => sum + (counts[reaction.id] ?? 0));
    if (combinedReactionCount > 0) result['other'] = combinedReactionCount;
    if ((counts['dislike'] ?? 0) > 0) result['dislike'] = counts['dislike']!;
    return result;
  }
}
