import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/theme.dart';
import 'package:toddler_talk_aac/widgets/card_tile.dart';

import 'test_harness.dart';

/// The old board fixed the card label at 20 logical pixels inside a quarter of
/// a square card, and chose two or three columns off a single 600px threshold.
/// It overflowed at a large text scale, and it wasted a tablet in landscape.
void main() {
  const Map<String, Size> viewports = {
    'small phone portrait': Size(320, 568),
    'small phone landscape': Size(568, 320),
    'tablet portrait': Size(800, 1280),
    'tablet landscape': Size(1280, 800),
  };

  List<Map<String, dynamic>> cards() => [
    storedCard(id: 'a', label: 'Cup'),
    storedCard(id: 'b', label: 'A very long card label indeed, and then some'),
    storedCard(id: 'c', label: 'Ball'),
  ];

  for (final MapEntry<String, Size> viewport in viewports.entries) {
    for (final double scale in [1.0, 1.5, 2.0]) {
      testWidgets('${viewport.key} at text scale $scale does not overflow', (
        tester,
      ) async {
        installMocks(storedCards: cards());
        await pumpApp(tester, size: viewport.value, textScale: scale);
        expect(tester.takeException(), isNull);

        // Parent mode adds the edit row, which is where a card runs out of
        // room first.
        await enterParentMode(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the board fits more cards across a wider screen', (
    tester,
  ) async {
    installMocks(storedCards: cards());

    await pumpApp(tester, size: const Size(320, 568));
    final double onPhone = tester.getSize(find.byType(CardTile).first).width;

    await pumpApp(tester, size: const Size(1280, 800));
    final double onTablet = tester.getSize(find.byType(CardTile).first).width;

    // A card stays about the same size, rather than growing to fill a tablet.
    expect(onTablet, lessThan(onPhone * 2));
    expect(onTablet, greaterThan(100));
  });

  testWidgets('a card stays a large touch target at every text scale', (
    tester,
  ) async {
    for (final double scale in [1.0, 1.5, 2.0]) {
      installMocks(storedCards: cards());
      await pumpApp(tester, size: const Size(320, 568), textScale: scale);

      final Size size = tester.getSize(find.byType(CardTile).first);
      expect(
        size.shortestSide,
        greaterThanOrEqualTo(AppTokens.minTouchTarget),
        reason: 'text scale $scale',
      );
    }
  });

  testWidgets('the label survives a long word instead of overflowing', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);

    // Rendered, clipped by the band, and no overflow exception.
    expect(
      find.textContaining('A very long card label', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picture keeps room even when the label is huge', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);

    final Size card = tester.getSize(find.byType(CardTile).first);
    final Size label = tester.getSize(
      find.descendant(
        of: find.byType(CardTile).first,
        matching: find.byType(ColoredBox),
      ),
    );
    expect(label.height, lessThanOrEqualTo(card.height * 0.61));
  });

  testWidgets('an empty board holds up on a small screen at scale 2.0', (
    tester,
  ) async {
    installMocks(storedCards: const []);
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);
    expect(tester.takeException(), isNull);

    await enterParentMode(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('The board is empty'), findsOneWidget);
  });

  testWidgets('the parent-mode banner leaves the board its room', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);
    await enterParentMode(tester);

    // The banner used to wrap until it claimed the whole screen.
    expect(find.byType(CardTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
