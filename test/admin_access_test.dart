// ทดสอบปัญหาอ่านสิทธิ์ผู้ดูแลล้มเหลว: ต้องแจ้ง error และกดลองใหม่ได้แทนตัวโหลดค้าง
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/screens/admin/admin_reports_screen.dart';

class _UnavailableTokenUser implements User {
  int attempts = 0;
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    attempts++;
    throw FirebaseAuthException(code: 'network-request-failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('failed admin token shows retry and does not keep loading', (
    tester,
  ) async {
    final user = _UnavailableTokenUser();
    await tester.pumpWidget(MaterialApp(home: AdminReportsScreen(user: user)));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('ตรวจสิทธิ์ผู้ดูแลไม่สำเร็จ กรุณาลองอีกครั้ง'),
      findsOneWidget,
    );
    expect(user.attempts, 1);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(user.attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
