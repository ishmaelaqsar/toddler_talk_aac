import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/theme.dart';

import 'test_harness.dart';

/// The app is meant to be safe in a toddler's hands. It was not: the board
/// could be dragged into a new order, a card could be deleted on one tap, and
/// parent mode never closed itself.
void main() {
  List<Map<String, dynamic>> threeCards() => [
    storedCard(id: 'a', label: 'Apple'),
    storedCard(id: 'b', label: 'Ball'),
    storedCard(id: 'c', label: 'Cup'),
  ];

  group('toddler mode', () {
    testWidgets('shows no editing control at all', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      expect(find.byIcon(Icons.add_circle), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('a drag does not reorder the board', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      await dragCardRight(tester, 'Apple');

      expect(await savedOrder(), ['Apple', 'Ball', 'Cup']);
    });

    testWidgets('a tap does not open the editor', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      await tester.tap(find.text('Apple'));
      await tester.pumpAndSettle();

      expect(find.text('Card details'), findsNothing);
    });

    testWidgets('a hidden card is not on the board', (tester) async {
      installMocks(
        storedCards: [
          storedCard(id: 'a', label: 'Apple'),
          storedCard(id: 'b', label: 'Ball', isVisible: false),
        ],
      );
      await pumpApp(tester);

      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('Ball'), findsNothing);
    });

    testWidgets('a single tap on the lock does not unlock it', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      await tester.tap(find.byTooltip('Press and hold to edit cards'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle), findsNothing);
    });
  });

  group('parent mode', () {
    testWidgets('a hold on the lock opens it', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      expect(find.byIcon(Icons.add_circle), findsOneWidget);
      expect(find.textContaining('Parent mode'), findsOneWidget);
    });

    // The control for the toddler-mode drag test: the same gesture must work
    // here, or that test proves nothing.
    testWidgets('a drag does reorder the board', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      await dragCardRight(tester, 'Apple');

      expect(await savedOrder(), ['Ball', 'Apple', 'Cup']);
    });

    testWidgets('delete asks first, and Keep keeps the card', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Delete Apple'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Apple?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(find.text('Apple'), findsOneWidget);
      expect(await savedOrder(), ['Apple', 'Ball', 'Cup']);
    });

    testWidgets('delete removes the card once confirmed', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Delete Apple'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await savedOrder(), ['Ball', 'Cup']);
    });

    testWidgets('restore asks before it replaces the board', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Backup and restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore Data'));
      await tester.pumpAndSettle();

      expect(find.text('Restore a backup?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(await savedOrder(), ['Apple', 'Ball', 'Cup']);
    });

    testWidgets('hiding a card keeps it, and the child stops seeing it', (
      tester,
    ) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Hide Apple from your child'));
      await tester.pumpAndSettle();

      // Still there for the parent, and still saved.
      expect(find.text('Apple'), findsOneWidget);
      expect(await savedOrder(), ['Apple', 'Ball', 'Cup']);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Apple'), findsNothing);
    });

    testWidgets('it locks itself after a spell of no input', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);
      expect(find.byIcon(Icons.add_circle), findsOneWidget);

      await tester.pump(AppTokens.parentModeTimeout);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle), findsNothing);
      expect(find.text('Editing locked itself.'), findsOneWidget);
    });

    testWidgets('Done leaves it at once', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle), findsNothing);
    });

    testWidgets('leaving the app and coming back locks it', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      backgroundAndReturn(tester);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle), findsNothing);
    });
  });
}
