// จำลองพื้นที่แป้นพิมพ์ของโทรศัพท์จริง ตรวจฟอร์ม Login/Register โดยไม่เรียก Firebase
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/theme/app_theme.dart';
import 'package:social_app/screens/login/login.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(393, 852)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'registration scrolls with keyboard: ${size.width}/${brightness.name}',
        (tester) async {
          await _pumpPhone(tester, size: size, brightness: brightness);
          await _openRegistration(tester);
          await _exerciseRegistration(tester, keyboardHeight: 300);
        },
      );
    }
  }

  testWidgets('registration scrolls in landscape with larger text', (
    tester,
  ) async {
    await _pumpPhone(
      tester,
      size: const Size(740, 393),
      brightness: Brightness.dark,
      textScale: 1.4,
    );
    await _openRegistration(tester);
    await _exerciseRegistration(tester, keyboardHeight: 170);
  });

  testWidgets('login actions remain reachable with the keyboard open', (
    tester,
  ) async {
    await _pumpPhone(
      tester,
      size: const Size(320, 640),
      brightness: Brightness.dark,
    );
    await tester.showKeyboard(find.byType(TextFormField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('ลืมรหัสผ่าน?'));
    expect(
      tester.getRect(find.text('ลืมรหัสผ่าน?')).bottom,
      lessThanOrEqualTo(340),
    );
    final submit = find.widgetWithText(FilledButton, 'เข้าสู่ระบบ');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('กรุณากรอกอีเมล'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPhone(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  double textScale = 1,
}) async {
  // viewInsets อยู่ใน physical pixels จึงตั้ง DPR=1 ให้ความสูงแป้นพิมพ์ตรงกับ fixture
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const LoginScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openRegistration(WidgetTester tester) async {
  final toggle = find.widgetWithText(TextButton, 'สมัครสมาชิก');
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _exerciseRegistration(
  WidgetTester tester, {
  required double keyboardHeight,
}) async {
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(4));
  await tester.showKeyboard(fields.first);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);

  // เลื่อนกรอกได้ครบถึงช่องยืนยันรหัสผ่าน โดยแป้นพิมพ์ยังเปิดอยู่
  for (var i = 0; i < 4; i++) {
    await tester.ensureVisible(fields.at(i));
    await tester.enterText(
      fields.at(i),
      ['Draft name', 'invalid-email', 'short', 'different'][i],
    );
    await tester.pumpAndSettle();
  }
  final submit = find.widgetWithText(FilledButton, 'สมัครสมาชิก');
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  final visibleBottom = tester.view.physicalSize.height - keyboardHeight;
  expect(tester.getRect(submit).bottom, lessThanOrEqualTo(visibleBottom));
  await tester.tap(submit);
  await tester.pumpAndSettle();
  expect(find.text('กรุณากรอกอีเมลให้ถูกต้อง'), findsOneWidget);
  expect(find.text('รหัสผ่านไม่ตรงกัน'), findsOneWidget);
  expect(tester.takeException(), isNull);

  // ปิด/เปิดแป้นพิมพ์ต้องไม่ทำให้ข้อมูลร่างหรือข้อความตรวจฟอร์มหาย
  tester.view.resetViewInsets();
  await tester.pumpAndSettle();
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
  await tester.pumpAndSettle();
  expect(
    tester.widget<TextFormField>(fields.first).controller!.text,
    'Draft name',
  );
  expect(find.text('รหัสผ่านไม่ตรงกัน'), findsOneWidget);
  expect(tester.takeException(), isNull);
}
