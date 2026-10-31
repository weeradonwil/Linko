import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/screens/auth/verify_email_screen.dart';

class _User extends Fake implements User {
  @override
  String get email => 'member@example.test';
}

void main() {
  // ไม่มีการส่งอีเมลจาก unit/widget test ใช้ callback แทน แล้วทดสอบ SDK จริงแยกใน Emulator
  testWidgets('verified response opens the next page once', (tester) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VerifyEmailScreen(
          user: _User(),
          onVerified: () => opens++,
          checkVerification: () async => true,
        ),
      ),
    );
    await tester.tap(find.text('ฉันยืนยันอีเมลแล้ว'));
    await tester.pump();
    expect(opens, 1);
  });
  testWidgets('unverified response stays on verification page', (tester) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VerifyEmailScreen(
          user: _User(),
          onVerified: () => opens++,
          checkVerification: () async => false,
        ),
      ),
    );
    await tester.tap(find.text('ฉันยืนยันอีเมลแล้ว'));
    await tester.pump();
    expect(opens, 0);
    expect(find.textContaining('ยังไม่พบการยืนยัน'), findsOneWidget);
  });
  testWidgets('resending has a 60 second cooldown and timer is disposed', (
    tester,
  ) async {
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VerifyEmailScreen(
          user: _User(),
          onVerified: () {},
          sendVerification: () async {
            sends++;
          },
        ),
      ),
    );
    await tester.tap(find.text('ส่งลิงก์ยืนยันอีกครั้ง'));
    await tester.pump();
    expect(sends, 1);
    expect(find.text('ส่งอีกครั้งใน 60 วินาที'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('ส่งลิงก์ยืนยันอีกครั้ง'), findsOneWidget);
    await tester.tap(find.text('ส่งลิงก์ยืนยันอีกครั้ง'));
    await tester.pump();
    expect(sends, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets('too many emails gives a clear retry message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VerifyEmailScreen(
          user: _User(),
          onVerified: () {},
          sendVerification: () async =>
              throw FirebaseAuthException(code: 'too-many-requests'),
        ),
      ),
    );
    await tester.tap(find.text('ส่งลิงก์ยืนยันอีกครั้ง'));
    await tester.pump();
    expect(find.textContaining('ส่งหลายครั้งแล้ว'), findsOneWidget);
  });
}
