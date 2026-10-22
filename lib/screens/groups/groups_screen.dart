// รายการกลุ่มที่ค้นพบได้ พร้อมสร้างกลุ่มและเปิดหน้าสนทนาในกลุ่ม
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/group_reaction_service.dart';
import '../../core/models/social_group.dart';
import '../../core/utils/document_values.dart';
import '../../core/models/social_reaction.dart';
import '../../core/services/group_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_media.dart';
import '../../core/widgets/group_editor_dialog.dart';
import '../../core/widgets/social_reaction_picker.dart';
import '../profile/profile.dart';

/// แสดงกลุ่มสาธารณะและเปิดทางสร้างกลุ่มใหม่
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.user});
  final User user;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _service = GroupService();
  late Stream<List<SocialGroup>> _groupsStream;

  @override
  void initState() {
    super.initState();
    _groupsStream = _service.watchDiscoverableGroups();
  }

  void _retryGroupLoad() {
    setState(() => _groupsStream = _service.watchDiscoverableGroups());
  }

  String _groupLoadMessage(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'บัญชีนี้ไม่มีสิทธิ์อ่านรายการกลุ่ม กรุณาตรวจว่าลงชื่อเข้าใช้แล้วและ Deploy Firestore Rules รุ่นล่าสุด';
        case 'unauthenticated':
          return 'เซสชันหมดอายุ กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'เชื่อมต่อ Firestore ไม่ได้ กรุณาตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง';
        default:
          return 'โหลดรายการกลุ่มไม่สำเร็จ กรุณาลองอีกครั้ง';
      }
    }
    return 'โหลดรายการกลุ่มไม่สำเร็จ กรุณาลองอีกครั้ง';
  }

  Future<void> _createGroup() async {
    final draft = await showDialog<GroupDraft>(
      context: context,
      builder: (_) => const GroupEditorDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      await _service.createGroup(
        name: draft.name,
        description: draft.description,
        visibility: draft.visibility,
        avatar: draft.avatar,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  void _openGroup(SocialGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(user: widget.user, group: group),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('กลุ่ม'),
      actions: [
        IconButton(
          tooltip: 'สร้างกลุ่ม',
          onPressed: _createGroup,
          icon: const Icon(Icons.group_add_outlined),
        ),
      ],
    ),
    body: StreamBuilder<List<SocialGroup>>(
      stream: _groupsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          final details = error is FirebaseException
              ? '${error.code}${error.message == null ? '' : ': ${error.message}'}'
              : error.toString();
          return _GroupLoadState(
            message: _groupLoadMessage(error),
            details: details,
            isError: true,
            onRetry: _retryGroupLoad,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = snapshot.data!;
        if (groups.isEmpty) return const _GroupsEmpty();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _GroupCard(
            group: groups[index],
            user: widget.user,
            service: _service,
            onTap: () => _openGroup(groups[index]),
          ),
        );
      },
    ),
  );
}

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.user, required this.group});
  final User user;
  final SocialGroup group;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _service = GroupService();
  final _picker = ImagePicker();
  final _postController = TextEditingController();
  final _postFocusNode = FocusNode();
  late SocialGroup _group;
  XFile? _attachment;
  bool _sending = false;
  int _postsLimit = 30;
  bool _membershipBusy = false;
  bool _legacyCountSyncStarted = false;
  bool _isAdmin = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _groupSubscription;
  bool _groupRemoved = false;
  bool _groupLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _groupSubscription = FirebaseFirestore.instance
        .collection('groups')
        .doc(_group.id)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              _groupLoadFailed = false;
              _groupRemoved = !snapshot.exists;
              if (snapshot.exists) _group = SocialGroup.fromSnapshot(snapshot);
            });
          },
          onError: (Object error) {
            if (mounted) setState(() => _groupLoadFailed = true);
          },
        );
    _loadAdminClaim();
  }

  Future<void> _loadAdminClaim() async {
    try {
      final token = await widget.user.getIdTokenResult(true);
      if (mounted && token.claims?['admin'] == true) {
        setState(() => _isAdmin = true);
      }
    } catch (_) {
      // Keep standard member access when the optional admin claim is unavailable.
    }
  }

  @override
  void dispose() {
    _groupSubscription?.cancel();
    _postController.dispose();
    _postFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendPost() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await _service.addPost(
        groupId: _group.id,
        content: _postController.text,
        attachment: _attachment,
      );
      if (mounted) {
        _postController.clear();
        setState(() => _attachment = null);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() => _pickGroupMedia(image: true);
  Future<void> _pickVideo() => _pickGroupMedia(image: false);

  Future<void> _pickGroupMedia({required bool image}) async {
    _postFocusNode.unfocus();
    try {
      final file = image
          ? await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              maxWidth: 1600,
              maxHeight: 1600,
            )
          : await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      final maximum = (image ? 10 : 50) * 1024 * 1024;
      if (await file.length() > maximum) {
        throw FormatException(
          image ? 'รูปต้องไม่เกิน 10 MB' : 'วิดีโอต้องไม่เกิน 50 MB',
        );
      }
      if (mounted) setState(() => _attachment = file);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เลือกไฟล์ไม่สำเร็จ: $error')));
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _postFocusNode.requestFocus();
      });
    }
  }

  Future<void> _editGroup() async {
    final draft = await showDialog<GroupDraft>(
      context: context,
      builder: (_) => GroupEditorDialog(
        editing: true,
        initialName: _group.name,
        initialDescription: _group.description,
        initialVisibility: _group.visibility,
        existingAvatar: _GroupAvatar(group: _group, radius: 38),
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _service.updateGroup(
        groupId: _group.id,
        name: draft.name,
        description: draft.description,
        avatar: draft.avatar,
      );
      final updated = await FirebaseFirestore.instance
          .collection('groups')
          .doc(_group.id)
          .get();
      if (mounted && updated.exists) {
        setState(() => _group = SocialGroup.fromSnapshot(updated));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _membershipAction({
    required bool isMember,
    required bool hasRequest,
  }) async {
    if (_membershipBusy) return;
    setState(() => _membershipBusy = true);
    try {
      if (isMember) {
        await _service.leaveGroup(_group);
        if (mounted) {
          Navigator.pop(context);
        }
      } else if (hasRequest) {
        await _service.cancelJoinRequest(_group.id);
      } else if (_group.visibility == 'private') {
        await _service.requestToJoin(_group);
      } else {
        await _service.joinGroup(_group);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _membershipBusy = false);
    }
  }

  void _openOwnerProfile() {
    if (_group.ownerId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileScreen(user: widget.user, profileUid: _group.ownerId),
      ),
    );
  }

  void _showGroupMembers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupMembersSheet(
        groupId: _group.id,
        service: _service,
        ownerId: _group.ownerId,
      ),
    );
  }

  void _showJoinRequests() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _GroupJoinRequestsSheet(groupId: _group.id, service: _service),
    );
  }

  void _showManageGroupOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text(
                'จัดการกลุ่ม',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_group.visibility == 'private')
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('คำขอเข้าร่วม'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showJoinRequests();
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('แก้ไขข้อมูลกลุ่ม'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editGroup();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('ลบกลุ่ม'),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteGroup();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// ขอคำยืนยันก่อนลบกลุ่ม รวมถึงสมาชิกและโพสต์ที่อยู่ภายในกลุ่ม
  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบกลุ่มนี้?'),
        content: const Text('สมาชิกและโพสต์ทั้งหมดในกลุ่มจะถูกลบถาวร'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบกลุ่ม'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deleteGroup(_group.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ลบกลุ่มไม่สำเร็จ: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final isOwner = group.ownerId == widget.user.uid;
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (isOwner || _isAdmin)
            IconButton(
              tooltip: 'จัดการกลุ่ม',
              onPressed: isOwner ? _showManageGroupOptions : _showJoinRequests,
              icon: const Icon(Icons.more_vert_rounded),
            ),
        ],
      ),
      body: _groupRemoved
          ? const Center(child: Text('กลุ่มนี้ถูกลบแล้ว'))
          : _groupLoadFailed
          ? const Center(
              child: Text('โหลดข้อมูลกลุ่มไม่สำเร็จ กรุณาเปิดกลุ่มอีกครั้ง'),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _service.watchMembership(group.id),
              builder: (context, membershipSnapshot) {
                if (membershipSnapshot.hasError) {
                  return const _GroupLoadState(
                    message: 'ตรวจสอบสถานะสมาชิกไม่สำเร็จ',
                    isError: true,
                  );
                }
                if (!membershipSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final isMember =
                    isOwner || membershipSnapshot.data?.exists == true;
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _service.watchJoinRequest(group.id),
                  builder: (context, requestSnapshot) {
                    if (requestSnapshot.hasError) {
                      return const _GroupLoadState(
                        message: 'โหลดสถานะคำขอเข้าร่วมไม่สำเร็จ',
                        isError: true,
                      );
                    }
                    if (!requestSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final hasRequest = requestSnapshot.data?.exists == true;
                    final canReadMembers =
                        group.visibility == 'public' || isMember || isOwner;
                    if (!canReadMembers) {
                      return _buildGroupContent(
                        isOwner: isOwner,
                        isMember: isMember,
                        hasRequest: hasRequest,
                        memberCount: group.memberCount,
                      );
                    }
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _service.watchMembers(group.id),
                      builder: (context, memberSnapshot) {
                        if (memberSnapshot.hasError) {
                          return const _GroupLoadState(
                            message: 'โหลดข้อมูลสมาชิกไม่สำเร็จ',
                            isError: true,
                          );
                        }
                        if (!memberSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final members = memberSnapshot.data?.docs;
                        if (isOwner &&
                            group.memberCount == null &&
                            members != null &&
                            !_legacyCountSyncStarted) {
                          _legacyCountSyncStarted = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _service.ensureMemberCount(group.id).catchError((
                              _,
                            ) {
                              _legacyCountSyncStarted = false;
                            });
                          });
                        }
                        return _buildGroupContent(
                          isOwner: isOwner,
                          isMember: isMember,
                          hasRequest: hasRequest,
                          memberCount: members?.length ?? group.memberCount,
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildGroupContent({
    required bool isOwner,
    required bool isMember,
    required bool hasRequest,
    required int? memberCount,
  }) {
    final canReadMembers = _group.visibility == 'public' || isMember || isOwner;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: _GroupDetailHeader(
            group: _group,
            memberCount: memberCount,
            isOwner: isOwner,
            isMember: isMember,
            hasRequest: hasRequest,
            busy: _membershipBusy || _group.isDeleting,
            onOwnerTap: _openOwnerProfile,
            onMembersTap: canReadMembers ? _showGroupMembers : null,
            onManageTap: _showManageGroupOptions,
            onMembershipTap: () =>
                _membershipAction(isMember: isMember, hasRequest: hasRequest),
          ),
        ),
        if ((isOwner || _isAdmin) && _group.visibility == 'private')
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _service.watchJoinRequests(_group.id),
                builder: (context, requests) => OutlinedButton.icon(
                  onPressed: _showJoinRequests,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    'คำขอเข้าร่วม (${requests.data?.docs.length ?? 0})',
                  ),
                ),
              ),
            ),
          ),
        if (_group.isDeleting)
          SliverToBoxAdapter(
            child: ListTile(
              title: const Text('กำลังลบกลุ่ม'),
              subtitle: const Text(
                'ไม่สามารถเพิ่มเนื้อหาหรือเข้าร่วมระหว่างลบได้',
              ),
              trailing: isOwner
                  ? TextButton(
                      onPressed: _deleteGroup,
                      child: const Text('ลบต่อ'),
                    )
                  : null,
            ),
          ),
        if (isMember && !_group.isDeleting)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _groupComposer(),
            ),
          ),
        if (!isMember)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _GroupJoinMessage(
              isPrivate: _group.visibility == 'private',
              hasRequest: hasRequest,
            ),
          )
        else
          StreamBuilder<List<GroupPost>>(
            stream: _service.watchPosts(_group.id, limit: _postsLimit),
            builder: (context, postSnapshot) {
              if (postSnapshot.hasError) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _GroupLoadState(
                    message: 'โหลดโพสต์กลุ่มไม่สำเร็จ',
                    isError: true,
                  ),
                );
              }
              if (!postSnapshot.hasData) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final posts = postSnapshot.data!;
              if (posts.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _GroupLoadState(message: 'กลุ่มยังไม่มีโพสต์'),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => index == posts.length
                        ? TextButton(
                            onPressed: () => setState(() => _postsLimit += 30),
                            child: const Text('โหลดโพสต์เก่าเพิ่มเติม'),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _GroupPostCard(
                              groupId: _group.id,
                              post: posts[index],
                              user: widget.user,
                            ),
                          ),
                    childCount:
                        posts.length + (posts.length >= _postsLimit ? 1 : 0),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _groupComposer() => Column(
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _postController,
              focusNode: _postFocusNode,
              enabled: !_sending,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              onTap: () => _postFocusNode.requestFocus(),
              decoration: const InputDecoration(
                hintText: 'เขียนโพสต์ในกลุ่ม',
                counterText: '',
                alignLabelWithHint: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: IconButton.filled(
              tooltip: 'โพสต์',
              onPressed: _sending ? null : _sendPost,
              icon: const Icon(Icons.send_rounded),
            ),
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: _sending ? null : _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Photo'),
            ),
            TextButton.icon(
              onPressed: _sending ? null : _pickVideo,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Video'),
            ),
            if (_attachment != null)
              Chip(
                label: Text(_attachment!.name, overflow: TextOverflow.ellipsis),
                onDeleted: _sending
                    ? null
                    : () => setState(() => _attachment = null),
              ),
          ],
        ),
      ),
    ],
  );
}

class _GroupDetailHeader extends StatelessWidget {
  const _GroupDetailHeader({
    required this.group,
    required this.memberCount,
    required this.isOwner,
    required this.isMember,
    required this.hasRequest,
    required this.busy,
    required this.onOwnerTap,
    required this.onMembersTap,
    required this.onManageTap,
    required this.onMembershipTap,
  });

  final SocialGroup group;
  final int? memberCount;
  final bool isOwner;
  final bool isMember;
  final bool hasRequest;
  final bool busy;
  final VoidCallback onOwnerTap;
  final VoidCallback? onMembersTap;
  final VoidCallback onManageTap;
  final VoidCallback onMembershipTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isPrivate = group.visibility == 'private';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GroupAvatar(group: group, radius: 30),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 7),
                      _GroupVisibilityBadge(visibility: group.visibility),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: onOwnerTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _GroupOwnerName(
                        ownerId: group.ownerId,
                        prefix: 'เจ้าของกลุ่ม:',
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            InkWell(
              onTap: onMembersTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.groups_2_outlined,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        memberCount == null
                            ? 'จำนวนสมาชิกยังไม่พร้อม'
                            : '$memberCount สมาชิก',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (onMembersTap != null)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'เกี่ยวกับกลุ่ม',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    group.description.trim().isEmpty
                        ? 'ยังไม่มีคำอธิบายกลุ่ม'
                        : group.description,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isPrivate ? Icons.lock_outline_rounded : Icons.public_rounded,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isPrivate
                        ? 'ส่งคำขอเข้าร่วมได้ โพสต์จะแสดงหลังเจ้าของอนุมัติ'
                        : 'กลุ่มสาธารณะ เข้าร่วมและดูโพสต์ได้ทันที',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isOwner)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onManageTap,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('จัดการกลุ่ม'),
                ),
              )
            else if (isMember)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onMembershipTap,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout_rounded),
                  label: const Text('ออกจากกลุ่ม'),
                ),
              )
            else if (hasRequest)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.hourglass_top_rounded),
                      label: const Text('รอการอนุมัติ'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: busy ? null : onMembershipTap,
                    child: const Text('ยกเลิกคำขอ'),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : onMembershipTap,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isPrivate
                              ? Icons.lock_open_rounded
                              : Icons.group_add_outlined,
                        ),
                  label: Text(isPrivate ? 'ส่งคำขอเข้าร่วม' : 'เข้าร่วม'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupJoinMessage extends StatelessWidget {
  const _GroupJoinMessage({required this.isPrivate, required this.hasRequest});

  final bool isPrivate;
  final bool hasRequest;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPrivate ? Icons.lock_outline_rounded : Icons.groups_2_outlined,
            size: 38,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            hasRequest
                ? 'ส่งคำขอแล้ว โพสต์จะเปิดให้ดูเมื่อเจ้าของอนุมัติ'
                : isPrivate
                ? 'กลุ่มนี้เป็นส่วนตัว ส่งคำขอและรอเจ้าของอนุมัติก่อนเข้าดูโพสต์'
                : 'เข้าร่วมกลุ่มเพื่อดูโพสต์และเขียนข้อความ',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class _GroupLoadState extends StatelessWidget {
  const _GroupLoadState({
    required this.message,
    this.isError = false,
    this.details,
    this.onRetry,
  });

  final String message;
  final bool isError;
  final String? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.cloud_off_outlined : Icons.groups_2_outlined,
            size: 38,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (details != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              details!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('ลองอีกครั้ง'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _GroupMembersSheet extends StatelessWidget {
  const _GroupMembersSheet({
    required this.groupId,
    required this.service,
    required this.ownerId,
  });

  final String groupId;
  final GroupService service;
  final String ownerId;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'สมาชิกกลุ่ม',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: service.watchMembers(groupId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _GroupLoadState(
                    message: 'โหลดรายชื่อสมาชิกไม่สำเร็จ',
                    isError: true,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final members = snapshot.data!.docs;
                if (members.isEmpty) {
                  return const _GroupLoadState(message: 'ยังไม่มีสมาชิก');
                }
                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final data = members[index].data();
                    final name = readName(data['displayName']);
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(name.characters.first.toUpperCase()),
                      ),
                      title: Text(name),
                      trailing: members[index].id == ownerId
                          ? const Chip(label: Text('เจ้าของ'))
                          : null,
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

class _GroupJoinRequestsSheet extends StatelessWidget {
  const _GroupJoinRequestsSheet({required this.groupId, required this.service});

  final String groupId;
  final GroupService service;

  Future<void> _respond(
    BuildContext context,
    GroupJoinRequest request,
    bool approve,
  ) async {
    try {
      if (approve) {
        await service.approveJoinRequest(
          groupId: groupId,
          requesterUid: request.uid,
        );
      } else {
        await service.rejectJoinRequest(
          groupId: groupId,
          requesterUid: request.uid,
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'คำขอเข้าร่วมกลุ่ม',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: service.watchJoinRequests(groupId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _GroupLoadState(
                    message: 'โหลดคำขอเข้าร่วมไม่สำเร็จ',
                    isError: true,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final requests = snapshot.data!.docs
                    .map(GroupJoinRequest.fromSnapshot)
                    .toList();
                if (requests.isEmpty) {
                  return const _GroupLoadState(message: 'ยังไม่มีคำขอเข้าร่วม');
                }
                return ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          request.displayName.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Text(
                        request.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Text('รอการอนุมัติ'),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: 'อนุมัติ',
                            onPressed: () => _respond(context, request, true),
                            color: AppTheme.primary,
                            icon: const Icon(Icons.check_circle_outline),
                          ),
                          IconButton(
                            tooltip: 'ปฏิเสธ',
                            onPressed: () => _respond(context, request, false),
                            icon: const Icon(Icons.cancel_outlined),
                          ),
                        ],
                      ),
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

class _GroupCard extends StatefulWidget {
  const _GroupCard({
    required this.group,
    required this.user,
    required this.service,
    required this.onTap,
  });

  final SocialGroup group;
  final User user;
  final GroupService service;
  final VoidCallback onTap;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _busy = false;

  Future<void> _membershipAction({required bool cancelRequest}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (cancelRequest) {
        await widget.service.cancelJoinRequest(widget.group.id);
      } else if (widget.group.visibility == 'private') {
        await widget.service.requestToJoin(widget.group);
      } else {
        await widget.service.joinGroup(widget.group);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _action({
    required bool isOwner,
    required bool isMember,
    required bool hasRequest,
  }) {
    if (isOwner) {
      return TextButton.icon(
        onPressed: widget.onTap,
        icon: const Icon(Icons.settings_outlined, size: 18),
        label: const Text('จัดการกลุ่ม'),
      );
    }
    if (isMember) {
      return TextButton.icon(
        onPressed: widget.onTap,
        icon: const Icon(Icons.login_rounded, size: 18),
        label: const Text('เข้ากลุ่ม'),
      );
    }
    if (hasRequest) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            'รอการอนุมัติ',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _membershipAction(cancelRequest: true),
            child: const Text('ยกเลิกคำขอ'),
          ),
        ],
      );
    }
    return TextButton.icon(
      onPressed: _busy ? null : () => _membershipAction(cancelRequest: false),
      icon: Icon(
        widget.group.visibility == 'private'
            ? Icons.lock_outline_rounded
            : Icons.group_add_outlined,
        size: 18,
      ),
      label: Text(
        widget.group.visibility == 'private' ? 'ส่งคำขอเข้าร่วม' : 'เข้าร่วม',
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: widget.service.watchMembership(widget.group.id),
    builder: (context, memberSnapshot) {
      if (memberSnapshot.hasError) {
        return const Center(child: Text('ตรวจสอบสถานะสมาชิกไม่สำเร็จ'));
      }
      if (!memberSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final isOwner = widget.group.ownerId == widget.user.uid;
      final isMember = memberSnapshot.data?.exists == true;
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: widget.service.watchJoinRequest(widget.group.id),
        builder: (context, requestSnapshot) {
          if (requestSnapshot.hasError) {
            return const Center(child: Text('ตรวจสอบคำขอเข้าร่วมไม่สำเร็จ'));
          }
          if (!requestSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final hasRequest = requestSnapshot.data?.exists == true;
          final canReadMembers =
              widget.group.visibility == 'public' || isOwner || isMember;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 6),
              child: Column(
                children: [
                  InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(14),
                    child: Row(
                      children: [
                        _GroupAvatar(group: widget.group, radius: 27),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.group.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              _GroupOwnerName(
                                ownerId: widget.group.ownerId,
                                prefix: 'สร้างโดย',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _GroupVisibilityBadge(
                        visibility: widget.group.visibility,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _GroupMemberCount(
                          group: widget.group,
                          service: widget.service,
                          canReadMembers: canReadMembers,
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: widget.group.isDeleting
                        ? TextButton(
                            onPressed: widget.onTap,
                            child: const Text('กำลังลบกลุ่ม'),
                          )
                        : _busy
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _action(
                            isOwner: isOwner,
                            isMember: isMember,
                            hasRequest: hasRequest,
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _GroupOwnerName extends StatelessWidget {
  const _GroupOwnerName({required this.ownerId, required this.prefix});

  final String ownerId;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    if (ownerId.isEmpty) return Text('$prefix ไม่ทราบชื่อ');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            '$prefix ไม่พบข้อมูล',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        if (!snapshot.hasData) {
          return Text(
            '$prefix กำลังโหลดชื่อ…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        final name = readOptionalString(snapshot.data?.data()?['displayName'])
            ?.trim();
        return Text(
          '$prefix ${name == null || name.isEmpty ? 'ไม่ทราบชื่อ' : name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
      },
    );
  }
}

class _GroupVisibilityBadge extends StatelessWidget {
  const _GroupVisibilityBadge({required this.visibility});

  final String visibility;

  @override
  Widget build(BuildContext context) {
    final isPrivate = visibility == 'private';
    final color = isPrivate
        ? AppTheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isPrivate
            ? AppTheme.primary.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPrivate ? Icons.lock_outline_rounded : Icons.public_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isPrivate ? 'ส่วนตัว' : 'สาธารณะ',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _GroupMemberCount extends StatelessWidget {
  const _GroupMemberCount({
    required this.group,
    required this.service,
    required this.canReadMembers,
  });

  final SocialGroup group;
  final GroupService service;
  final bool canReadMembers;

  @override
  Widget build(BuildContext context) {
    if (group.memberCount != null) {
      return _label(context, '${group.memberCount} สมาชิก');
    }
    if (!canReadMembers) return _label(context, 'จำนวนสมาชิกยังไม่พร้อม');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchMembers(group.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _label(context, 'โหลดจำนวนสมาชิกไม่ได้');
        if (!snapshot.hasData) return _label(context, 'กำลังโหลดสมาชิก…');
        return _label(context, '${snapshot.data!.docs.length} สมาชิก');
      },
    );
  }

  Widget _label(BuildContext context, String value) => Row(
    children: [
      Icon(
        Icons.people_outline_rounded,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.group, required this.radius});

  final SocialGroup group;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = group.avatarPath;
    final colors = Theme.of(context).colorScheme;
    Widget placeholder() => CircleAvatar(
      radius: radius,
      backgroundColor: colors.secondaryContainer,
      child: Icon(
        Icons.groups_2_outlined,
        size: radius,
        color: colors.onSecondaryContainer,
      ),
    );
    if (path == null || path.isEmpty) return placeholder();
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path).getDownloadURL(),
      builder: (context, snapshot) {
        if (snapshot.data == null) return placeholder();
        return CircleAvatar(
          radius: radius,
          backgroundColor: colors.secondaryContainer,
          backgroundImage: NetworkImage(snapshot.data!),
        );
      },
    );
  }
}

class _GroupPostCard extends StatelessWidget {
  const _GroupPostCard({
    required this.groupId,
    required this.post,
    required this.user,
  });

  final String groupId;
  final GroupPost post;
  final User user;

  static final _reactionService = GroupReactionService();

  Future<void> _toggleReaction(BuildContext context, String reaction) async {
    try {
      await _reactionService.toggleReaction(
        groupId: groupId,
        postId: post.id,
        reaction: reaction,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
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
          if (post.mediaPath != null) ...[
            const SizedBox(height: 10),
            PostMedia(
              path: post.mediaPath!,
              type: post.mediaType,
              thumbnailPath: post.thumbnailPath,
            ),
          ],
          const Divider(height: 24),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _reactionService.watchReactions(groupId, post.id),
            builder: (context, snapshot) {
              final reactions = snapshot.data?.docs ?? const [];
              final myReactions = reactions
                  .where((reaction) => reaction.id == user.uid)
                  .toList();
              final mine = myReactions.isEmpty
                  ? null
                  : readOptionalString(myReactions.first.data()['reaction']);
              final counts = <String, int>{
                for (final reaction in SocialReaction.options) reaction.id: 0,
              };
              for (final reaction in reactions) {
                final id = readOptionalString(reaction.data()['reaction']);
                if (id != null && counts.containsKey(id)) {
                  counts.update(id, (total) => total + 1);
                }
              }
              final selected = SocialReaction.byId(mine);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (counts.values.any((total) => total > 0))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 8,
                        children: counts.entries
                            .where((entry) => entry.value > 0)
                            .map(
                              (entry) => Text(
                                '${SocialReaction.byId(entry.key)?.emoji} ${entry.value}',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (buttonContext) => TextButton.icon(
                            onPressed: () => _toggleReaction(context, 'like'),
                            onLongPress: () async {
                              final reaction = await SocialReactionPicker.show(
                                buttonContext,
                              );
                              if (reaction != null && context.mounted) {
                                await _toggleReaction(context, reaction);
                              }
                            },
                            icon: selected != null && selected.id != 'dislike'
                                ? Text(
                                    selected.emoji,
                                    style: const TextStyle(fontSize: 18),
                                  )
                                : Icon(
                                    mine == 'like'
                                        ? Icons.thumb_up
                                        : Icons.thumb_up_outlined,
                                  ),
                            label: Text(
                              selected != null && selected.id != 'dislike'
                                  ? selected.label
                                  : 'Like',
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => _toggleReaction(context, 'dislike'),
                          icon: Icon(
                            mine == 'dislike'
                                ? Icons.thumb_down
                                : Icons.thumb_down_outlined,
                          ),
                          label: const Text('Dislike'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _GroupsEmpty extends StatelessWidget {
  const _GroupsEmpty();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_2_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          const Text('ยังไม่มีกลุ่ม'),
          const SizedBox(height: 5),
          const Text('สร้างกลุ่มแรกหรือกลับมาดูภายหลัง'),
        ],
      ),
    ),
  );
}
