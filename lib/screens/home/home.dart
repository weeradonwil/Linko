// หน้า Feed หลัก เชื่อมการโหลดโพสต์ การจัดการโพสต์ และทางลัดไปฟีเจอร์อื่น
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../core/models/post.dart';
import '../../core/utils/document_values.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/post_service.dart';
import '../../core/services/reaction_service.dart';
import '../../core/models/social_reaction.dart';
import '../../core/widgets/post_media.dart';
import '../../core/widgets/post_report_dialog.dart';
import '../../core/widgets/social_reaction_picker.dart';
import '../../core/widgets/social_navigation.dart';
import '../create_post/create_post.dart';
import '../chat/chat_list.dart';
import '../comments/post_comments_screen.dart';
import '../notifications/notifications_screen.dart';
import '../search/search_explore.dart';
import '../profile/profile.dart';
import '../groups/groups_screen.dart';

/// หน้าฟีดหลังล็อกอิน: แสดงโพสต์เรียงเวลาและเปิดทางสร้าง/จัดการโพสต์ของตนเอง
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.user,
    this.isDarkMode = false,
    this.onToggleTheme,
    super.key,
  });

  /// User ที่ AuthGate ส่งมา จึงเป็นบัญชีที่ล็อกอินอยู่ในขณะนี้
  final User user;

  /// Theme ที่กำลังแสดง ใช้แสดงไอคอน/คำอธิบายของปุ่มสลับ
  final bool isDarkMode;

  /// ฟังก์ชันจาก SocialApp สำหรับเปลี่ยนและจำโหมดสีที่ผู้ใช้เลือก
  final VoidCallback? onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _legacyMigrationComplete = <String>{};
  static final _legacyMigrationRunning = <String>{};

  final _feedScrollController = ScrollController();
  final _reactionService = ReactionService();
  int _feedGeneration = 0;
  int _feedLimit = 30;
  late Stream<List<Post>> _feed;

  @override
  void initState() {
    super.initState();
    _feed = PostService().watchFeed(limit: _feedLimit);
  }

  void _loadOlder() => setState(() {
    _feedLimit += 30;
    _feed = PostService().watchFeed(limit: _feedLimit);
  });

  void _restartFeed() {
    setState(() {
      _feedGeneration++;
      _feed = PostService().watchFeed(limit: _feedLimit);
    });
    if (_feedScrollController.hasClients) {
      _feedScrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _feedScrollController.dispose();
    super.dispose();
  }

  /// เปิดหน้าสร้างโพสต์; Navigator.push ซ้อนหน้าใหม่ไว้บน Home
  Future<void> _openCreatePost(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreatePostScreen(user: widget.user)),
    );
  }

  /// ส่ง Post เดิมไปให้ฟอร์ม เพื่อแสดงเนื้อหาเดิมและบันทึกทับ document เดิม
  Future<void> _openEditPost(BuildContext context, Post post) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(user: widget.user, post: post),
      ),
    );
  }

  /// ขอคำยืนยันก่อนลบ เพราะการลบจะนำ document ออกจาก Firestore อย่างถาวร
  Future<void> _deletePost(BuildContext context, Post post) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบโพสต์นี้?'),
        content: const Text('เมื่อลบแล้วจะไม่สามารถกู้คืนโพสต์ได้'),
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

    // กดยกเลิกแล้วหยุด; mounted ตรวจว่า Home ยังอยู่บนหน้าจอก่อนใช้ context ต่อ
    if (shouldDelete != true || !context.mounted) return;

    try {
      await PostService().deletePost(post);
    } catch (_) {
      // กรณี Rules ปฏิเสธหรือเครือข่ายขัดข้อง แจ้งผู้ใช้แทนการปิดแอป
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ลบโพสต์ไม่สำเร็จ ตรวจสิทธิ์และการเชื่อมต่อแล้วลองอีกครั้ง',
          ),
        ),
      );
    }
  }

  /// Opens the live comment thread for the selected post.
  void _openComments(BuildContext context, Post post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostCommentsScreen(user: widget.user, post: post),
      ),
    );
  }

  /// เปิดแบบฟอร์มรายงาน ให้ผู้ใช้เลือกเหตุผลและส่งรายงานไปเก็บใน Firestore
  Future<void> _reportPost(BuildContext context, Post post) async {
    final draft = await showDialog<PostReportDraft>(
      context: context,
      builder: (_) => const PostReportDialog(),
    );
    if (draft == null || !context.mounted) return;

    try {
      await PostService().reportPost(
        post: post,
        reason: draft.reason,
        details: draft.details,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ขอบคุณที่ช่วยรายงานโพสต์นี้')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ส่งรายงานไม่สำเร็จ กรุณาตรวจ Firestore Rules'),
        ),
      );
    }
  }

  /// สลับ reaction ของผู้ใช้ปัจจุบัน; เลือกแบบเดิมซ้ำจะยกเลิก reaction
  Future<void> _setReaction(
    BuildContext context,
    Post post,
    String reaction,
  ) async {
    try {
      await _reactionService.toggleReaction(
        postId: post.id,
        reaction: reaction,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกความรู้สึกไม่สำเร็จ: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ใช้ชื่อจาก Firebase Auth ถ้าไม่มีชื่อให้แสดงคำว่า "สมาชิก"
    final name = widget.user.displayName?.trim();
    final title = (name == null || name.isEmpty) ? 'สมาชิก' : name;
    final postService = PostService();

    // ค่อย ๆ เติม fields ใหม่ให้โพสต์เก่าของเจ้าของ โดยไม่เปลี่ยนข้อมูลในโพสต์ใหม่
    if (!_legacyMigrationComplete.contains(widget.user.uid) &&
        _legacyMigrationRunning.add(widget.user.uid)) {
      unawaited(() async {
        try {
          await postService.normalizeOwnedPosts();
          _legacyMigrationComplete.add(widget.user.uid);
        } catch (_) {
          // ถ้า Rules ปฏิเสธ ให้ลองใหม่เมื่อ Home ถูกสร้างอีกครั้ง
        } finally {
          _legacyMigrationRunning.remove(widget.user.uid);
        }
      }());
    }

    return ScrollNavigationVisibility(
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 20,
          title: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _restartFeed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                  children: [
                    const TextSpan(text: 'Link'),
                    TextSpan(
                      text: 'o',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'ค้นหา',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SearchExploreScreen(
                    user: widget.user,
                    isDarkMode: widget.isDarkMode,
                    onToggleTheme: widget.onToggleTheme,
                  ),
                ),
              ),
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: 'แจ้งเตือน',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NotificationsScreen(
                    user: widget.user,
                    isDarkMode: widget.isDarkMode,
                    onToggleTheme: widget.onToggleTheme,
                  ),
                ),
              ),
              icon: NotificationCountIcon(
                icon: Icons.notifications_none_rounded,
              ),
            ),
            if (widget.onToggleTheme != null)
              IconButton(
                tooltip: widget.isDarkMode
                    ? 'เปลี่ยนเป็นโหมดสว่าง'
                    : 'เปลี่ยนเป็นโหมดมืด',
                onPressed: widget.onToggleTheme,
                icon: Icon(
                  widget.isDarkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
            IconButton(
              tooltip: 'ออกจากระบบ',
              onPressed: () async {
                try {
                  // เมื่อออกจากระบบ AuthGate จะสลับกลับไปหน้า Login จาก stream
                  await AuthService().signOut();
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ออกจากระบบไม่สำเร็จ กรุณาลองอีกครั้ง'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Column(
          children: [
            // ช่องเริ่มโพสต์เป็นทางลัดหลักของหน้า Feed
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openCreatePost(context),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          foregroundColor: Colors.white,
                          child: Text(title.characters.first.toUpperCase()),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Text(
                              'คุณกำลังคิดอะไรอยู่?',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Post>>(
                // snapshots ใน PostService ส่งรายการใหม่ทุกครั้งที่ Firestore เปลี่ยน
                key: ValueKey(_feedGeneration),
                stream: _feed,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    // สถานะผิดพลาด เช่น อ่าน posts ไม่ได้ตาม Rules
                    debugPrint('Feed stream failed: ${snapshot.error}');
                    return _FeedMessage(
                      icon: Icons.cloud_off_outlined,
                      message: 'โหลดฟีดไม่สำเร็จ กรุณาตรวจการเชื่อมต่อและ Firestore Rules',
                      details: kDebugMode ? snapshot.error.toString() : null,
                      onRetry: _restartFeed,
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    // ยังไม่มีข้อมูลครั้งแรก จึงแสดงตัวโหลด
                    return const Center(child: CircularProgressIndicator());
                  }

                  final posts = snapshot.data ?? const <Post>[];
                  if (posts.isEmpty) {
                    // ข้อมูลโหลดสำเร็จแต่ยังไม่มีโพสต์
                    return const _FeedMessage(
                      icon: Icons.forum_outlined,
                      message: 'ยังไม่มีโพสต์ เริ่มแบ่งปันเรื่องราวได้เลย',
                    );
                  }

                  return ListView.separated(
                    controller: _feedScrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount:
                        posts.length + (posts.length >= _feedLimit ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == posts.length) {
                        return TextButton(
                          onPressed: _loadOlder,
                          child: const Text('โหลดโพสต์เก่าเพิ่มเติม'),
                        );
                      }
                      final post = posts[index];
                      if (post.isDeleting) {
                        return Card(
                          child: ListTile(
                            title: const Text('กำลังลบโพสต์'),
                            subtitle: const Text(
                              'หากการลบหยุดลง สามารถลองลบต่อได้',
                            ),
                            trailing: TextButton(
                              onPressed: () => _deletePost(context, post),
                              child: const Text('ลบต่อ'),
                            ),
                          ),
                        );
                      }
                      // ใช้ UID เทียบเจ้าของ; ซ่อนเมนูแก้ไข/ลบสำหรับโพสต์คนอื่น
                      final isOwner = post.userId == widget.user.uid;

                      return _PostCard(
                        post: post,
                        isOwner: isOwner,
                        onEdit: isOwner
                            ? () => _openEditPost(context, post)
                            : null,
                        onDelete: isOwner
                            ? () => _deletePost(context, post)
                            : null,
                        onReport: isOwner
                            ? null
                            : () => _reportPost(context, post),
                        currentUid: widget.user.uid,
                        reactionService: _reactionService,
                        onReaction: (reaction) =>
                            _setReaction(context, post, reaction),
                        onAuthorTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ProfileScreen(
                              user: widget.user,
                              profileUid: post.userId,
                            ),
                          ),
                        ),
                        onComment: () => _openComments(context, post),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: ScrollHidingNavigationBar(
          child: BottomNavigationBar(
            currentIndex: 0,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Theme.of(context).colorScheme.onSurface,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            elevation: 0,
            onTap: (index) {
              if (index == 2) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatListScreen(
                      user: widget.user,
                      isDarkMode: widget.isDarkMode,
                      onToggleTheme: widget.onToggleTheme,
                    ),
                  ),
                );
              } else if (index == 3) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NotificationsScreen(
                      user: widget.user,
                      isDarkMode: widget.isDarkMode,
                      onToggleTheme: widget.onToggleTheme,
                    ),
                  ),
                );
              } else if (index == 1) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupsScreen(user: widget.user),
                  ),
                );
              } else if (index == 4) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileScreen(user: widget.user),
                  ),
                );
              }
            },
            items: [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'หน้าหลัก',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.groups_outlined),
                label: 'กลุ่ม',
              ),
              BottomNavigationBarItem(
                icon: ChatUnreadCountIcon(
                  icon: Icons.chat_bubble_outline_rounded,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                activeIcon: ChatUnreadCountIcon(
                  icon: Icons.chat_bubble_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                label: 'แชท',
              ),
              BottomNavigationBarItem(
                icon: NotificationCountIcon(
                  icon: Icons.notifications_none_rounded,
                ),
                activeIcon: NotificationCountIcon(
                  icon: Icons.notifications_rounded,
                ),
                label: 'แจ้งเตือน',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline_rounded),
                label: 'โปรไฟล์',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// การ์ดหนึ่งรายการในฟีด; เมนูแก้ไข/ลบจะแสดงเฉพาะโพสต์ของผู้ใช้ปัจจุบัน
class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.isOwner,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.currentUid,
    required this.reactionService,
    required this.onReaction,
    required this.onAuthorTap,
    required this.onComment,
  });

  final Post post;
  final bool isOwner;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final String currentUid;
  final ReactionService reactionService;
  final ValueChanged<String> onReaction;
  final VoidCallback onAuthorTap;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    // อ่านสีและรูปแบบตัวอักษรจาก Theme เพื่อรองรับทั้ง Light/Dark mode
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: onAuthorTap,
                  borderRadius: BorderRadius.circular(22),
                  child: CircleAvatar(
                    radius: 20,
                    child: Text(post.authorName.characters.first.toUpperCase()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: onAuthorTap,
                        child: Text(
                          post.authorName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _formatThailandTimestamp(post.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (post.editedAt != null)
                            Text(
                              '· แก้ไขแล้ว',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                post.visibility == 'private'
                                    ? Icons.lock_outline_rounded
                                    : post.visibility == 'followers'
                                    ? Icons.group_outlined
                                    : Icons.public_rounded,
                                size: 15,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                post.visibility == 'private'
                                    ? 'ส่วนตัว'
                                    : post.visibility == 'followers'
                                    ? 'Followers'
                                    : 'สาธารณะ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // รายการเมนูจะไม่ถูกสร้างเลย หากโพสต์นี้ไม่ใช่ของผู้ใช้ปัจจุบัน
                if (isOwner)
                  PopupMenuButton<String>(
                    tooltip: 'จัดการโพสต์',
                    onSelected: (action) {
                      // ส่งการเลือกเมนูกลับไปให้ Home เรียกหน้าแก้ไขหรือขั้นตอนลบ
                      if (action == 'edit') onEdit?.call();
                      if (action == 'delete') onDelete?.call();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('แก้ไข'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('ลบ'),
                        ),
                      ),
                    ],
                  ),
                if (!isOwner)
                  PopupMenuButton<String>(
                    tooltip: 'รายงานโพสต์',
                    onSelected: (_) => onReport?.call(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'report',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.flag_outlined),
                          title: Text('รายงานโพสต์'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (post.content.isNotEmpty)
              SelectableText(post.content, style: theme.textTheme.bodyLarge),
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: post.tags
                    .map(
                      (tag) => Chip(
                        label: Text('#$tag'),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (post.mediaPath != null && post.mediaType == 'image') ...[
              const SizedBox(height: 10),
              PostMedia(
                path: post.mediaPath!,
                type: post.mediaType,
                thumbnailPath: post.thumbnailPath,
              ),
            ],
            if (post.mediaPath != null && post.mediaType == 'video') ...[
              const SizedBox(height: 10),
              PostMedia(
                path: post.mediaPath!,
                type: post.mediaType,
                thumbnailPath: post.thumbnailPath,
              ),
            ],
            const SizedBox(height: 14),
            Divider(color: theme.colorScheme.outlineVariant, height: 1),
            const SizedBox(height: 4),
            StreamBuilder(
              stream: reactionService.watchReactions(post.id),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? const [];
                final ownReaction = docs.where((doc) => doc.id == currentUid);
                final selectedReaction = ownReaction.isEmpty
                    ? null
                    : SocialReaction.byId(
                        readOptionalString(
                          ownReaction.first.data()['reaction'],
                        ),
                      );
                final selected = selectedReaction?.id;
                final counts = <String, int>{
                  for (final reaction in SocialReaction.options) reaction.id: 0,
                };
                for (final doc in docs) {
                  final value = readOptionalString(doc.data()['reaction']);
                  final normalized = SocialReaction.byId(value)?.id;
                  if (normalized != null && counts.containsKey(normalized)) {
                    counts.update(
                      normalized,
                      (count) => count + 1,
                      ifAbsent: () => 1,
                    );
                  }
                }
                return Column(
                  children: [
                    if (counts.values.any((count) => count > 0))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4),
                          child: Wrap(
                            spacing: 8,
                            children: counts.entries
                                .where((entry) => entry.value > 0)
                                .map(
                                  (entry) => Text(
                                    '${SocialReaction.byId(entry.key)?.emoji ?? '👍'} ${entry.value}',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _PostAction(
                            icon: selected == 'like'
                                ? Icons.thumb_up_alt
                                : Icons.thumb_up_alt_outlined,
                            emoji:
                                selectedReaction == null ||
                                    selected == 'dislike'
                                ? null
                                : selectedReaction.emoji,
                            label:
                                selectedReaction == null ||
                                    selected == 'dislike'
                                ? 'ถูกใจ'
                                : selectedReaction.label,
                            color: selected != null && selected != 'dislike'
                                ? theme.colorScheme.primary
                                : null,
                            onPressed: () => onReaction('like'),
                            onLongPress: (buttonContext) async {
                              final reaction = await SocialReactionPicker.show(
                                buttonContext,
                              );
                              if (reaction != null) onReaction(reaction);
                            },
                          ),
                        ),
                        Expanded(
                          child: _PostAction(
                            icon: selected == 'dislike'
                                ? Icons.thumb_down_alt
                                : Icons.thumb_down_alt_outlined,
                            label: 'ไม่ถูกใจ',
                            color: selected == 'dislike'
                                ? theme.colorScheme.error
                                : null,
                            onPressed: () => onReaction('dislike'),
                          ),
                        ),
                        Expanded(
                          child: _PostAction(
                            icon: Icons.mode_comment_outlined,
                            label: 'ความคิดเห็น',
                            onPressed: onComment,
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

  /// แปลงเวลาโพสต์เป็นเขตเวลาไทย (UTC+7) และรูปแบบ 24 ชม. วัน/เดือน/ปี
  /// ใช้ UTC ก่อนบวก 7 ชั่วโมง เพื่อให้ผลไม่ขึ้นกับเขตเวลาของอุปกรณ์ที่เปิดแอป
  String _formatThailandTimestamp(DateTime createdAt) {
    final thailandTime = createdAt.toUtc().add(const Duration(hours: 7));
    final hour = thailandTime.hour.toString().padLeft(2, '0');
    final minute = thailandTime.minute.toString().padLeft(2, '0');

    return '$hour:$minute ${thailandTime.day}/${thailandTime.month}/${thailandTime.year}';
  }
}

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.emoji,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final String? emoji;
  final ValueChanged<BuildContext>? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) => TextButton(
        onPressed: onPressed,
        onLongPress: onLongPress == null
            ? null
            : () => onLongPress!(buttonContext),
        style: TextButton.styleFrom(
          foregroundColor: color ?? Theme.of(context).colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (emoji == null)
              Icon(icon, size: 20)
            else
              Text(emoji!, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label == 'แสดงความคิดเห็น' ? 'ความคิดเห็น' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// สถานะว่าง/ผิดพลาดของฟีด ใช้รูปแบบเดียวกันทั้งสองกรณี
class _FeedMessage extends StatelessWidget {
  /// Widget กลางสำหรับสถานะว่างหรือผิดพลาด รับไอคอน/ข้อความจากจุดเรียกใช้
  const _FeedMessage({
    required this.icon,
    required this.message,
    this.details,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final String? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (details != null) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 112),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    details!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองอีกครั้ง'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
