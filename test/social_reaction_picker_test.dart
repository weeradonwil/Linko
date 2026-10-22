import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/widgets/social_reaction_picker.dart';

void main() {
  testWidgets('long press opens the emoji picker and returns the selection', (
    tester,
  ) async {
    String? selectedReaction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (buttonContext) => TextButton(
              onPressed: () {},
              onLongPress: () async {
                selectedReaction = await SocialReactionPicker.show(
                  buttonContext,
                );
              },
              child: const Text('ถูกใจ'),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('ถูกใจ'));
    await tester.pumpAndSettle();
    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('😡'), findsOneWidget);

    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();
    expect(selectedReaction, 'love');
  });

  for (final width in [240.0, 390.0]) {
    testWidgets('Back dismisses palette on a $width wide screen', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result = 'pending';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await SocialReactionPicker.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('❤️'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('❤️'), findsNothing);
      expect(result, isNull);
      expect(find.text('open'), findsOneWidget);
    });
  }

  testWidgets('outside tap dismisses palette without selecting a reaction', (
    tester,
  ) async {
    String? result = 'pending';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await SocialReactionPicker.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(500, 400));
    await tester.pumpAndSettle();
    expect(find.text('❤️'), findsNothing);
    expect(result, isNull);
  });
}
