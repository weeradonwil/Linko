// จุดเริ่มทดสอบธีมบน Chrome/Android จริง โดยไม่เริ่ม Firebase และคืนค่าที่เคยบันทึกเมื่อจบ
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_app/core/theme/appearance_controller.dart';
import 'package:social_app/core/theme/theme_accent.dart';
import 'package:social_app/core/widgets/appearance_settings.dart';
import 'package:social_app/main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  const keys = [
    AppearanceController.themeModeKey,
    AppearanceController.lightAccentKey,
    AppearanceController.darkAccentKey,
  ];
  final original = {for (final key in keys) key: preferences.getString(key)};
  final controller = AppearanceController();
  await controller.load();
  final probe = GlobalKey();
  final completed = ValueNotifier<int?>(null);
  final results = <Map<String, Object?>>[];
  runApp(
    SocialApp(
      appearanceController: controller,
      home: _SmokeScreen(probe: probe, completed: completed),
    ),
  );

  Future<void> check(String name, Future<void> Function() action) async {
    try {
      await action();
      results.add({'name': name, 'passed': true});
    } catch (error) {
      results.add({'name': name, 'passed': false, 'error': error.toString()});
    }
  }

  try {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final accent in ThemeAccent.values) {
        await check('${brightness.name}/${accent.id}', () async {
          await controller.setMode(
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          );
          await controller.setAccent(brightness, accent);
          // รอให้การเปลี่ยน ThemeData และ animation ของ MaterialApp แสดงเฟรมจริงก่อนอ่าน
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await WidgetsBinding.instance.endOfFrame;
          final theme = Theme.of(probe.currentContext!);
          if (theme.brightness != brightness ||
              theme.colorScheme.primary != accent.colorFor(brightness)) {
            throw StateError(
              'Rendered theme did not match the selected mode/accent.',
            );
          }
        });
      }
    }
    await check('real preferences restore both independent colors', () async {
      await controller.setAccent(Brightness.light, ThemeAccent.blue);
      await controller.setAccent(Brightness.dark, ThemeAccent.purple);
      await controller.setMode(ThemeMode.dark);
      // อ่าน storage ของแพลตฟอร์มกลับใหม่ เพื่อไม่ยืนยันผลจากแคช SharedPreferences เดิมอย่างเดียว
      await preferences.reload();
      final reopened = AppearanceController();
      try {
        await reopened.load();
        if (reopened.mode != ThemeMode.dark ||
            reopened.lightAccent != ThemeAccent.blue ||
            reopened.darkAccent != ThemeAccent.purple ||
            controller.persistenceFailed) {
          throw StateError(
            'Platform preferences did not preserve both colors.',
          );
        }
      } finally {
        reopened.dispose();
      }
    });
  } finally {
    // คืนค่า storage ของแพลตฟอร์ม เพื่อไม่ทิ้งตัวเลือกทดสอบไว้แทนค่าของผู้ใช้
    for (final entry in original.entries) {
      if (entry.value == null) {
        await preferences.remove(entry.key);
      } else {
        await preferences.setString(entry.key, entry.value!);
      }
    }
  }
  completed.value = results.where((result) => result['passed'] == true).length;
  // Driver อ่านผลจาก Console ของ Chrome หรือ logcat ของ Android โดยไม่ใช้บัญชีจริง
  debugPrint('LINKO_APPEARANCE_SMOKE ${jsonEncode(results)}');
}

/// แสดงตัวอย่าง UI ด้วยธีมจริง และเปิดเมนูการแสดงผลตัวเดียวกับแอปได้
class _SmokeScreen extends StatelessWidget {
  const _SmokeScreen({required this.probe, required this.completed});

  final GlobalKey probe;
  final ValueNotifier<int?> completed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linko'),
        actions: const [AppearanceButton()],
      ),
      body: Padding(
        key: probe,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<int?>(
              valueListenable: completed,
              builder: (_, passed, _) => Text(
                passed == null
                    ? 'Checking appearance...'
                    : 'Appearance: $passed/17 passed',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 20),
            const Text('Linko — ตัวอย่างธีมบนแพลตฟอร์มจริง'),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'สีของการ์ดและข้อความ',
                  style: TextStyle(color: colors.onSurface),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'ข้อความของคุณ',
                  style: TextStyle(color: colors.onPrimary),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () {}, child: const Text('ปุ่มหลัก')),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(hintText: 'ตัวอย่างช่องข้อความ'),
            ),
          ],
        ),
      ),
    );
  }
}
