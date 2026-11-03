import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/models/post.dart';
import 'package:social_app/core/widgets/tagged_post_content.dart';

void main() {
  test('Post keeps tagged accounts separate from hashtags', () {
    final post = Post.fromData('post-1', {
      'userId': 'owner',
      'authorName': 'rukna',
      'content': 'hello',
      'createdAt': DateTime.utc(2026, 11, 3),
      'tags': ['travel'],
      'taggedUserIds': ['friend-1', 'friend-2'],
      'visibility': 'public',
      'mediaType': 'none',
    });

    expect(post.tags, ['travel']);
    expect(post.taggedUserIds, ['friend-1', 'friend-2']);
  });

  test('Old posts without taggedUserIds still load', () {
    final post = Post.fromData('post-legacy', {
      'userId': 'owner',
      'authorName': 'rukna',
      'content': 'hello',
      'createdAt': DateTime.utc(2026, 11, 3),
      'tags': ['travel'],
      'visibility': 'public',
      'mediaType': 'none',
    });

    expect(post.taggedUserIds, isEmpty);
  });

  test('Tagged friend appears after caption without changing stored text', () {
    expect(renderTaggedPostText('Hi', ['friend'], {'friend': 'Paradise'}), 'Hi @Paradise');
  });

  test('Existing exact mention is not doubled, substring does not hide it', () {
    expect(renderTaggedPostText('Hi @Paradise', ['friend'], {'friend': 'Paradise'}), 'Hi @Paradise');
    expect(renderTaggedPostText('Hi @Paradise2', ['friend'], {'friend': 'Paradise'}), 'Hi @Paradise2 @Paradise');
  });
}
