// ทดสอบรายการ reaction ที่ใช้ร่วมกันระหว่าง UI, service และ Firestore Rules
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/models/social_reaction.dart';
import 'package:social_app/core/services/reaction_service.dart';

void main() {
  test('รองรับ reaction like และ dislike ตามรายการปัจจุบัน', () {
    expect(ReactionService.supportedReactions, {'like', 'dislike'});
    expect(SocialReaction.options, hasLength(2));
    expect(SocialReaction.byId('like')?.emoji, '👍');
    expect(SocialReaction.byId('dislike')?.emoji, '👎');
  });

  test('reaction ID ไม่ซ้ำ และ reaction เก่าถูกแสดงเป็น Like', () {
    final ids = SocialReaction.options.map((reaction) => reaction.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(SocialReaction.byId('love')?.id, 'like');
    expect(SocialReaction.byId('haha')?.id, 'like');
    expect(SocialReaction.byId('unknown'), isNull);
  });
}
