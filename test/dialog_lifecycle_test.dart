import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/widgets/group_editor_dialog.dart';
import 'package:social_app/core/widgets/post_report_dialog.dart';

void main() {
  for (final editing in [false, true]) {
    testWidgets(
      'group dialog cancels safely while text field has focus ($editing)',
      (tester) async {
        GroupDraft? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<GroupDraft>(
                      context: context,
                      builder: (_) => GroupEditorDialog(
                        editing: editing,
                        initialName: editing ? 'Group' : '',
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextField).first);
        await tester.enterText(find.byType(TextField).first, 'Edited group');
        await tester.tap(find.text('ยกเลิก'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('report dialog returns values without disposing a live field', (
    tester,
  ) async {
    PostReportDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<PostReportDraft>(
                  context: context,
                  builder: (_) => const PostReportDialog(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Report details');
    await tester.tap(find.text('ส่งรายงาน'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(result?.details, 'Report details');
    expect(result?.reason, 'สแปม');
    expect(tester.takeException(), isNull);
  });
}
