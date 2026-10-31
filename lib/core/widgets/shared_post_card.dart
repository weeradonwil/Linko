import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../../screens/comments/post_comments_screen.dart';
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
                      Text(
                        'แชร์จาก ${post.authorName}',
                        style: Theme.of(context).textTheme.labelLarge,
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
