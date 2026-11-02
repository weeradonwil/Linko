import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../../screens/comments/post_comments_screen.dart';
import '../../screens/profile/profile.dart';
import 'member_avatar.dart';
import 'post_media.dart';
import 'content_visibility.dart';

/// อ่านต้นฉบับสดเสมอ เปลี่ยนเป็นส่วนตัวหรือลบแล้วจะไม่แสดงภาพตัวอย่างเก่าค้างไว้
class SharedPostCard extends StatelessWidget {
  const SharedPostCard({super.key, required this.postId});
  final String postId;
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .snapshots(),
        builder: (context, snapshot) {
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
                onTap: () => Navigator.of(context).push(
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'แชร์จาก ${post.authorName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    Text(
                                      'ดูโปรไฟล์',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
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
                      Text(
                        post.content,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
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
