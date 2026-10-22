import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/models/chat_models.dart';
import 'package:social_app/core/models/post.dart';
import 'package:social_app/core/models/post_policy.dart';
import 'package:social_app/core/utils/document_values.dart';

void main() {
  test('a malformed legacy document cannot break the post list', () {
    final post = Post.fromData('old', {
      'userId': 1,
      'authorName': [],
      'content': false,
      'tags': [123, 'valid'],
      'createdAt': 'bad',
      'mediaPath': 42,
      'thumbnailPath': {},
    });
    expect(post.tags, ['valid']);
    expect(post.authorName, 'สมาชิก');
    expect(post.mediaPath, isNull);
    expect(post.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
  test('malformed counters and maps cannot break the chat list', () {
    final room = ConversationSummary.fromData('old', {
      'participantIds': ['me', 'peer', 123],
      'participantNames': 'bad',
      'unreadCounts': {'me': 'not-a-number'},
      'hiddenFor': false,
    }, 'me');
    expect(room.unreadCount, 0);
    expect(room.participantIds, ['me', 'peer']);
    expect(room.peerName('me'), 'สมาชิก');
    expect(room.isHidden, isFalse);
  });
  test('media-only editing is valid; removing its last content is not', () {
    expect(PostPolicy.hasContent('', hasMedia: true), isTrue);
    expect(PostPolicy.hasContent('  ', hasMedia: false), isFalse);
    expect(PostPolicy.hasContent('Caption', hasMedia: false), isTrue);
  });
  test(
    'privacy jobs apply the pending target and preserve explicit private posts',
    () {
      expect(
        PostPolicy.profileIsPrivate({
          'isPrivate': false,
          'privacyTarget': true,
        }),
        isTrue,
      );
      expect(
        PostPolicy.profileIsPrivate({
          'isPrivate': true,
          'privacyTarget': false,
        }),
        isFalse,
      );
      expect(PostPolicy.audience(true, 'public'), 'followers');
      expect(PostPolicy.audience(false, 'followers'), 'public');
      expect(PostPolicy.audience(true, 'private'), 'private');
      expect(PostPolicy.audience(false, 'private'), 'private');
    },
  );
  test('profile repair limits do not split emoji surrogate pairs', () {
    expect(boundedString('A😀B', 2), 'A');
    expect(boundedString('A😀B', 3), 'A😀');
  });
  test('blank and malformed display names have a safe avatar initial', () {
    expect(readName('  '), 'สมาชิก');
    expect(readName(123), 'สมาชิก');
    expect(readName('  King '), 'King');
  });
}
