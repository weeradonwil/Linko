import 'social_reaction.dart';

/// Like กับ Dislike แยกยอดไว้ ส่วนอารมณ์อื่นจะยุบเมื่อมีหลายแบบ
class ReactionSummary {
  static Map<String, int> visible(Map<String, int> counts) {
    final result = <String, int>{};
    if ((counts['like'] ?? 0) > 0) result['like'] = counts['like']!;
    final others = {
      for (final reaction in SocialReaction.options)
        if (reaction.id != 'like' &&
            reaction.id != 'dislike' &&
            (counts[reaction.id] ?? 0) > 0)
          reaction.id: counts[reaction.id]!,
    };
    if (others.length > 1) {
      result['other'] = others.values.fold(0, (sum, value) => sum + value);
    } else {
      result.addAll(others);
    }
    if ((counts['dislike'] ?? 0) > 0) result['dislike'] = counts['dislike']!;
    return result;
  }
}
