// แสดงโปรไฟล์ โพสต์ และความสัมพันธ์ผู้ติดตามของสมาชิก
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../core/models/post.dart';
import '../../core/models/post_policy.dart';
import '../../core/utils/document_values.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/follow_service.dart';
import '../../core/services/post_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_media.dart';
import '../admin/admin_reports_screen.dart';
import '../chat/chat_room.dart';
import 'edit_profile_screen.dart';

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
  late final Future<bool> _hasAdminClaim;
  final _postService = PostService();
  bool _followBusy = false;
  bool _openingChat = false;
  bool _privacyBusy = false;
  int _postsLimit = 30;
  String get _profileUid => widget.profileUid ?? widget.user.uid;
  bool get _isOwnProfile => _profileUid == widget.user.uid;

  @override
  void initState() {
    super.initState();
    _followService = FollowService(firestore: _firestore);
    _hasAdminClaim = _isAdmin();
  }

  Future<bool> _isAdmin() async {
    if (!_isOwnProfile) return false;
    final token = await widget.user.getIdTokenResult(true);
    return token.claims?['admin'] == true;
  }

  Future<void> _editProfile({
    required String name,
    required String bio,
    required String? avatarPath,
  }) async {
    final authNameSynced = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditProfileScreen(
          user: widget.user,
          initialName: name,
          initialBio: bio,
          initialAvatarPath: avatarPath,
        ),
      ),
    );
    if (authNameSynced == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกโปรไฟล์แล้ว แต่ซิงค์ชื่อบัญชีไม่สำเร็จ'),
        ),
      );
    }
  }

  Future<void> _toggleFollow({
    required bool isFollowing,
    required bool hasRequested,
    required bool isPrivate,
  }) async {
    if (_followBusy) return;
    setState(() => _followBusy = true);
    try {
      if (isFollowing) {
        await _followService.unfollow(_profileUid);
      } else if (isPrivate && hasRequested) {
        await _followService.cancelFollowRequest(_profileUid);
      } else if (isPrivate) {
        await _followService.requestFollow(_profileUid);
      } else {
        await _followService.follow(_profileUid);
      }
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('permission-denied')
          ? 'ติดตามไม่สำเร็จ: กรุณา deploy Firestore Rules รุ่นล่าสุดก่อน'
          : 'ติดตามไม่สำเร็จ: $error';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _openChat(String peerName) async {
    if (_openingChat) return;
    setState(() => _openingChat = true);
    try {
      final conversationId = await ChatService().openConversation(
        peerId: _profileUid,
        peerName: peerName,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(
            user: widget.user,
            conversationId: conversationId,
            peerId: _profileUid,
            peerName: peerName,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('เปิดแชทไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _togglePrivacy(bool isPrivate) async {
    if (_privacyBusy) return;
    setState(() => _privacyBusy = true);
    try {
      await _postService.updateProfilePrivacy(isPrivate);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เปลี่ยนความเป็นส่วนตัวไม่สำเร็จ: $error')),
      );
    } finally {
      if (mounted) setState(() => _privacyBusy = false);
    }
  }

  void _showFollowRequests() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FollowRequestsSheet(
        stream: _followService.watchFollowRequests(_profileUid),
        firestore: _firestore,
        followService: _followService,
      ),
    );
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
          final storedName = readString(data['displayName']).trim();
          final name = storedName.isEmpty ? 'สมาชิก' : storedName;
          final bio = readString(data['bio']).trim();
          final isPrivate = PostPolicy.profileIsPrivate(data);
          final privacyPending = data['privacyTarget'] is bool;
          final avatarPath = readOptionalString(data['avatarPath']);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                  child: Column(
                    children: [
                      FutureBuilder<String>(
                        future: avatarPath == null || avatarPath.isEmpty
                            ? null
                            : FirebaseStorage.instance
                                  .ref(avatarPath)
                                  .getDownloadURL(),
                        builder: (context, avatar) => CircleAvatar(
                          radius: 40,
                          backgroundColor: colors.primaryContainer,
                          backgroundImage: avatar.data == null
                              ? null
                              : NetworkImage(avatar.data!),
                          child: avatar.data == null
                              ? Text(
                                  (name.isEmpty ? '?' : name.characters.first)
                                      .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 32,
                                    color: colors.onPrimaryContainer,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(name, style: Theme.of(context).textTheme.titleLarge),
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(bio, textAlign: TextAlign.center),
                      ] else if (_isOwnProfile) ...[
                        const SizedBox(height: 6),
                        Text(
                          'เพิ่มคำแนะนำตัวของคุณ',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                      if (_isOwnProfile && widget.user.email != null)
                        Text(
                          widget.user.email!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _PeopleCount(
                              label: 'ผู้ติดตาม',
                              stream: _followService.watchFollowers(
                                _profileUid,
                              ),
                              onTap: () => _showPeople('ผู้ติดตาม', true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PeopleCount(
                              label: 'กำลังติดตาม',
                              stream: _followService.watchFollowing(
                                _profileUid,
                              ),
                              onTap: () => _showPeople('กำลังติดตาม', false),
                            ),
                          ),
                        ],
                      ),
                      if (_isOwnProfile) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _editProfile(
                              name: name,
                              bio: bio,
                              avatarPath: avatarPath,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('แก้ไขโปรไฟล์'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 4),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.lock_outline_rounded,
                            color: isPrivate
                                ? AppTheme.primary
                                : colors.outline,
                          ),
                          title: const Text('บัญชีส่วนตัว'),
                          subtitle: Text(
                            isPrivate
                                ? 'เปิดอยู่ · เฉพาะผู้ติดตามที่อนุมัติจะเห็นโพสต์'
                                : 'ปิดอยู่ · ทุกคนดูโพสต์สาธารณะได้',
                          ),
                          trailing: Switch.adaptive(
                            value: isPrivate,
                            onChanged: _privacyBusy || privacyPending
                                ? null
                                : _togglePrivacy,
                            thumbColor: WidgetStateProperty.resolveWith<Color?>(
                              (states) => states.contains(WidgetState.selected)
                                  ? AppTheme.primary
                                  : Colors.white,
                            ),
                            trackColor: WidgetStateProperty.resolveWith<Color?>(
                              (states) => states.contains(WidgetState.selected)
                                  ? AppTheme.primary.withValues(alpha: .32)
                                  : colors.outlineVariant,
                            ),
                            trackOutlineColor: WidgetStateProperty.all(
                              Colors.transparent,
                            ),
                          ),
                        ),
                        if (privacyPending)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'กำลังปรับความเป็นส่วนตัวของโพสต์',
                            ),
                            subtitle: const Text(
                              'หากงานหยุดลง กดดำเนินการต่อได้',
                            ),
                            trailing: TextButton(
                              onPressed: _privacyBusy
                                  ? null
                                  : () => _togglePrivacy(
                                      data['privacyTarget'] as bool,
                                    ),
                              child: Text(
                                _privacyBusy ? 'กำลังบันทึก' : 'ดำเนินการต่อ',
                              ),
                            ),
                          ),
                        if (isPrivate)
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _followService.watchFollowRequests(
                              _profileUid,
                            ),
                            builder: (context, requests) => Align(
                              alignment: Alignment.center,
                              child: OutlinedButton.icon(
                                onPressed: _showFollowRequests,
                                icon: const Icon(Icons.person_add_alt_1),
                                label: Text(
                                  'คำขอติดตาม (${requests.data?.docs.length ?? 0})',
                                ),
                              ),
                            ),
                          ),
                        FutureBuilder<bool>(
                          future: _hasAdminClaim,
                          builder: (context, claim) => claim.data == true
                              ? OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          AdminReportsScreen(user: widget.user),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                  ),
                                  label: const Text('จัดการรายงาน'),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ] else ...[
                        const SizedBox(height: 14),
                        StreamBuilder<bool>(
                          stream: _followService.watchIsFollowing(_profileUid),
                          builder: (context, following) => StreamBuilder<bool>(
                            stream: _followService.watchHasRequested(
                              _profileUid,
                            ),
                            builder: (context, requested) {
                              final isFollowing = following.data == true;
                              final hasRequested = requested.data == true;
                              final statusUnavailable =
                                  following.hasError || requested.hasError;
                              final canAttemptFollow =
                                  following.hasData && requested.hasData ||
                                  statusUnavailable;
                              return Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: canAttemptFollow && !_followBusy
                                        ? () => _toggleFollow(
                                            isFollowing: isFollowing,
                                            hasRequested: hasRequested,
                                            isPrivate: isPrivate,
                                          )
                                        : null,
                                    icon: Icon(
                                      isFollowing
                                          ? Icons.person_remove_alt_1_rounded
                                          : hasRequested
                                          ? Icons.hourglass_top_rounded
                                          : Icons.person_add_alt_1_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _followBusy
                                          ? 'กำลังบันทึก'
                                          : isFollowing
                                          ? 'กำลังติดตาม'
                                          : isPrivate && hasRequested
                                          ? 'ยกเลิกคำขอ'
                                          : isPrivate
                                          ? 'ขอติดตาม'
                                          : 'ติดตาม',
                                    ),
                                  ),
                                  if (statusUnavailable)
                                    SizedBox(
                                      width:
                                          MediaQuery.sizeOf(context).width - 80,
                                      child: Text(
                                        'โหลดสถานะติดตามไม่สำเร็จ หากกดแล้วยังไม่ได้ ให้ deploy Firestore Rules รุ่นล่าสุด',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: colors.error),
                                      ),
                                    ),
                                  if (isFollowing)
                                    OutlinedButton.icon(
                                      onPressed: _openingChat
                                          ? null
                                          : () => _openChat(name),
                                      icon: const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _openingChat
                                            ? 'กำลังเปิดแชท'
                                            : 'ข้อความ',
                                      ),
                                    ),
                                ],
                              );
                            },
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
                  _isOwnProfile ? 'โพสต์ของฉัน' : 'โพสต์',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _buildProfilePosts(isPrivate),
            ],
          );
        },
      ),
    );
  }

  /// ผู้ชมอื่นเห็นเฉพาะโพสต์ public; เจ้าของโปรไฟล์เห็นโพสต์ของตัวเองทั้งหมด
  Widget _buildProfilePosts(bool isPrivate) {
    if (_isOwnProfile) return _profilePostsList(isPrivate);
    return StreamBuilder<bool>(
      stream: _followService.watchIsFollowing(_profileUid),
      builder: (context, following) {
        if (isPrivate && following.data != true) {
          return const _ProfileMessage(
            'บัญชีนี้เป็นส่วนตัว ส่งคำขอติดตามเพื่อดูโพสต์',
          );
        }
        return _profilePostsList(isPrivate);
      },
    );
  }

  Widget _profilePostsList(bool isPrivate) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _postsStream(isPrivate),
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
              .where((p) => !p.isDeleting || _isOwnProfile)
              .toList();
          if (posts.isEmpty) return const _ProfileMessage('ยังไม่มีโพสต์');
          return Column(
            children: [
              for (final post in posts)
                if (post.isDeleting)
                  Card(
                    child: ListTile(
                      title: const Text('กำลังลบโพสต์'),
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            await _postService.deletePost(post);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                        child: const Text('ลบต่อ'),
                      ),
                    ),
                  )
                else
                  _ProfilePost(post: post),
              if (postsSnapshot.data!.docs.length >= _postsLimit)
                TextButton(
                  onPressed: () => setState(() => _postsLimit += 30),
                  child: const Text('โหลดโพสต์เก่าเพิ่มเติม'),
                ),
            ],
          );
        },
      );

  Stream<QuerySnapshot<Map<String, dynamic>>> _postsStream(bool isPrivate) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('posts')
        .where('userId', isEqualTo: _profileUid);
    if (!_isOwnProfile) {
      query = query.where(
        'visibility',
        isEqualTo: isPrivate ? 'followers' : 'public',
      );
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(_postsLimit)
        .snapshots();
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
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                children: [
                  Text(
                    '${snapshot.data?.docs.length ?? 0}',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
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
                if (snapshot.hasError) {
                  return const Center(child: Text('โหลดรายชื่อไม่สำเร็จ'));
                }
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
                        readOptionalString(people[index].data()['uid']) ??
                        people[index].id;
                    return FutureBuilder<
                      DocumentSnapshot<Map<String, dynamic>>
                    >(
                      future: firestore.collection('users').doc(uid).get(),
                      builder: (context, personSnapshot) {
                        final person =
                            personSnapshot.data?.data() ??
                            const <String, dynamic>{};
                        final name = readString(
                          person['displayName'],
                          'สมาชิก',
                        );
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (name.isEmpty ? '?' : name.characters.first)
                                  .toUpperCase(),
                            ),
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

class _FollowRequestsSheet extends StatelessWidget {
  const _FollowRequestsSheet({
    required this.stream,
    required this.firestore,
    required this.followService,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final FirebaseFirestore firestore;
  final FollowService followService;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'คำขอติดตาม',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('โหลดคำขอไม่สำเร็จ'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final requests = snapshot.data!.docs;
                if (requests.isEmpty) {
                  return const Center(child: Text('ไม่มีคำขอติดตาม'));
                }
                return ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    final requesterUid =
                        readOptionalString(request.data()['uid']) ?? request.id;
                    return FutureBuilder<
                      DocumentSnapshot<Map<String, dynamic>>
                    >(
                      future: firestore
                          .collection('users')
                          .doc(requesterUid)
                          .get(),
                      builder: (context, personSnapshot) {
                        final person =
                            personSnapshot.data?.data() ??
                            const <String, dynamic>{};
                        final name = readString(
                          person['displayName'],
                          'สมาชิก',
                        );
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (name.isEmpty ? '?' : name.characters.first)
                                  .toUpperCase(),
                            ),
                          ),
                          title: Text(name),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'อนุมัติ',
                                onPressed: () async {
                                  try {
                                    await followService.approveFollowRequest(
                                      requesterUid,
                                    );
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'อนุมัติไม่สำเร็จ: $error',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.check_circle_outline),
                              ),
                              IconButton(
                                tooltip: 'ปฏิเสธ',
                                onPressed: () async {
                                  try {
                                    await followService.rejectFollowRequest(
                                      requesterUid,
                                    );
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'ปฏิเสธไม่สำเร็จ: $error',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
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
  Widget build(BuildContext context) {
    if (post.mediaPath == null) return _buildTextPost(context);

    // โพสต์ที่มีสื่อคงการ์ดรูปแบบเดิมไว้ เพื่อไม่เปลี่ยนการแสดงภาพและวิดีโอ
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.authorName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
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
            const SizedBox(height: 8),
            PostMedia(
              path: post.mediaPath!,
              type: post.mediaType,
              thumbnailPath: post.thumbnailPath,
            ),
          ],
        ),
      ),
    );
  }

  /// แยกโพสต์ข้อความล้วนให้เนื้อหาเป็นจุดเด่น พร้อมเวลาและแท็กที่อ่านง่าย
  Widget _buildTextPost(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final createdAt = post.createdAt.toLocal();
    final timestamp =
        '${createdAt.day.toString().padLeft(2, '0')}/'
        '${createdAt.month.toString().padLeft(2, '0')}/'
        '${createdAt.year} • '
        '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: Text(post.authorName.characters.first.toUpperCase()),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            post.visibility == 'private'
                                ? Icons.lock_outline_rounded
                                : post.visibility == 'followers'
                                ? Icons.group_outlined
                                : Icons.public_rounded,
                            size: 13,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '$timestamp${post.editedAt == null ? '' : ' • แก้ไขแล้ว'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.notes_rounded, color: colors.primary),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                post.content.isEmpty ? 'โพสต์ข้อความ' : post.content,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(height: 1.5, fontWeight: FontWeight.w500),
              ),
            ),
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: post.tags
                    .map(
                      (tag) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            '#$tag',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: colors.primary),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
