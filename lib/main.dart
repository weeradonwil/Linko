// เริ่ม Flutter โหลดค่าตั้งต้นของแอป และตั้งค่า Firebase ก่อนแสดงหน้าจอแรก
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/appearance_controller.dart';
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
  const SocialApp({super.key, this.home, this.appearanceController});

  // รับหน้าเริ่มต้น/ตัวควบคุมแยกได้ เพื่อทดสอบธีมจริงโดยไม่เรียก Firebase
  final Widget? home;
  final AppearanceController? appearanceController;

  @override
  State<SocialApp> createState() => _SocialAppState();
}

class _SocialAppState extends State<SocialApp> {
  late final AppearanceController _appearance;

  @override
  void initState() {
    super.initState();
    _appearance = widget.appearanceController ?? AppearanceController();
    unawaited(_appearance.load());
  }

  @override
  void dispose() {
    if (widget.appearanceController == null) _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Scope อยู่เหนือ Navigator เพื่อให้หน้าที่เปิดค้างและเมนูตั้งค่าเปลี่ยนสีพร้อมกัน
    return AppearanceScope(
      controller: _appearance,
      child: ListenableBuilder(
        listenable: _appearance,
        builder: (context, _) => MaterialApp(
          // ชื่อที่ระบบแสดงในรายการแอปล่าสุดและชื่อหน้าต่างของ Flutter
          title: 'Linko',
          // ซ่อนป้าย DEBUG สีแดงที่ Flutter แสดงระหว่างพัฒนา
          debugShowCheckedModeBanner: false,
          // MaterialApp ใช้ ThemeMode ปัจจุบันเลือก lightTheme หรือ darkTheme
          theme: AppTheme.light(accent: _appearance.lightAccent),
          darkTheme: AppTheme.dark(accent: _appearance.darkAccent),
          themeMode: _appearance.mode,
          home: widget.home ?? const AuthGate(),
        ),
      ),
    );
  }
}
