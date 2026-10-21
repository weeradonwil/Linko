// เลือกหน้า Login หรือ Home ตามสถานะการเข้าสู่ระบบที่ Firebase ส่งมา
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../home/home.dart';
import '../login/login.dart';

/// AuthGate รับแจ้งเตือนจาก Firebase เมื่อสถานะบัญชีเปลี่ยน แล้วเลือกแสดงหน้า Login หรือ Home
/// ถ้ายังไม่มีบัญชีที่ล็อกอินจะแสดง Login; ถ้ามีบัญชีจะแสดง Home
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder สร้างหน้าจอใหม่ทุกครั้งที่ Firebase ส่งสถานะบัญชีมา
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        // ระหว่างรอ Firebase คืนสถานะ ให้แสดงตัวโหลดแทนหน้าจอว่าง
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          // แสดงข้อความแทนการเปิดหน้าผิด เมื่ออ่านสถานะจาก Firebase ไม่ได้
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ตรวจสอบสถานะบัญชีไม่สำเร็จ กรุณาปิดแล้วเปิดแอปใหม่',
                ),
              ),
            ),
          );
        }

        // data เป็น User เมื่อเข้าสู่ระบบแล้ว และเป็น null เมื่อยังไม่ได้ล็อกอิน
        final user = snapshot.data;
        // แต่ละหน้ารับธีมจากส่วนกลาง จึงไม่ส่ง bool ที่อาจค้างหลังสลับโหมด
        return user == null ? const LoginScreen() : HomeScreen(user: user);
      },
    );
  }
}
