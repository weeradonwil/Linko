// เริ่ม Flutter โหลดค่าตั้งต้นของแอป และตั้งค่า Firebase ก่อนแสดงหน้าจอแรก
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/auth/auth_gate.dart';

Future<void> main() async {
  // อนุญาตให้เรียกโค้ด Flutter ก่อน runApp เช่น การเริ่ม Firebase แบบ async

  //เริ่มแอปและเชื่อม Firebase — ใน main.dartเริ่ม Flutter แล้วตั้งค่า Firebase ก่อนเปิดหน้าแอป
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SocialApp());
}

/// Widget เก็บโหมดสีและส่งค่า Theme ให้ทุกหน้าผ่าน MaterialApp
class SocialApp extends StatefulWidget {
  const SocialApp({super.key});

  @override
  State<SocialApp> createState() => _SocialAppState();
}

class _SocialAppState extends State<SocialApp> {
  static const _themePreferenceKey = 'social_app_theme_mode';

  // เก็บ instance ไว้ใช้ซ้ำ โดยเรียก SharedPreferences หลัง Flutter เริ่มแอปแล้ว
  // และสร้าง instance เมื่อจำเป็น เพื่อไม่ให้การเริ่มหน้าจอพึ่งพา plugin ทันที
  SharedPreferences? _preferences;

  Future<SharedPreferences> _getPreferences() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  // เริ่มตามโหมดของระบบก่อน แล้วค่อยแทนค่าด้วยค่าที่ผู้ใช้เคยเลือก (ถ้ามี)
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadSavedThemeMode();
  }

  /// อ่านตัวเลือกที่เก็บไว้ เพื่อคง Light/Dark mode หลังปิดและเปิดแอปใหม่
  Future<void> _loadSavedThemeMode() async {
    try {
      final preferences = await _getPreferences();
      final savedMode = preferences.getString(_themePreferenceKey);
      if (!mounted) return;

      setState(() {
        _themeMode = switch (savedMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
      });
    } catch (_) {
      // ถ้าอ่านค่าที่เก็บไว้ไม่ได้ ให้ใช้โหมดระบบต่อไป แอปยังเปิดได้ตามปกติ
    }
  }

  /// สลับไปอีกโหมดหนึ่งและบันทึกค่า โดยอ่านโหมดปัจจุบันทุกครั้งที่กด
  Future<void> _toggleTheme() async {
    final isCurrentlyDark =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final newMode = isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;
    final savedValue = newMode == ThemeMode.dark ? 'dark' : 'light';

    // เปลี่ยน state ก่อนเพื่อให้หน้าจอเปลี่ยนทันที ไม่ต้องรอการเขียนลงเครื่อง
    setState(() => _themeMode = newMode);

    try {
      final preferences = await _getPreferences();
      await preferences.setString(_themePreferenceKey, savedValue);
    } catch (_) {
      // ถ้าบันทึกไม่ได้ โหมดที่เลือกยังใช้ได้จนกว่าจะปิดแอป
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Social App',
      // ซ่อนป้าย DEBUG สีแดงที่ Flutter แสดงระหว่างพัฒนา
      debugShowCheckedModeBanner: false,
      // MaterialApp ใช้ ThemeMode ปัจจุบันเลือก lightTheme หรือ darkTheme
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      // ส่งฟังก์ชันสลับธีมลงไปให้หน้า Login และ Home แสดงปุ่มควบคุมได้
      home: AuthGate(onToggleTheme: _toggleTheme),
    );
  }
}
