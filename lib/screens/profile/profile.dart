import '../../core/widgets/shared_post_card.dart';
import '../../core/widgets/cover_editor.dart';
import 'moderation_screen.dart';
import '../../core/widgets/content_visibility.dart';
import 'blocked_users_screen.dart';

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
import '../../core/widgets/post_media.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/live_profile_name.dart';
import '../../core/widgets/post_engagement_bar.dart';
import '../../core/widgets/tagged_post_content.dart';
import '../admin/admin_reports_screen.dart';
import '../chat/chat_room.dart';
import '../comments/post_comments_screen.dart';
import '../create_post/create_post.dart';
import '../search/search_explore.dart';
import 'edit_profile_screen.dart';
import 'profile_image_screen.dart';
import '../../core/utils/avatar_thumbnail.dart';
import 'change_email_screen.dart';

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
  String? _profileEmail;
  String get _profileUid => widget.profileUid ?? widget.user.uid;
  bool get _isOwnProfile => _profileUid == widget.user.uid;

  @override
  void initState() {
    super.initState();
    _profileEmail = widget.user.email;
    _followService = FollowService(firestore: _firestore);
    _hasAdminClaim = _isAdmin();
  }

  Future<void> _changeEmail() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChangeEmailScreen(user: widget.user),
      ),
    );
    if (changed != true || !mounted) return;
    final refreshedUser = FirebaseAuth.instance.currentUser;
    setState(() => _profileEmail = refreshedUser?.email ?? widget.user.email);
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
    final currentProfile =
        (await _firestore.collection('users').doc(_profileUid).get()).data();
    final currentCover = currentProfile?['coverPath'] as String?;
    if (!mounted) return;
    final authNameSynced = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditProfileScreen(
          user: widget.user,
          initialName: name,
          initialBio: bio,
          initialAvatarPath: avatarPath,
          initialAvatarThumbPath: readOptionalString(
            currentProfile?['avatarThumbPath'],
          ),
          initialCoverPath: currentCover,
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

  void _openProfileImage(ProfileImageKind kind) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfileImageScreen(ownerUid: _profileUid, kind: kind),
      ),
    );
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

  Future<void> _deleteProfilePost(Post post) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบโพสต์นี้?'),
        content: const Text('โพสต์และโพสต์ที่แชร์นี้จะถูกลบออกจากบัญชีของคุณ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบโพสต์'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    try {
      // Shared posts are normal posts owned by this account, so the same
      // service removes the share card without touching its original post.
      await _postService.deletePost(post);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ลบโพสต์แล้ว')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ลบโพสต์ไม่สำเร็จ: $error')));
      }
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

  Future<void> _showPeople(String title, bool followers) async {
    // รับ UID ที่แตะกลับจากแผงรายชื่อ ปิดแผงก่อนเปิดโปรไฟล์ด้วยบัญชีที่ล็อกอินอยู่
    final selectedUid = await showModalBottomSheet<String>(
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
    if (!mounted || selectedUid == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileScreen(user: widget.user, profileUid: selectedUid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = _firestore.collection('users').doc(_profileUid);
    return Scaffold(
      appBar: AppBar(
        title: const Text('โปรไฟล์'),
        actions: [
          if (_isOwnProfile)
            IconButton(
              tooltip: 'คำเตือนโพสต์',
              icon: const Icon(Icons.gpp_maybe_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ModerationScreen(),
                ),
              ),
            ),
          if (_isOwnProfile)
            IconButton(
              tooltip: 'บัญชีที่บล็อก',
              icon: const Icon(Icons.block),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BlockedUsersScreen(),
                ),
              ),
            ),
        ],
      ),
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
          final privacyPending =
              data['privacyMigrationTarget'] is bool ||
              data['privacyTarget'] is bool;
          final privacyRetryTarget = data['privacyMigrationTarget'] is bool
              ? data['privacyMigrationTarget'] as bool
              : data['privacyTarget'] as bool?;
          final avatarPath = readOptionalString(data['avatarPath']);
          final avatarPreviewPath = visibleAvatarPath(data);
          final coverPath = readOptionalString(data['coverPath']);
          // รูปปกเป็นข้อมูลที่แสดงบนโปรไฟล์ ส่วนรูปโปรไฟล์ขนาดใหญ่ยังจำกัดเมื่อเป็นบัญชีส่วนตัว
          final canOpenAvatar = _isOwnProfile || !isPrivate;
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final avatarRadius = (constraints.maxWidth * 0.12)
                              .clamp(40.0, 144.0);
                          return Column(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  AspectRatio(
                                    aspectRatio: 1.4,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap:
                                          coverPath != null &&
                                              coverPath.isNotEmpty
                                          ? () => _openProfileImage(
                                              ProfileImageKind.cover,
                                            )
                                          : null,
                                      child: ProfileCover(path: coverPath),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: -avatarRadius,
                                    child: Center(
                                      child: InkResponse(
                                        customBorder: const CircleBorder(),
                                        onTap:
                                            canOpenAvatar &&
                                                avatarPath != null &&
                                                avatarPath.isNotEmpty
                                            ? () => _openProfileImage(
                                                ProfileImageKind.avatar,
                                              )
                                            : null,
                                        child: CircleAvatar(
                                          radius: avatarRadius + 4,
                                          backgroundColor: colors.surface,
                                          child: FutureBuilder<String>(
                                            future:
                                                avatarPreviewPath == null ||
                                                    avatarPreviewPath.isEmpty
                                                ? null
                                                : FirebaseStorage.instance
                                                      .ref(avatarPreviewPath)
                                                      .getDownloadURL(),
                                            builder: (context, avatar) => CircleAvatar(
                                              radius: avatarRadius,
                                              backgroundColor:
                                                  colors.primaryContainer,
                                              backgroundImage:
                                                  avatar.data == null
                                                  ? null
                                                  : NetworkImage(avatar.data!),
                                              child: avatar.data == null
                                                  ? Text(
                                                      (name.isEmpty
                                                              ? '?'
                                                              : name
                                                                    .characters
                                                                    .first)
                                                          .toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize:
                                                            avatarRadius * 0.8,
                                                        color: colors
                                                            .onPrimaryContainer,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: avatarRadius + 20),
                              Text(
                                name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          );
                        },
                      ),
                      if (!_isOwnProfile) BlockUserButton(uid: _profileUid),
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
                      if (_isOwnProfile && _profileEmail != null) ...[
                        Text(
                          _profileEmail!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        TextButton.icon(
                          onPressed: _changeEmail,
                          icon: const Icon(Icons.alternate_email_rounded),
                          label: const Text('เปลี่ยนอีเมล'),
                        ),
                      ],
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
                              backgroundColor: colors.primary,
                              foregroundColor: colors.onPrimary,
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
                            color: isPrivate ? colors.primary : colors.outline,
                          ),
                          title: const Text('บัญชีส่วนตัว'),
                          subtitle: Text(
                            isPrivate
                                ? 'เปิดอยู่ · เฉพาะผู้ติดตามที่อนุมัติจะเห็นโพสต์'
                                : 'ปิดอยู่ · ทุกคนดูโพสต์สาธารณะได้',
                          ),
                          trailing: Switch.adaptive(
                            value: isPrivate,
                            onChanged: _privacyBusy ? null : _togglePrivacy,
                            // ให้ Material เลือกคู่สี thumb/track ตามธีม รวมสถานะปิดใช้งาน
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
                                  : () => _togglePrivacy(privacyRetryTarget!),
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
              ContentVisibility(
                authorId: _profileUid,
                child: _buildProfilePosts(isPrivate: isPrivate),
              ),
            ],
          );
        },
      ),
    );
  }

  /// บัญชีส่วนตัวให้เฉพาะผู้ติดตามที่อนุมัติอ่านโพสต์ทั่วไป โดยไม่รวมโพสต์เฉพาะฉัน
  Widget _buildProfilePosts({required bool isPrivate}) {
    if (_isOwnProfile) return _profilePostsList(includeFollowers: true);
    return StreamBuilder<bool>(
      stream: _followService.watchIsFollowing(_profileUid),
      builder: (context, following) {
        if (following.hasError) {
          return const _ProfileMessage('ตรวจสอบสิทธิ์ดูโพสต์ไม่สำเร็จ');
        }
        if (isPrivate && !following.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (isPrivate && following.data != true) {
          return const _ProfileMessage(
            'บัญชีนี้เป็นส่วนตัว เฉพาะผู้ติดตามที่อนุมัติแล้วจึงจะเห็นโพสต์',
          );
        }
        return _profilePostsList(includeFollowers: following.data == true);
      },
    );
  }

  Widget _profilePostsList({
    required bool includeFollowers,
  }) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _postsStream(includeFollowers: includeFollowers),
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
          .where((p) => p.isDeleting ? _isOwnProfile : p.hasVisibleContent)
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
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$error')));
                        }
                      }
                    },
                    child: const Text('ลบต่อ'),
                  ),
                ),
              )
            else
              _ProfilePost(
                post: post,
                currentUser: widget.user,
                onEdit: _isOwnProfile
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<bool>(
                          builder: (_) =>
                              CreatePostScreen(user: widget.user, post: post),
                        ),
                      )
                    : null,
                onDelete: _isOwnProfile ? () => _deleteProfilePost(post) : null,
              ),
          if (postsSnapshot.data!.docs.length >= _postsLimit)
            TextButton(
              onPressed: () => setState(() => _postsLimit += 30),
              child: const Text('โหลดโพสต์เก่าเพิ่มเติม'),
            ),
        ],
      );
    },
  );

  Stream<QuerySnapshot<Map<String, dynamic>>> _postsStream({
    required bool includeFollowers,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('posts')
        .where('userId', isEqualTo: _profileUid);
    if (!_isOwnProfile) {
      query = includeFollowers
          ? query.where('visibility', whereIn: ['public', 'followers'])
          : query.where('visibility', isEqualTo: 'public');
      // ผู้ติดตามที่อนุมัติอ่านโพสต์ทั่วไปได้แม้เจ้าของเป็นบัญชีส่วนตัว
      if (!includeFollowers) {
        query = query.where('authorIsPrivate', isEqualTo: false);
      }
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

/// ใช้ร่วมกันทั้งผู้ติดตาม/กำลังติดตาม ส่ง UID ของแถวที่แตะกลับไปเปิดโปรไฟล์
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
                        final name = readName(person['displayName']);
                        return ListTile(
                          leading: MemberAvatar(uid: uid, radius: 22),
                          title: Text(name),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).pop(uid),
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
                          leading: MemberAvatar(uid: requesterUid, radius: 22),
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
  const _ProfilePost({
    required this.post,
    required this.currentUser,
    this.onEdit,
    this.onDelete,
  });
  final Post post;
  final User currentUser;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  Future<void> _openComments(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostCommentsScreen(user: currentUser, post: post),
        ),
      );

  void _openTag(BuildContext context, String tag) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SearchExploreScreen(user: currentUser, initialTag: tag),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (post.sharedPostId != null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              if (post.content.isNotEmpty || post.taggedUserIds.isNotEmpty) ...[
                const SizedBox(height: 10),
                TaggedPostContent(post: post),
              ],
              SharedPostCard(postId: post.sharedPostId!),
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildPostTags(context),
              ],
              const SizedBox(height: 8),
              PostEngagementBar(
                post: post,
                onComment: () => _openComments(context),
              ),
            ],
          ),
        ),
      );
    }
    if (post.mediaPath == null) return _buildTextPost(context);

    // ใช้หัวโพสต์เดียวกับโพสต์ข้อความ รูปและวิดีโอจึงเห็นเจ้าของกับปุ่มแก้ไขด้วย
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            if (post.content.isNotEmpty || post.taggedUserIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              TaggedPostContent(post: post),
            ],
            const SizedBox(height: 8),
            PostMedia(
              path: post.mediaPath!,
              type: post.mediaType,
              thumbnailPath: post.thumbnailPath,
            ),
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPostTags(context),
            ],
            const SizedBox(height: 8),
            PostEngagementBar(
              post: post,
              onComment: () => _openComments(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final createdAt = post.createdAt.toLocal();
    final timestamp =
        '${createdAt.day.toString().padLeft(2, '0')}/'
        '${createdAt.month.toString().padLeft(2, '0')}/'
        '${createdAt.year} • '
        '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';

    // เปิดหน้าเจ้าของโพสต์จากรูปหรือชื่อได้เหมือนการแตะใน Feed
    void openOwnerProfile() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileScreen(user: currentUser, profileUid: post.userId),
      ),
    );

    return Row(
      children: [
        // ดู users/{uid} สด จึงเปลี่ยนรูปในโพสต์เก่าได้ทันทีเมื่อแก้โปรไฟล์
        InkWell(
          onTap: openOwnerProfile,
          customBorder: const CircleBorder(),
          child: MemberAvatar(uid: post.userId, radius: 19),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: InkWell(
            onTap: openOwnerProfile,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LiveProfileName(
                    uid: post.userId,
                    fallbackName: post.authorName,
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
          ),
        ),
        if (onEdit != null && onDelete != null)
          PopupMenuButton<String>(
            tooltip: 'จัดการโพสต์',
            onSelected: (action) {
              if (action == 'edit') onEdit!();
              if (action == 'delete') onDelete!();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('แก้ไขโพสต์'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('ลบโพสต์'),
                ),
              ),
            ],
          )
        else if (onEdit != null)
          IconButton(
            onPressed: onEdit,
            tooltip: 'แก้ไขโพสต์',
            icon: const Icon(Icons.edit_outlined),
          )
        else
          const SizedBox(width: 4),
      ],
    );
  }

  /// แยกโพสต์ข้อความล้วนให้เนื้อหาเป็นจุดเด่น พร้อมเวลาและแท็กที่อ่านง่าย
  Widget _buildTextPost(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(16),
              ),
              child: post.content.isEmpty && post.taggedUserIds.isEmpty
                  ? Text(
                      'โพสต์ข้อความ',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(height: 1.5, fontWeight: FontWeight.w500),
                    )
                  : TaggedPostContent(
                      post: post,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(height: 1.5, fontWeight: FontWeight.w500),
                    ),
            ),
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildPostTags(context),
            ],
            const SizedBox(height: 8),
            PostEngagementBar(
              post: post,
              onComment: () => _openComments(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostTags(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: post.tags
        .map(
          (tag) => ActionChip(
            label: Text('#$tag'),
            onPressed: () => _openTag(context, tag),
          ),
        )
        .toList(),
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
