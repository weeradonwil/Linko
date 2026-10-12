import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/chat_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/firebase_error_message.dart';
import '../../core/widgets/social_navigation.dart';
import '../chat/chat_list.dart';
import '../chat/chat_room.dart';
import '../search/search_explore.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.user,
    this.isDarkMode = false,
    this.onToggleTheme,
  });
  final User user;
  final bool isDarkMode;
  final VoidCallback? onToggleTheme;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

// สลับ stream ระหว่างการแจ้งเตือนทั้งหมดกับรายการที่ยังไม่ได้อ่าน
class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _unreadOnly = false;
  final _service = NotificationService();
  void _go(int i) {
    if (i == 0) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (i == 2) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatListScreen(
            user: widget.user,
            isDarkMode: widget.isDarkMode,
            onToggleTheme: widget.onToggleTheme,
          ),
        ),
      );
    } else if (i != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(i == 1 ? 'กลุ่มกำลังพัฒนา' : 'โปรไฟล์กำลังพัฒนา'),
        ),
      );
    }
  }

  // ให้ service จัดการแบ่ง batch และแสดงข้อผิดพลาดหากอัปเดตไม่สำเร็จ
  Future<void> _markAllRead() async {
    try {
      await _service.markAllRead();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ทำเครื่องหมายอ่านแล้วไม่สำเร็จ')),
        );
    }
  }

  // เมื่อเปิดแจ้งเตือนข้อความ ให้ทำเครื่องหมายอ่านแล้วและไปยังห้องสนทนา
  Future<void> _open(AppNotification item) async {
    try {
      if (!item.isRead) await _service.markRead(item.id);
    } catch (_) {}
    if (!mounted) return;
    if (item.type == 'message' && item.conversationId != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(
            user: widget.user,
            conversationId: item.conversationId!,
            peerId: item.actorId,
            peerName: item.actorName,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ScrollNavigationVisibility(
      child: Scaffold(
        appBar: LinkoAppBar(
          onSearch: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SearchExploreScreen(
                user: widget.user,
                isDarkMode: widget.isDarkMode,
                onToggleTheme: widget.onToggleTheme,
              ),
            ),
          ),
          onNotifications: () => setState(() => _unreadOnly = false),
          isDarkMode: widget.isDarkMode,
          onToggleTheme: widget.onToggleTheme,
          onSignOut: () => AuthService().signOut(),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'การแจ้งเตือน',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _markAllRead,
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('อ่านทั้งหมด'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('ทั้งหมด')),
                  ButtonSegment(value: true, label: Text('ยังไม่ได้อ่าน')),
                ],
                selected: {_unreadOnly},
                onSelectionChanged: (value) =>
                    setState(() => _unreadOnly = value.first),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<AppNotification>>(
                stream: _service.watchNotifications(unreadOnly: _unreadOnly),
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return _NoticeState(
                      icon: Icons.cloud_off_outlined,
                      title: 'โหลดการแจ้งเตือนไม่สำเร็จ',
                      detail: firebaseErrorMessage(
                        snapshot.error,
                        action: 'โหลดการแจ้งเตือน',
                      ),
                    );
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  final items = snapshot.data ?? [];
                  if (items.isEmpty)
                    return _NoticeState(
                      icon: Icons.notifications_none_rounded,
                      title: _unreadOnly
                          ? 'ไม่มีรายการที่ยังไม่ได้อ่าน'
                          : 'ยังไม่มีการแจ้งเตือน',
                      detail: 'การแจ้งเตือนข้อความใหม่จะแสดงที่นี่',
                    );
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final n = items[i];
                      return Card(
                        color: n.isRead ? null : colors.surfaceContainerLow,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _open(n),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: colors.primary.withValues(
                                    alpha: .18,
                                  ),
                                  child: Text(
                                    n.actorName.characters.first.toUpperCase(),
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.actorName + ' ส่งข้อความถึงคุณ',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        n.body,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        _when(n.createdAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!n.isRead)
                                  Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: ScrollHidingNavigationBar(
          child: SocialBottomNavigation(selectedIndex: 3, onTap: _go),
        ),
      ),
    );
  }

  String _when(DateTime? date) {
    if (date == null) return 'เมื่อสักครู่';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return diff.inMinutes.toString() + ' นาทีที่แล้ว';
    if (diff.inHours < 24) return diff.inHours.toString() + ' ชั่วโมงที่แล้ว';
    return date.day.toString() +
        '/' +
        date.month.toString() +
        '/' +
        date.year.toString();
  }
}

class _NoticeState extends StatelessWidget {
  const _NoticeState({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 54,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
