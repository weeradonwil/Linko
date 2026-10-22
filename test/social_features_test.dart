// ทดสอบรายการ reaction ที่ใช้ร่วมกันระหว่าง UI, service และ Firestore Rules
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/models/social_reaction.dart';
import 'package:social_app/core/services/group_reaction_service.dart';
import 'package:social_app/core/services/reaction_service.dart';

void main() {
  test('รองรับ reaction แบบกดค้างและ dislike', () {
    expect(ReactionService.supportedReactions, {
      'like',
      'love',
      'haha',
      'wow',
      'sad',
      'angry',
      'dislike',
    });
    expect(
      GroupReactionService.supportedReactions,
      ReactionService.supportedReactions,
    );
    expect(SocialReaction.options, hasLength(7));
    expect(SocialReaction.byId('like')?.emoji, '👍');
    expect(SocialReaction.byId('love')?.emoji, '❤️');
    expect(SocialReaction.byId('haha')?.emoji, '😂');
    expect(SocialReaction.byId('wow')?.emoji, '😮');
    expect(SocialReaction.byId('sad')?.emoji, '😢');
    expect(SocialReaction.byId('angry')?.emoji, '😡');
    expect(SocialReaction.byId('dislike')?.emoji, '👎');
  });

  test('reaction ID ไม่ซ้ำและค้นหา ID ที่ไม่รองรับไม่เจอ', () {
    final ids = SocialReaction.options.map((reaction) => reaction.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(SocialReaction.byId('love')?.id, 'love');
    expect(SocialReaction.byId('haha')?.id, 'haha');
    expect(SocialReaction.byId('unknown'), isNull);
  });
}
