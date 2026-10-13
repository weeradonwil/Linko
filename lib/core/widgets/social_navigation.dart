import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/chat_service.dart';
import '../services/notification_service.dart';

/// App bar ร่วมที่รวมทางลัดค้นหา แจ้งเตือน เปลี่ยนธีม และออกจากระบบ
class LinkoAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LinkoAppBar({
    super.key,
    required this.onSearch,
    required this.onNotifications,
    this.onToggleTheme,
    this.isDarkMode = false,
    this.onSignOut,
  });
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final VoidCallback? onToggleTheme;
  final bool isDarkMode;
  final VoidCallback? onSignOut;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppBar(
      titleSpacing: 20,
      title: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
          children: [
            TextSpan(
              text: 'Link',
              style: TextStyle(color: colors.onSurface),
            ),
            TextSpan(
              text: 'o',
              style: TextStyle(color: colors.primary),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'ค้นหา',
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: 'แจ้งเตือน',
          onPressed: onNotifications,
          icon: const NotificationCountIcon(
            icon: Icons.notifications_none_rounded,
          ),
        ),
        if (onToggleTheme != null)
          IconButton(
            tooltip: isDarkMode ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด',
            onPressed: onToggleTheme,
            icon: Icon(
              isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
        if (onSignOut != null)
          IconButton(
            tooltip: 'ออกจากระบบ',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
          ),
      ],
    );
  }
}

/// แถบนำทางร่วม; ลำดับ items ต้องตรงกับ index ที่แต่ละหน้าจอใช้
class SocialBottomNavigation extends StatelessWidget {
  const SocialBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });
  final int? selectedIndex;
  final ValueChanged<int> onTap;
  static const items = [
    (Icons.home_outlined, Icons.home_rounded, 'หน้าหลัก'),
    (Icons.groups_outlined, Icons.groups_rounded, 'กลุ่ม'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'แชท'),
    (
      Icons.notifications_none_rounded,
      Icons.notifications_rounded,
      'แจ้งเตือน',
    ),
    (Icons.person_outline_rounded, Icons.person_rounded, 'โปรไฟล์'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (i == 2)
                        ChatUnreadCountIcon(
                          icon: selectedIndex == i ? items[i].$2 : items[i].$1,
                          color: selectedIndex == i
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          size: 23,
                        )
                      else if (i == 3)
                        NotificationCountIcon(
                          icon: selectedIndex == i ? items[i].$2 : items[i].$1,
                          color: selectedIndex == i
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          size: 23,
                        )
                      else
                        Icon(
                          selectedIndex == i ? items[i].$2 : items[i].$1,
                          color: selectedIndex == i
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          size: 23,
                        ),
                      const SizedBox(height: 3),
                      Text(
                        items[i].$3,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selectedIndex == i
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: selectedIndex == i
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                      if (selectedIndex == i)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          height: 2,
                          width: 28,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        )
                      else
                        const SizedBox(height: 5),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// แสดงจำนวนแจ้งเตือนที่ยังไม่อ่านเหนือไอคอน และเปลี่ยนสีไอคอนเมื่อมีรายการใหม่
/// Shows the total unread chat count on the Chat tab, separate from social alerts.
class ChatUnreadCountIcon extends StatefulWidget {
  const ChatUnreadCountIcon({
    required this.icon,
    this.color,
    this.size = 24,
    super.key,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  State<ChatUnreadCountIcon> createState() => _ChatUnreadCountIconState();
}

class _ChatUnreadCountIconState extends State<ChatUnreadCountIcon> {
  // Sum the per-room counters from the existing real-time conversation stream.
  late final Stream<int> _unreadCount = ChatService().watchConversations().map(
    (rooms) => rooms.fold<int>(0, (total, room) => total + room.unreadCount),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unreadCount,
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final colors = Theme.of(context).colorScheme;
        return SizedBox(
          width: widget.size + 6,
          height: widget.size + 6,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  widget.icon,
                  color: count > 0 ? colors.primary : widget.color,
                  size: widget.size,
                ),
              ),
              if (count > 0)
                Positioned(
                  top: -5,
                  right: -7,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: colors.error,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.surface, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 99 ? '99+' : count.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class NotificationCountIcon extends StatefulWidget {
  const NotificationCountIcon({
    required this.icon,
    this.color,
    this.size = 24,
    super.key,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  State<NotificationCountIcon> createState() => _NotificationCountIconState();
}

class _NotificationCountIconState extends State<NotificationCountIcon> {
  // เก็บ stream ไว้ตลอดอายุ widget เพื่อไม่สมัคร listener ใหม่ทุกครั้งที่ build
  late final Stream<int> _unreadCount = NotificationService()
      .watchUnreadCount();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unreadCount,
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final color = count > 0
            ? Theme.of(context).colorScheme.primary
            : widget.color;

        return SizedBox(
          width: widget.size + 6,
          height: widget.size + 6,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(widget.icon, color: color, size: widget.size),
              ),
              if (count > 0)
                Positioned(
                  top: -5,
                  right: -7,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 99 ? '99+' : count.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// แจ้งทิศทางการเลื่อนให้แถบนำทางซ่อนลงและกลับมาเมื่อเลื่อนสวนทาง
class ScrollNavigationVisibility extends StatefulWidget {
  const ScrollNavigationVisibility({required this.child, super.key});

  final Widget child;

  @override
  State<ScrollNavigationVisibility> createState() =>
      _ScrollNavigationVisibilityState();
}

class _ScrollNavigationVisibilityState
    extends State<ScrollNavigationVisibility> {
  final _visible = ValueNotifier<bool>(true);

  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification.direction == ScrollDirection.reverse && _visible.value) {
      _visible.value = false;
    } else if (notification.direction == ScrollDirection.forward &&
        !_visible.value) {
      _visible.value = true;
    }
    return false;
  }

  @override
  void dispose() {
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ScrollNavigationScope(
      notifier: _visible,
      child: NotificationListener<UserScrollNotification>(
        onNotification: _onUserScroll,
        child: widget.child,
      ),
    );
  }
}

class _ScrollNavigationScope extends InheritedNotifier<ValueNotifier<bool>> {
  const _ScrollNavigationScope({
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueNotifier<bool>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ScrollNavigationScope>()
      ?.notifier;
}

/// Collapses the bottom navigation while its page scrolls down.
class ScrollHidingNavigationBar extends StatelessWidget {
  const ScrollHidingNavigationBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visible = _ScrollNavigationScope.maybeOf(context);
    if (visible == null) return child;

    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      child: child,
      builder: (context, show, nav) => ClipRect(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: show ? nav! : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
