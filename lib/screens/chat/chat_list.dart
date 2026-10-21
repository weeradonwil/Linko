// แสดงห้องสนทนาแบบ real-time และนำผู้ใช้ไปยังห้องที่เลือก
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/chat_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/firebase_error_message.dart';
import '../../core/services/chat_service.dart';
import '../../core/widgets/social_navigation.dart';
import '../notifications/notifications_screen.dart';
import '../search/search_explore.dart';
import '../profile/profile.dart';
import '../groups/groups_screen.dart';
import 'chat_room.dart';

/// แสดงรายการห้องจาก Firestore แบบ real-time และเปิดห้องแชทที่เลือก
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key, required this.user});
  final User user;
  void _go(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      case 2:
        return;
      case 3:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NotificationsScreen(user: user),
          ),
        );
        return;
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => GroupsScreen(user: user)),
        );
        return;
      case 4:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ProfileScreen(user: user)),
        );
        return;
    }
  }

  void _openSearch(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SearchExploreScreen(user: user)),
  );
  void _openNotifications(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => NotificationsScreen(user: user)),
  );

  @override
  Widget build(BuildContext context) {
    final service = ChatService();
    return ScrollNavigationVisibility(
      child: Scaffold(
        appBar: LinkoAppBar(
          onSearch: () => _openSearch(context),
          onNotifications: () => _openNotifications(context),
          onSignOut: () => AuthService().signOut(),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'แชท',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _openSearch(context),
                    tooltip: 'เริ่มแชทใหม่',
                    icon: const Icon(Icons.edit_square),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ConversationSummary>>(
                stream: service.watchConversations(),
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return _StateMessage(
                      icon: Icons.cloud_off_outlined,
                      text: firebaseErrorMessage(
                        snapshot.error,
                        action: 'โหลดรายการแชท',
                      ),
                      action: 'ลองอีกครั้ง',
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatListScreen(user: user),
                        ),
                      ),
                    );
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  final items = snapshot.data ?? [];
                  if (items.isEmpty)
                    return _StateMessage(
                      icon: Icons.chat_bubble_outline_rounded,
                      text: 'ยังไม่มีบทสนทนา',
                      detail: 'ค้นหาสมาชิกแล้วเริ่มพูดคุยกันได้เลย',
                      action: 'ค้นหาสมาชิก',
                      onPressed: () => _openSearch(context),
                    );
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final conversation = items[index];
                      final name = conversation.peerName(user.uid);
                      final preview = conversation.lastMessageText.isEmpty
                          ? 'เริ่มบทสนทนา'
                          : (conversation.lastMessageSenderId == user.uid
                                    ? 'คุณ: '
                                    : '') +
                                conversation.lastMessageText;
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            radius: 27,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .18),
                            child: Text(
                              name.characters.first.toUpperCase(),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (conversation.unreadCount > 0)
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        conversation.unreadCount > 99
                                            ? '99+'
                                            : conversation.unreadCount
                                                  .toString(),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _time(conversation.lastMessageAt),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'ตัวเลือกแชท',
                                onSelected: (value) async {
                                  if (value != 'hide') return;
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text(
                                        'ลบแชทนี้ออกจากรายการ?',
                                      ),
                                      content: const Text(
                                        'ข้อความของคุณและอีกฝ่ายจะยังอยู่ แชทจะถูกซ่อนจากบัญชีนี้',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('กลับ'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('ลบแชท'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true || !context.mounted)
                                    return;
                                  try {
                                    await ChatService().hideConversation(
                                      conversation.id,
                                    );
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'ลบแชทไม่สำเร็จ: $error',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'hide',
                                    child: Text('ลบแชท'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ChatRoomScreen(
                                user: user,
                                conversationId: conversation.id,
                                peerId: conversation.peerId(user.uid),
                                peerName: name,
                              ),
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
          child: SocialBottomNavigation(
            selectedIndex: 2,
            onTap: (i) => _go(context, i),
          ),
        ),
      ),
    );
  }

  String _time(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day)
      return date.hour.toString().padLeft(2, '0') +
          ':' +
          date.minute.toString().padLeft(2, '0');
    return date.day.toString() + '/' + date.month.toString();
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.text,
    this.detail,
    this.action,
    this.onPressed,
  });
  final IconData icon;
  final String text;
  final String? detail;
  final String? action;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 52,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}
