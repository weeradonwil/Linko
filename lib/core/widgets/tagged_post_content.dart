import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../models/post.dart';
import '../../screens/profile/profile.dart';

// User IDs are the real tags; this only makes them readable in the post body.
String renderTaggedPostText(
  String content,
  List<String> taggedUserIds,
  Map<String, String> namesById,
) {
  var visibleText = content.trimRight();
  for (final uid in taggedUserIds) {
    final name = namesById[uid] ?? 'สมาชิก';
    final mention = '@$name';
    final exactMention = RegExp(
      r'(^|\s)' + RegExp.escape(mention) + r'(?=\s|$|[.,!?])',
      caseSensitive: false,
    );
    if (exactMention.hasMatch(visibleText)) continue;
    visibleText = '${visibleText.isEmpty ? '' : '$visibleText '}$mention';
  }
  return visibleText;
}

/// Resolves tagged account IDs to names so mentions stay visible on every post surface.
class TaggedPostContent extends StatefulWidget {
  const TaggedPostContent({
    super.key,
    required this.post,
    this.style,
    this.maxLines,
    this.overflow,
    this.selectable = true,
  });

  final Post post;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;

  @override
  State<TaggedPostContent> createState() => _TaggedPostContentState();
}

class _TaggedPostContentState extends State<TaggedPostContent> {
  final Map<String, TapGestureRecognizer> _tapRecognizers = {};

  @override
  void dispose() {
    for (final recognizer in _tapRecognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(String uid) =>
      _tapRecognizers.putIfAbsent(
        uid,
        () => TapGestureRecognizer()
          ..onTap = () {
            final viewer = FirebaseAuth.instance.currentUser;
            if (!mounted || viewer == null) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProfileScreen(user: viewer, profileUid: uid),
              ),
            );
          },
      );

  @override
  Widget build(BuildContext context) {
    if (widget.post.taggedUserIds.isEmpty) return _text(widget.post.content);

    final profileStream = FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: widget.post.taggedUserIds)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: profileStream,
      builder: (context, snapshot) {
        final namesById = <String, String>{};
        for (final profile in snapshot.data?.docs ?? const []) {
          final name = profile.data()['displayName'];
          if (name is String && name.trim().isNotEmpty) {
            namesById[profile.id] = name.trim();
          }
        }

        final visibleText = renderTaggedPostText(
          widget.post.content,
          widget.post.taggedUserIds,
          namesById,
        );
        final matches = <({int start, int end, String uid})>[];
        final usedStarts = <int>{};
        for (final uid in widget.post.taggedUserIds) {
          final name = namesById[uid];
          if (name == null) continue;
          final pattern = RegExp(
            r'(^|\s)' + RegExp.escape('@$name') + r'(?=\s|$|[.,!?])',
            caseSensitive: false,
          );
          // Only IDs saved as tags become links. Plain @text stays plain text.
          for (final match in pattern.allMatches(visibleText)) {
            final start = match.start + (match.group(1)?.length ?? 0);
            if (usedStarts.add(start)) {
              matches.add((
                start: start,
                end: start + name.length + 1,
                uid: uid,
              ));
              break;
            }
          }
        }
        if (matches.isEmpty) return _text(visibleText);
        matches.sort((a, b) => a.start.compareTo(b.start));

        final spans = <InlineSpan>[];
        var offset = 0;
        for (final match in matches) {
          if (match.start < offset) continue;
          if (match.start > offset) {
            spans.add(
              TextSpan(text: visibleText.substring(offset, match.start)),
            );
          }
          spans.add(
            TextSpan(
              text: visibleText.substring(match.start, match.end),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              recognizer: _recognizerFor(match.uid),
            ),
          );
          offset = match.end;
        }
        if (offset < visibleText.length) {
          spans.add(TextSpan(text: visibleText.substring(offset)));
        }
        final richText = TextSpan(children: spans);
        return widget.selectable
            ? SelectableText.rich(
                richText,
                style: widget.style,
                maxLines: widget.maxLines,
              )
            : Text.rich(
                richText,
                style: widget.style,
                maxLines: widget.maxLines,
                overflow: widget.overflow,
              );
      },
    );
  }

  Widget _text(String value) => widget.selectable
      ? SelectableText(
          value,
          style: widget.style,
          maxLines: widget.maxLines,
          // SelectableText takes TextWidthBasis internally; overflow is not supported.
        )
      : Text(
          value,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
        );
}
