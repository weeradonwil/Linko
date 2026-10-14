// ทดสอบรายการ reaction ที่ใช้ร่วมกันระหว่าง UI, service และ Firestore Rules
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/models/social_reaction.dart';
import 'package:social_app/core/services/reaction_service.dart';

void main() {
  test('มี reaction like และอีโมจิอื่นครบตามรายการที่รองรับ', () {
    expect(ReactionService.supportedReactions, {
      'like',
      'love',
      'haha',
      'wow',
      'sad',
      'angry',
    });
    expect(SocialReaction.options, hasLength(6));
  });

  test('reaction ID ทุกตัวไม่ซ้ำและค้นหา emoji กับชื่อได้', () {
    final ids = SocialReaction.options.map((reaction) => reaction.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(SocialReaction.byId('love')?.emoji, '❤️');
    expect(SocialReaction.byId('haha')?.label, 'ฮ่าๆ');
    expect(SocialReaction.byId('unknown'), isNull);
  });
}
