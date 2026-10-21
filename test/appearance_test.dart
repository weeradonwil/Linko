// ทดสอบสีทั้ง 16 ชุด การจำค่าจริง และเมนูการแสดงผลโดยไม่เชื่อมต่อ Firebase
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_app/core/theme/app_theme.dart';
import 'package:social_app/core/theme/appearance_controller.dart';
import 'package:social_app/core/theme/theme_accent.dart';
import 'package:social_app/core/widgets/appearance_settings.dart';
import 'package:social_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // วัดคู่สีที่แสดงข้อความจริง รวมพื้นช่องกรอกและข้อความบนปุ่มสีอ่อน
  for (final accent in ThemeAccent.values) {
    for (final brightness in Brightness.values) {
      test('readable colors: ${accent.id}/${brightness.name}', () {
        final theme = brightness == Brightness.dark
            ? AppTheme.dark(accent: accent)
            : AppTheme.light(accent: accent);
        final colors = theme.colorScheme;
        final pairs = <String, (Color, Color)>{
          'button/chat': (colors.onPrimary, colors.primary),
          'accent text': (colors.primary, colors.surface),
          'selected container': (
            colors.onPrimaryContainer,
            colors.primaryContainer,
          ),
          'body/card': (colors.onSurface, colors.surface),
          'body/background': (colors.onSurface, theme.scaffoldBackgroundColor),
          'body/input': (colors.onSurface, colors.surfaceContainerHigh),
          'secondary/card': (colors.onSurfaceVariant, colors.surface),
          'secondary/input': (
            colors.onSurfaceVariant,
            colors.surfaceContainerHigh,
          ),
          'error/badge': (colors.onError, colors.error),
          'video/fullscreen': (
            AppTheme.mediaProgressColor(colors),
            Colors.black,
          ),
        };
        for (final pair in pairs.entries) {
          expect(
            _contrast(pair.value.$1, pair.value.$2),
            greaterThanOrEqualTo(4.5),
            reason: pair.key,
          );
        }
      });
    }
  }

  test('restores legacy mode and falls back for unknown color IDs', () async {
    SharedPreferences.setMockInitialValues({
      AppearanceController.themeModeKey: 'dark',
      AppearanceController.lightAccentKey: 'unknown',
      AppearanceController.darkAccentKey: 'purple',
    });
    final controller = AppearanceController();
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.mode, ThemeMode.dark);
    expect(controller.lightAccent, ThemeAccent.linko);
    expect(controller.darkAccent, ThemeAccent.purple);
  });

  test(
    'keeps separate colors and latest rapid selection after reopening',
    () async {
      final controller = AppearanceController();
      addTearDown(controller.dispose);
      await controller.load();
      final changes = [
        controller.setAccent(Brightness.light, ThemeAccent.blue),
        controller.setAccent(Brightness.dark, ThemeAccent.yellow),
        controller.setAccent(Brightness.dark, ThemeAccent.purple),
        controller.setMode(ThemeMode.light),
        controller.setMode(ThemeMode.dark),
      ];
      await Future.wait(changes);
      final reopened = AppearanceController();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.mode, ThemeMode.dark);
      expect(reopened.lightAccent, ThemeAccent.blue);
      expect(reopened.darkAccent, ThemeAccent.purple);
    },
  );

  test(
    'slow restore preserves new selection and untouched stored settings',
    () async {
      SharedPreferences.setMockInitialValues({
        AppearanceController.themeModeKey: 'dark',
        AppearanceController.lightAccentKey: 'green',
        AppearanceController.darkAccentKey: 'purple',
      });
      final preferences = await SharedPreferences.getInstance();
      final ready = Completer<SharedPreferences>();
      final controller = AppearanceController(
        preferencesLoader: () => ready.future,
      );
      addTearDown(controller.dispose);
      final loading = controller.load();
      final saving = controller.setAccent(Brightness.light, ThemeAccent.blue);
      ready.complete(preferences);
      await Future.wait([loading, saving]);
      expect(controller.lightAccent, ThemeAccent.blue);
      expect(controller.darkAccent, ThemeAccent.purple);
      expect(controller.mode, ThemeMode.dark);
      final reopened = AppearanceController();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.lightAccent, ThemeAccent.blue);
      expect(reopened.darkAccent, ThemeAccent.purple);
    },
  );

  test(
    'explicit defaults before slow restore replace older saved choices',
    () async {
      SharedPreferences.setMockInitialValues({
        AppearanceController.themeModeKey: 'dark',
        AppearanceController.lightAccentKey: 'blue',
        AppearanceController.darkAccentKey: 'purple',
      });
      final preferences = await SharedPreferences.getInstance();
      final ready = Completer<SharedPreferences>();
      final controller = AppearanceController(
        preferencesLoader: () => ready.future,
      );
      addTearDown(controller.dispose);
      final loading = controller.load();
      final defaultMode = controller.mode;
      final changes = [
        controller.setMode(defaultMode),
        controller.setAccent(Brightness.light, ThemeAccent.linko),
        controller.setAccent(Brightness.dark, ThemeAccent.linko),
      ];
      ready.complete(preferences);
      await Future.wait([loading, ...changes]);
      final reopened = AppearanceController();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.mode, defaultMode);
      expect(reopened.lightAccent, ThemeAccent.linko);
      expect(reopened.darkAccent, ThemeAccent.linko);
    },
  );

  test('retrying the same mode saves it after a storage failure', () async {
    var failing = true;
    final controller = AppearanceController(
      preferencesLoader: () async {
        if (failing) throw StateError('storage unavailable');
        return SharedPreferences.getInstance();
      },
    );
    addTearDown(controller.dispose);
    await controller.setMode(ThemeMode.dark);
    failing = false;
    await controller.setMode(ThemeMode.dark);
    final reopened = AppearanceController();
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.mode, ThemeMode.dark);
    expect(controller.persistenceFailed, isFalse);
  });

  test('reset restores initial mode and both default colors on disk', () async {
    final controller = AppearanceController();
    addTearDown(controller.dispose);
    final defaultMode = controller.mode;
    await controller.setMode(ThemeMode.dark);
    await controller.setAccent(Brightness.dark, ThemeAccent.orange);
    await controller.reset();
    final reopened = AppearanceController();
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.mode, defaultMode);
    expect(reopened.lightAccent, ThemeAccent.linko);
    expect(reopened.darkAccent, ThemeAccent.linko);
  });

  test('a storage failure keeps selected appearance and can recover', () async {
    var failing = true;
    final controller = AppearanceController(
      preferencesLoader: () async {
        if (failing) throw StateError('storage unavailable');
        return SharedPreferences.getInstance();
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.setAccent(Brightness.dark, ThemeAccent.yellow);
    expect(controller.darkAccent, ThemeAccent.yellow);
    expect(controller.persistenceFailed, isTrue);
    failing = false;
    await controller.setAccent(Brightness.dark, ThemeAccent.green);
    expect(controller.persistenceFailed, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(
        AppearanceController.darkAccentKey,
      ),
      'green',
    );
  });

  test(
    'recovery also saves earlier mode and color changes that failed',
    () async {
      var failing = true;
      final controller = AppearanceController(
        preferencesLoader: () async {
          if (failing) throw StateError('storage unavailable');
          return SharedPreferences.getInstance();
        },
      );
      addTearDown(controller.dispose);
      await controller.setMode(ThemeMode.dark);
      await controller.setAccent(Brightness.dark, ThemeAccent.yellow);
      failing = false;
      await controller.setAccent(Brightness.light, ThemeAccent.blue);
      final reopened = AppearanceController();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.mode, ThemeMode.dark);
      expect(reopened.darkAccent, ThemeAccent.yellow);
      expect(reopened.lightAccent, ThemeAccent.blue);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('legacy system mode becomes fixed ${brightness.name}', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      SharedPreferences.setMockInitialValues({
        AppearanceController.themeModeKey: 'system',
      });
      final controller = AppearanceController();
      addTearDown(controller.dispose);
      await controller.load();
      final initialMode = brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light;
      expect(controller.mode, initialMode);
      await controller.setAccent(Brightness.light, ThemeAccent.blue);
      await controller.setAccent(Brightness.dark, ThemeAccent.purple);
      await _pumpApp(tester, controller);
      expect(_screenTheme(tester).brightness, brightness);
      expect(
        _screenTheme(tester).colorScheme.primary,
        controller.accentFor(brightness).colorFor(brightness),
      );
      final opposite = brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
      tester.platformDispatcher.platformBrightnessTestValue = opposite;
      await tester.pumpAndSettle();
      expect(_screenTheme(tester).brightness, brightness);
      await controller.setMode(
        opposite == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      );
      await tester.pumpAndSettle();
      expect(_screenTheme(tester).brightness, opposite);
      expect(
        _screenTheme(tester).colorScheme.primary,
        controller.accentFor(opposite).colorFor(opposite),
      );
    });
  }

  testWidgets('one mode selector edits and restores each active mode color', (
    tester,
  ) async {
    final controller = AppearanceController();
    addTearDown(controller.dispose);
    final defaultMode = controller.mode;
    await controller.setMode(ThemeMode.light);
    await _pumpApp(tester, controller);
    await tester.tap(find.byTooltip('การแสดงผล'));
    await tester.pumpAndSettle();
    expect(find.text('ตามระบบ'), findsNothing);
    expect(find.text('จำสีของโหมดสว่างและโหมดมืดแยกกัน'), findsNothing);
    expect(find.byKey(const ValueKey('appearance-preview')), findsNothing);
    expect(find.text('ปุ่มตัวอย่าง'), findsNothing);
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    expect(find.byType(SegmentedButton<Brightness>), findsNothing);
    expect(find.text('Light Mode'), findsNothing);
    expect(find.text('Dark Mode'), findsNothing);
    expect(find.text('สีสำหรับโหมดสว่าง'), findsOneWidget);
    await _chooseAccent(tester, 'สีน้ำเงิน');
    expect(_screenTheme(tester).colorScheme.primary, ThemeAccent.blue.light);
    await tester.tap(find.text('มืด'));
    await tester.pumpAndSettle();
    expect(find.text('สีสำหรับโหมดมืด'), findsOneWidget);
    await _chooseAccent(tester, 'สีเหลือง');
    expect(controller.darkAccent, ThemeAccent.yellow);
    expect(controller.lightAccent, ThemeAccent.blue);
    expect(_screenTheme(tester).brightness, Brightness.dark);
    expect(_screenTheme(tester).colorScheme.primary, ThemeAccent.yellow.dark);
    await tester.tap(find.text('สว่าง'));
    await tester.pumpAndSettle();
    expect(_screenTheme(tester).colorScheme.primary, ThemeAccent.blue.light);
    expect(
      find.widgetWithText(DropdownButton<ThemeAccent>, 'สีน้ำเงิน'),
      findsOneWidget,
    );
    await tester.tap(find.text('มืด'));
    await tester.pumpAndSettle();
    expect(_screenTheme(tester).colorScheme.primary, ThemeAccent.yellow.dark);
    // เมนูที่เปิดค้างต้องเปลี่ยน Theme ตามแอปด้วย ไม่ค้างชุดสีเดิมจากตอนเปิด route
    expect(
      Theme.of(tester.element(find.byType(DropdownButton<ThemeAccent>)))
          .brightness,
      Brightness.dark,
    );
    await tester.tap(find.byKey(const ValueKey('appearance-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('การแสดงผล'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(DropdownButton<ThemeAccent>, 'สีเหลือง'),
      findsOneWidget,
    );
    await tester.tap(find.text('คืนค่าเริ่มต้น'));
    await tester.pumpAndSettle();
    expect(controller.mode, defaultMode);
    expect(controller.lightAccent, ThemeAccent.linko);
    expect(controller.darkAccent, ThemeAccent.linko);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings scroll on a small phone and expose all eight color names',
    (tester) async {
      final controller = AppearanceController();
      addTearDown(controller.dispose);
      await _pumpApp(tester, controller, size: const Size(320, 568));
      await tester.tap(find.byTooltip('การแสดงผล'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appearance-accent')));
      await tester.pumpAndSettle();
      for (final accent in ThemeAccent.values) {
        expect(find.text(accent.label, skipOffstage: false), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    },
  );
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + .05) / (math.min(first, second) + .05);
}

Future<void> _pumpApp(
  WidgetTester tester,
  AppearanceController controller, {
  Size size = const Size(393, 852),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    SocialApp(
      appearanceController: controller,
      home: const _AppearanceHarness(),
    ),
  );
  await tester.pumpAndSettle();
}

ThemeData _screenTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byKey(const ValueKey('screen-theme'))));

Future<void> _chooseAccent(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('appearance-accent')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// ใช้ SocialApp และเมนูจริง แทนการสร้างตรรกะธีมซ้ำในชุดทดสอบ
class _AppearanceHarness extends StatelessWidget {
  const _AppearanceHarness();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(actions: const [AppearanceButton()]),
    body: const Center(child: Text('Linko', key: ValueKey('screen-theme'))),
  );
}
