import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../../screens/comments/post_comments_screen.dart';
import '../../screens/profile/profile.dart';
import 'member_avatar.dart';
import 'live_profile_name.dart';
import 'post_media.dart';
import 'content_visibility.dart';
import 'tagged_post_content.dart';
import '../services/trusted_service.dart';

/// อ่านต้นฉบับสดเสมอ เปลี่ยนเป็นส่วนตัวหรือลบแล้วจะไม่แสดงภาพตัวอย่างเก่าค้างไว้
class SharedPostCard extends StatefulWidget {
  const SharedPostCard({
    super.key,
    required this.postId,
    this.shareId,
    this.groupId,
    this.conversationId,
  });
  final String postId;
  final String? shareId;
  final String? groupId;
  final String? conversationId;

  @override
  State<SharedPostCard> createState() => _SharedPostCardState();
}

class _SharedPostCardState extends State<SharedPostCard> {
  bool _accessAttempted = false;
  bool _unlocking = false;
  int _readGeneration = 0;

  @override
  void didUpdateWidget(covariant SharedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId ||
        oldWidget.shareId != widget.shareId ||
        oldWidget.groupId != widget.groupId ||
        oldWidget.conversationId != widget.conversationId) {
      _accessAttempted = false;
      _unlocking = false;
      _readGeneration++;
    }
  }

  Future<void> _unlockSharedPost() async {
    if (_accessAttempted || widget.shareId == null) return;
    final destination = widget.groupId != null ? 'group' : 'chat';
    final targetId = widget.groupId ?? widget.conversationId;
    if (targetId == null) return;
    setState(() {
      _accessAttempted = true;
      _unlocking = true;
    });
    try {
      await TrustedService.call('openSharedPost', {
        'postId': widget.postId,
        'shareId': widget.shareId,
        'destination': destination,
        'targetId': targetId,
      });
      if (mounted) setState(() => _readGeneration++);
    } catch (_) {
      // Keep the unavailable card if the share, membership or source changed.
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    key: ValueKey(_readGeneration),
    stream: FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError &&
          !_accessAttempted &&
          widget.shareId != null &&
          (widget.groupId != null || widget.conversationId != null)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _unlockSharedPost();
        });
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (_unlocking) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError ||
          snapshot.hasData &&
              (!snapshot.data!.exists ||
                  snapshot.data!.data()?['visibility'] != 'public' ||
                  snapshot.data!.data()?['isDeleting'] == true)) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('โพสต์นี้ไม่พร้อมใช้งาน'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final post = Post.fromSnapshot(snapshot.data!);
      final viewer = FirebaseAuth.instance.currentUser;
      void openAuthorProfile() {
        if (viewer == null) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ProfileScreen(user: viewer, profileUid: post.userId),
          ),
        );
      }

      return ContentVisibility(
        authorId: post.userId,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _accessAttempted
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PostCommentsScreen(
                        user: FirebaseAuth.instance.currentUser!,
                        post: post,
                      ),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ปุ่มโปรไฟล์แยกจากพื้นที่แตะเปิดโพสต์ต้นฉบับ
                  Row(
                    children: [
                      InkWell(
                        onTap: openAuthorProfile,
                        customBorder: const CircleBorder(),
                        child: MemberAvatar(uid: post.userId, radius: 18),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: InkWell(
                          onTap: openAuthorProfile,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LiveProfileName(
                                  uid: post.userId,
                                  fallbackName: post.authorName,
                                  prefix: 'แชร์จาก ',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                Text(
                                  'ดูโปรไฟล์',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (post.content.isNotEmpty || post.taggedUserIds.isNotEmpty)
                    TaggedPostContent(
                      post: post,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      selectable: false,
                    ),
                  if (post.mediaPath != null)
                    SizedBox(
                      height: 180,
                      child: PostMedia(
                        path: post.mediaPath!,
                        type: post.mediaType,
                        thumbnailPath: post.thumbnailPath,
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('แตะเพื่อเปิดโพสต์ต้นฉบับ'),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
