// ควบคุมโหมดแสดงผลและสีของแต่ละโหมด พร้อมบันทึกลงเครื่องโดยไม่ผูกกับบัญชี Firebase
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_accent.dart';

/// เปลี่ยนธีมทันที แล้วเรียงงานบันทึกเพื่อให้ค่าล่าสุดถูกเก็บหลังผู้ใช้กดเปลี่ยนเร็ว ๆ
class AppearanceController extends ChangeNotifier {
  AppearanceController({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance {
    // ใช้ความสว่างของเครื่องตอนเริ่มเป็นค่าเริ่มต้นครั้งเดียว แล้วให้ผู้ใช้เลือกสว่าง/มืดเอง
    _defaultMode =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    _mode = _defaultMode;
  }

  // ใช้ key โหมดเดิมเพื่อรักษาค่าของผู้ใช้ก่อนมีเมนูเลือกสี
  static const themeModeKey = 'social_app_theme_mode';
  static const lightAccentKey = 'social_app_light_accent';
  static const darkAccentKey = 'social_app_dark_accent';

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<SharedPreferences>? _preferences;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  late final ThemeMode _defaultMode;
  late ThemeMode _mode;
  ThemeAccent _lightAccent = ThemeAccent.linko;
  ThemeAccent _darkAccent = ThemeAccent.linko;
  final Set<String> _changedKeys = {};
  bool _disposed = false;
  bool _persistenceFailed = false;

  ThemeMode get mode => _mode;
  ThemeAccent get lightAccent => _lightAccent;
  ThemeAccent get darkAccent => _darkAccent;
  bool get persistenceFailed => _persistenceFailed;

  ThemeAccent accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? _darkAccent : _lightAccent;

  Future<SharedPreferences> _getPreferences() =>
      _preferences ??= _preferencesLoader();

  Future<void> load() => _loading ??= _restore();

  /// ไม่ให้การอ่านค่าที่เสร็จช้าเขียนทับตัวเลือกใหม่ที่ผู้ใช้กดระหว่างเปิดแอป
  Future<void> _restore() async {
    try {
      final preferences = await _getPreferences();
      if (_disposed) return;
      if (!_changedKeys.contains(themeModeKey)) {
        _mode = switch (preferences.getString(themeModeKey)) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          // รองรับค่า system ของรุ่นเดิม โดยแปลงเป็นสว่าง/มืด ไม่ติดตามระบบต่อ
          _ => _defaultMode,
        };
      }
      if (!_changedKeys.contains(lightAccentKey)) {
        _lightAccent = ThemeAccent.fromId(
          preferences.getString(lightAccentKey),
        );
      }
      if (!_changedKeys.contains(darkAccentKey)) {
        _darkAccent = ThemeAccent.fromId(preferences.getString(darkAccentKey));
      }
      _notify();
    } catch (error) {
      _reportPersistenceFailure(error);
    }
  }

  Future<void> setMode(ThemeMode mode) {
    // การเลือกค่าเดิมก็เป็นความตั้งใจของผู้ใช้ โดยเฉพาะก่อนโหลดค่าเก่าหรือหลังบันทึกล้มเหลว
    _mode = mode == ThemeMode.system ? _defaultMode : mode;
    return _changed({themeModeKey});
  }

  Future<void> setAccent(Brightness brightness, ThemeAccent accent) {
    if (brightness == Brightness.dark) {
      _darkAccent = accent;
    } else {
      _lightAccent = accent;
    }
    return _changed({
      brightness == Brightness.dark ? darkAccentKey : lightAccentKey,
    });
  }

  /// คืนโหมดเริ่มต้นครั้งนี้และสี Linko ของสองโหมด แม้การอ่านค่าที่บันทึกยังไม่เสร็จ
  Future<void> reset() {
    _mode = _defaultMode;
    _lightAccent = ThemeAccent.linko;
    _darkAccent = ThemeAccent.linko;
    return _changed({themeModeKey, lightAccentKey, darkAccentKey});
  }

  Future<void> _changed(Set<String> keys) {
    _changedKeys.addAll(keys);
    _notify();
    _writes = _writes.then((_) => _persist());
    return _writes;
  }

  /// จับปัญหาการบันทึกโดยคงธีมที่ผู้ใช้เลือกไว้สำหรับการใช้งานครั้งนี้
  Future<void> _persist() async {
    try {
      // รวมค่าเก่าที่ยังไม่ได้แก้ก่อนบันทึก และลองเก็บทุกค่าปัจจุบันเมื่อ storage กลับมาใช้ได้
      await load();
      final preferences = await _getPreferences();
      final values = {
        themeModeKey: _mode.name,
        lightAccentKey: _lightAccent.id,
        darkAccentKey: _darkAccent.id,
      };
      for (final entry in values.entries) {
        if (!await preferences.setString(entry.key, entry.value)) {
          throw StateError('Appearance preference was not saved.');
        }
      }
      if (_persistenceFailed) {
        _persistenceFailed = false;
        _notify();
      }
    } catch (error) {
      _reportPersistenceFailure(error);
    }
  }

  void _reportPersistenceFailure(Object error) {
    _persistenceFailed = true;
    _preferences = null;
    if (kDebugMode) {
      debugPrint('Appearance preferences failed [${error.runtimeType}]');
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// ให้ทุก route ใช้ตัวควบคุมเดียวกัน โดยไม่ส่งสถานะมืด/สว่างผ่านแต่ละหน้าจอ
class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    required AppearanceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppearanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;

  static AppearanceController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'AppearanceScope must wrap this widget.');
    return controller!;
  }
}
