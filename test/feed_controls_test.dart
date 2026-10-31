import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/widgets/post_action_button.dart';
import 'package:social_app/core/widgets/social_navigation.dart';

Widget _page() => MaterialApp(
  home: ScrollNavigationVisibility(
    child: Scaffold(
      appBar: AppBar(title: const Text('Linko toolbar')),
      body: Column(
        children: [
          const ScrollHidingHeader(
            child: SizedBox(
              height: 100,
              child: Center(child: Text('composer')),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 80,
              itemBuilder: (_, index) =>
                  SizedBox(height: 100, child: Text('post $index')),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const ScrollHidingNavigationBar(
        child: SizedBox(height: 64, child: Text('bottom navigation')),
      ),
    ),
  ),
);

void main() {
  testWidgets('scroll hides composer and navigation but keeps the toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('composer'), findsNothing);
    expect(find.text('bottom navigation'), findsNothing);
    expect(find.text('Linko toolbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling up restores composer and bottom navigation', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('composer'), findsOneWidget);
    expect(find.text('bottom navigation'), findsOneWidget);
    expect(find.text('Linko toolbar'), findsOneWidget);
  });

  testWidgets('horizontal scrolling does not hide feed controls', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    UserScrollNotification(
      metrics: FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 500,
        pixels: 100,
        viewportDimension: 300,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 1,
      ),
      context: tester.element(find.byType(ListView)),
      direction: ScrollDirection.reverse,
    ).dispatch(tester.element(find.byType(ListView)));
    await tester.pumpAndSettle();
    expect(find.text('composer'), findsOneWidget);
    expect(find.text('bottom navigation'), findsOneWidget);
  });

  testWidgets(
    'icon actions have no visible labels and preserve the requested order',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (final (icon, label) in [
                  (Icons.thumb_up_alt_outlined, 'ถูกใจ'),
                  (Icons.thumb_down_alt_outlined, 'ไม่ถูกใจ'),
                  (Icons.mode_comment_outlined, 'ความคิดเห็น'),
                  (Icons.share_outlined, 'แชร์'),
                ])
                  Expanded(
                    child: PostActionButton(
                      icon: icon,
                      label: label,
                      onPressed: () {},
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('ถูกใจ'), findsNothing);
      expect(find.text('ไม่ถูกใจ'), findsNothing);
      expect(find.text('ความคิดเห็น'), findsNothing);
      final icons = tester
          .widgetList<Icon>(find.byType(Icon))
          .map((icon) => icon.icon);
      expect(icons, [
        Icons.thumb_up_alt_outlined,
        Icons.thumb_down_alt_outlined,
        Icons.mode_comment_outlined,
        Icons.share_outlined,
      ]);
      expect(find.byTooltip('แชร์'), findsOneWidget);
    },
  );

  testWidgets('long press still invokes the reaction picker callback once', (
    tester,
  ) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostActionButton(
            icon: Icons.thumb_up_alt_outlined,
            label: 'ถูกใจ',
            onPressed: () => taps++,
            onLongPress: (_) => holds++,
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(PostActionButton));
    await tester.pumpAndSettle();
    expect(holds, 1);
    expect(taps, 0);
  });
}
