import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/screens/login/login.dart';

void main() {
  // ตรวจหน้าเข้าสู่ระบบและการตรวจช่องว่าง โดยไม่เรียก Firebase จริง
  testWidgets('แสดงฟอร์มเข้าสู่ระบบและแจ้งเมื่อยังไม่กรอกข้อมูล', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('ยินดีต้อนรับ'), findsOneWidget);
    await tester.tap(find.text('เข้าสู่ระบบ'));
    await tester.pump();

    expect(find.text('กรุณากรอกอีเมล'), findsOneWidget);
    expect(find.text('กรุณากรอกรหัสผ่าน'), findsOneWidget);
  });

  // ตรวจว่าการสลับโหมดสมัครสมาชิกทำให้ช่องชื่อแสดงขึ้น
  testWidgets('แสดงช่องชื่อในโหมดสมัครสมาชิก', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.text('ยังไม่มีบัญชี? สมัครสมาชิก'));
    await tester.pump();

    expect(find.text('สร้างบัญชีใหม่'), findsOneWidget);
    expect(find.text('ชื่อที่แสดง'), findsOneWidget);
    expect(find.text('ยืนยันรหัสผ่าน'), findsOneWidget);
  });

  // ตรวจว่ารหัสผ่านสั้นถูกปฏิเสธก่อนส่งข้อมูลไป Firebase
  testWidgets('ปฏิเสธรหัสผ่านที่สั้นกว่า 8 ตัวอักษร', (
    WidgetTester tester,
  ) async {
    await _openRegistration(tester);
    await _fillRegistration(tester, password: 'Ab1!', confirmation: 'Ab1!');

    await tester.tap(find.text('สมัครสมาชิก'));
    await tester.pump();

    expect(find.text('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร'), findsOneWidget);
  });

  // ตรวจว่ารหัสผ่านที่ยืนยันต้องตรงกัน ก่อนเรียก Firebase Authentication
  testWidgets('แจ้งเตือนเมื่อยืนยันรหัสผ่านไม่ตรงกัน', (
    WidgetTester tester,
  ) async {
    await _openRegistration(tester);
    await _fillRegistration(
      tester,
      password: 'StrongPass1!',
      confirmation: 'StrongPass2!',
    );

    await tester.tap(find.text('สมัครสมาชิก'));
    await tester.pump();

    expect(find.text('รหัสผ่านไม่ตรงกัน'), findsOneWidget);
  });
}

/// เปิดโหมดสมัครสมาชิก โดยไม่จำเป็นต้องเริ่ม Firebase ใน Widget test
Future<void> _openRegistration(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
  await tester.tap(find.text('ยังไม่มีบัญชี? สมัครสมาชิก'));
  await tester.pump();
}

/// กรอกข้อมูลที่ทำให้ฟอร์มผ่านช่องชื่อและอีเมล เพื่อทดสอบกฎรหัสผ่านโดยตรง
Future<void> _fillRegistration(
  WidgetTester tester, {
  required String password,
  required String confirmation,
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Test User');
  await tester.enterText(fields.at(1), 'test@example.com');
  await tester.enterText(fields.at(2), password);
  await tester.enterText(fields.at(3), confirmation);
}
