import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/widgets/auth_session_boundary.dart';

void main() {
  testWidgets('signout closes pushed pages and clears session data once', (
    tester,
  ) async {
    String? uid = 'first-user';
    late StateSetter changeSession;
    var clears = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            changeSession = setState;
            return AuthSessionBoundary(
              sessionId: uid,
              onSessionChanged: () => clears++,
              child: Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const Scaffold(body: Text('private detail')),
                    ),
                  ),
                  child: Text(uid == null ? 'login' : 'home'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();
    expect(find.text('private detail'), findsOneWidget);
    changeSession(() => uid = null);
    await tester.pumpAndSettle();
    expect(find.text('private detail'), findsNothing);
    expect(find.text('login'), findsOneWidget);
    expect(clears, 1);
    changeSession(() {});
    await tester.pumpAndSettle();
    expect(clears, 1);
  });
}
