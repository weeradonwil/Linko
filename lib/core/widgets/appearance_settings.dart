// เมนูเลือกโหมดสว่าง/มืดและสีหลักที่บันทึกแยกกันสำหรับแต่ละโหมด
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/appearance_controller.dart';
import '../theme/theme_accent.dart';

/// ทางเข้าร่วมของหน้า Login, Home และ AppBar; ใช้ธีมปัจจุบันแทนสถานะที่ส่งค้างจาก route ก่อน
class AppearanceButton extends StatelessWidget {
  const AppearanceButton({this.iconSize, this.visualDensity, super.key});

  final double? iconSize;
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    if (AppearanceScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'การแสดงผล',
      iconSize: iconSize,
      visualDensity: visualDensity,
      icon: const Icon(Icons.palette_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const _AppearancePanel(),
      ),
    );
  }
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel();

  @override
  Widget build(BuildContext context) {
    final controller = AppearanceScope.of(context);
    // ใช้โหมดที่เลือกเป็นทั้งโหมดแสดงผลและโหมดที่ปรับสี เพื่อไม่ให้มีตัวเลือกซ้ำสองแถว
    final brightness = controller.mode == ThemeMode.dark
        ? Brightness.dark
        : Brightness.light;
    final accent = controller.accentFor(brightness);
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'การแสดงผล',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('appearance-close'),
                      tooltip: 'ปิด',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'โหมดแสดงผล',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('สว่าง'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('มืด'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {controller.mode},
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                  ),
                  onSelectionChanged: (selection) =>
                      unawaited(controller.setMode(selection.single)),
                ),
                const SizedBox(height: 24),
                // บันทึกสีเฉพาะโหมดปัจจุบัน สีของอีกโหมดยังคงค่าที่เคยเลือกไว้
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: brightness == Brightness.dark
                        ? 'สีสำหรับโหมดมืด'
                        : 'สีสำหรับโหมดสว่าง',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ThemeAccent>(
                      key: const ValueKey('appearance-accent'),
                      isExpanded: true,
                      value: accent,
                      dropdownColor: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      selectedItemBuilder: (_) => ThemeAccent.values
                          .map(
                            (item) => _AccentLabel(
                              accent: item,
                              brightness: brightness,
                            ),
                          )
                          .toList(),
                      items: ThemeAccent.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _AccentLabel(
                                      accent: item,
                                      brightness: brightness,
                                    ),
                                  ),
                                  if (item == accent)
                                    const Icon(Icons.check_rounded, size: 20),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (selected) {
                        if (selected != null) {
                          unawaited(controller.setAccent(brightness, selected));
                        }
                      },
                    ),
                  ),
                ),
                if (controller.persistenceFailed) ...[
                  const SizedBox(height: 12),
                  Text(
                    'ใช้ค่าที่เลือกได้ในครั้งนี้ แต่บันทึกไว้ใช้ครั้งหน้าไม่สำเร็จ',
                    style: TextStyle(color: colors.error),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => unawaited(controller.reset()),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('คืนค่าเริ่มต้น'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// แสดงชื่อควบคู่จุดสี เพื่อให้เลือกได้โดยไม่ต้องแยกแยะจากสีเพียงอย่างเดียว
class _AccentLabel extends StatelessWidget {
  const _AccentLabel({required this.accent, required this.brightness});

  final ThemeAccent accent;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: accent.colorFor(brightness),
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(child: Text(accent.label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
