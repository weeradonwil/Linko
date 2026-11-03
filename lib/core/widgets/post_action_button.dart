import 'package:flutter/material.dart';

/// แสดงเฉพาะไอคอน แต่ยังมีชื่อปุ่มให้เมาส์ชี้และโปรแกรมอ่านหน้าจอ
class PostActionButton extends StatelessWidget {
  const PostActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.emoji,
    this.onLongPress,
    this.badgeCount,
    this.inlineCount,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final String? emoji;
  final ValueChanged<BuildContext>? onLongPress;
  final int? badgeCount;
  final int? inlineCount;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (buttonContext) => Semantics(
      selected: color == null ? null : true,
      child: Tooltip(
        message: inlineCount != null && inlineCount! > 0
            ? '$label ${inlineCount!}'
            : badgeCount != null && badgeCount! > 0
            ? '$label ${badgeCount!}'
            : label,
        // ปุ่มถูกใจใช้กดค้างเปิดอิโมจิ จึงไม่ให้ Tooltip แย่ง gesture นี้
        triggerMode: onLongPress == null
            ? TooltipTriggerMode.longPress
            : TooltipTriggerMode.manual,
        child: TextButton(
          onPressed: onPressed,
          onLongPress: onLongPress == null
              ? null
              : () => onLongPress!(buttonContext),
          style: TextButton.styleFrom(
            foregroundColor: color ?? Theme.of(context).colorScheme.onSurface,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: ExcludeSemantics(
            child: Badge(
              isLabelVisible: badgeCount != null && badgeCount! > 0,
              label: badgeCount == null ? null : Text('$badgeCount'),
              child: inlineCount == null
                  ? emoji == null
                        ? Icon(icon, size: 22)
                        : Text(
                            emoji!,
                            style: const TextStyle(fontSize: 22, height: 1),
                          )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        emoji == null
                            ? Icon(icon, size: 22)
                            : Text(
                                emoji!,
                                style: const TextStyle(fontSize: 22, height: 1),
                              ),
                        if (inlineCount! > 0) ...[
                          const SizedBox(width: 5),
                          Text(
                            '$inlineCount',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
