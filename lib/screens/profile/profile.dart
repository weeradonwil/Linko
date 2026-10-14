// แสดงโปรไฟล์ โพสต์ และความสัมพันธ์ผู้ติดตามของสมาชิก
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/post.dart';
import '../../core/services/follow_service.dart';
import '../../core/widgets/post_media.dart';

/// แสดงโปรไฟล์ตนเองหรือสมาชิกที่เปิดจากผลค้นหา/โพสต์
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.user, this.profileUid});

  final User user;
  final String? profileUid;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firestore = FirebaseFirestore.instance;
  late final FollowService _followService;
  String get _profileUid => widget.profileUid ?? widget.user.uid;
  bool get _isOwnProfile => _profileUid == widget.user.uid;

  @override
  void initState() {
    super.initState();
    _followService = FollowService(firestore: _firestore);
  }

  Future<void> _editName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขชื่อโปรไฟล์'),
        content: TextField(
          controller: controller,
          maxLength: 60,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'ชื่อที่แสดง'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _firestore.collection('users').doc(_profileUid).update({
        'displayName': name,
        'displayNameLower': name.toLowerCase(),
      });
      await widget.user.updateDisplayName(name);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('บันทึกชื่อไม่สำเร็จ: $error')));
    }
  }

  Future<void> _toggleFollow(bool isFollowing) async {
    try {
      if (isFollowing) {
        await _followService.unfollow(_profileUid);
      } else {
        await _followService.follow(_profileUid);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เปลี่ยนสถานะติดตามไม่สำเร็จ: $error')),
      );
    }
  }

  void _showPeople(String title, bool followers) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PeopleSheet(
        title: title,
        stream: followers
            ? _followService.watchFollowers(_profileUid)
            : _followService.watchFollowing(_profileUid),
        firestore: _firestore,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = _firestore.collection('users').doc(_profileUid);
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: profile.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('โหลดโปรไฟล์ไม่สำเร็จ'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return const Center(child: Text('ไม่พบสมาชิกนี้'));
          }
          final data = snapshot.data!.data() ?? const <String, dynamic>{};
          final name =
              (data['displayName'] as String?)?.trim().isNotEmpty == true
              ? (data['displayName'] as String).trim()
              : 'สมาชิก';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: colors.primaryContainer,
                        child: Text(
                          name.characters.first.toUpperCase(),
                          style: TextStyle(
                            fontSize: 32,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(name, style: Theme.of(context).textTheme.titleLarge),
                      if (_isOwnProfile && widget.user.email != null)
                        Text(
                          widget.user.email!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _PeopleCount(
                            label: 'ผู้ติดตาม',
                            stream: _followService.watchFollowers(_profileUid),
                            onTap: () => _showPeople('ผู้ติดตาม', true),
                          ),
                          const SizedBox(width: 26),
                          _PeopleCount(
                            label: 'กำลังติดตาม',
                            stream: _followService.watchFollowing(_profileUid),
                            onTap: () => _showPeople('กำลังติดตาม', false),
                          ),
                        ],
                      ),
                      if (_isOwnProfile) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () => _editName(name),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('แก้ไขชื่อ'),
                        ),
                      ] else ...[
                        const SizedBox(height: 14),
                        StreamBuilder<bool>(
                          stream: _followService.watchIsFollowing(_profileUid),
                          builder: (context, following) => FilledButton.icon(
                            onPressed: following.hasData
                                ? () => _toggleFollow(following.data!)
                                : null,
                            icon: Icon(
                              following.data == true
                                  ? Icons.person_remove_alt_1_rounded
                                  : Icons.person_add_alt_1_rounded,
                            ),
                            label: Text(
                              following.data == true ? 'กำลังติดตาม' : 'ติดตาม',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                child: Text(
                  'โพสต์',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _postsStream(),
                builder: (context, postsSnapshot) {
                  if (postsSnapshot.hasError) {
                    return const _ProfileMessage('โหลดโพสต์ไม่สำเร็จ');
                  }
                  if (!postsSnapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final posts = postsSnapshot.data!.docs
                      .map(Post.fromSnapshot)
                      .toList();
                  if (posts.isEmpty) {
                    return const _ProfileMessage('ยังไม่มีโพสต์');
                  }
                  return Column(
                    children: posts
                        .map((post) => _ProfilePost(post: post))
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// ผู้ชมอื่นเห็นเฉพาะโพสต์ public; เจ้าของโปรไฟล์เห็นโพสต์ของตัวเองทั้งหมด
  Stream<QuerySnapshot<Map<String, dynamic>>> _postsStream() {
    Query<Map<String, dynamic>> query = _firestore
        .collection('posts')
        .where('userId', isEqualTo: _profileUid);
    if (!_isOwnProfile) query = query.where('visibility', isEqualTo: 'public');
    return query.orderBy('createdAt', descending: true).limit(30).snapshots();
  }
}

class _PeopleCount extends StatelessWidget {
  const _PeopleCount({
    required this.label,
    required this.stream,
    required this.onTap,
  });
  final String label;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Text(
                  '${snapshot.data?.docs.length ?? 0}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
}

class _PeopleSheet extends StatelessWidget {
  const _PeopleSheet({
    required this.title,
    required this.stream,
    required this.firestore,
  });
  final String title;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final FirebaseFirestore firestore;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final people = snapshot.data!.docs;
                if (people.isEmpty) {
                  return const Center(child: Text('ยังไม่มีรายชื่อ'));
                }
                return ListView.builder(
                  itemCount: people.length,
                  itemBuilder: (context, index) {
                    final uid =
                        people[index].data()['uid'] as String? ??
                        people[index].id;
                    return FutureBuilder<
                      DocumentSnapshot<Map<String, dynamic>>
                    >(
                      future: firestore.collection('users').doc(uid).get(),
                      builder: (context, personSnapshot) {
                        final person =
                            personSnapshot.data?.data() ??
                            const <String, dynamic>{};
                        final name =
                            person['displayName'] as String? ?? 'สมาชิก';
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(name.characters.first.toUpperCase()),
                          ),
                          title: Text(name),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfilePost extends StatelessWidget {
  const _ProfilePost({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(post.authorName, style: Theme.of(context).textTheme.titleSmall),
          if (post.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(post.content),
          ],
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: post.tags
                  .map((tag) => Chip(label: Text('#$tag')))
                  .toList(),
            ),
          ],
          if (post.mediaPath != null) ...[
            const SizedBox(height: 8),
            PostMedia(path: post.mediaPath!, type: post.mediaType),
          ],
        ],
      ),
    ),
  );
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(child: Text(message)),
  );
}
