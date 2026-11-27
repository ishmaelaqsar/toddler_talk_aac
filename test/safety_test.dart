import 'dart:convert';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toddler_talk_aac/data/card_repository.dart';
import 'package:toddler_talk_aac/theme.dart';
import 'package:toddler_talk_aac/widgets/page_tabs.dart';
import 'package:toddler_talk_aac/widgets/parent_gate.dart';

import 'test_harness.dart';

/// The app is meant to be safe in a toddler's hands. It was not: the board
/// could be dragged into a new order, a card could be deleted on one tap, and
/// parent mode never closed itself. When it did close itself, it could do so
/// under a parent who was busy in a sheet. A Back press or a swipe from the
/// system bars took the child out of the app. A board the app could not read
/// left a spinner that never ended. A hold alone opened parent mode, and a
/// patient child can hold a button.
void main() {
  List<Map<String, dynamic>> threeCards() => [
    storedCard(id: 'a', label: 'Apple'),
    storedCard(id: 'b', label: 'Ball'),
    storedCard(id: 'c', label: 'Cup'),
  ];

  /// The system UI modes the app asked for, in order.
  List<Object?> uiModes() => [
    for (final MethodCall call in platformCalls)
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') call.arguments,
  ];

  bool leftTheApp() =>
      platformCalls.any((call) => call.method == 'SystemNavigator.pop');

  final String hiddenBars = SystemUiMode.immersiveSticky.toString();
  final String shownBars = SystemUiMode.edgeToEdge.toString();

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

    testWidgets('shows no page control but the tabs', (tester) async {
      installMocks(
        storedCards: [
          storedCard(id: 'a', label: 'Apple', pageId: 'home'),
          storedCard(id: 'b', label: 'Ball', pageId: 'food'),
        ],
        storedPages: [storedPage('home', 'Home'), storedPage('food', 'Food')],
      );
      await pumpApp(tester);

      expect(find.byType(PageTabs), findsOneWidget);
      expect(find.byTooltip('Settings and backup'), findsNothing);
      for (final String control in [
        'Rename Home',
        'Choose a symbol for Food',
        'Move Food up',
        'Delete Food',
      ]) {
        expect(find.byTooltip(control), findsNothing, reason: control);
      }
    });

    testWidgets('a single tap on the lock does not unlock it', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      await tester.tap(find.byTooltip('Press and hold to edit cards'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle), findsNothing);
    });

    testWidgets('a system Back does not leave the app', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(leftTheApp(), isFalse);
      expect(find.text('Apple'), findsOneWidget);
    });

    testWidgets('the system bars are hidden', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      expect(uiModes(), [hiddenBars]);
    });

    // Android can show the bars again after a resume.
    testWidgets('the system bars hide again when the app comes back', (
      tester,
    ) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      platformCalls.clear();

      backgroundAndReturn(tester);
      await tester.pumpAndSettle();

      expect(uiModes(), isNotEmpty);
      expect(uiModes(), everyElement(hiddenBars));
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

    testWidgets('a system Back leaves the app as usual', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(leftTheApp(), isTrue);
    });

    testWidgets('the system bars show, and hide again at the lock', (
      tester,
    ) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      await enterParentMode(tester);
      expect(uiModes().last, shownBars);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(uiModes().last, hiddenBars);
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

      await tester.tap(find.byTooltip('Settings and backup'));
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

    for (final (String name, Future<void> Function(WidgetTester) open) in [
      ('settings', openSettings),
      ('pages', openPages),
    ]) {
      testWidgets('it stays open while the $name sheet is open', (
        tester,
      ) async {
        installMocks(storedCards: threeCards());
        await pumpApp(tester);
        await enterParentMode(tester);
        await open(tester);

        // The sheet is a route of its own, so its touches never reach the
        // board. A timer left running would lock parent mode under the parent.
        await tester.pump(AppTokens.parentModeTimeout * 2);
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.add_circle), findsOneWidget);

        await tester.pump(AppTokens.parentModeTimeout);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.add_circle), findsNothing);
      });
    }

    testWidgets('a sheet opened from the editor does not restart the lock', (
      tester,
    ) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Apple'));
      await tester.pumpAndSettle();

      // Change picture is a second flow inside the editor's flow.
      await tester.tap(find.text('Change picture'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.pump(AppTokens.parentModeTimeout * 2);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_circle), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pump(AppTokens.parentModeTimeout);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_circle), findsNothing);
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

  group('the parent gate', () {
    bool locked() => find.byIcon(Icons.add_circle).evaluate().isEmpty;
    bool gateOpen() => find.text('Grown-ups only').evaluate().isNotEmpty;

    testWidgets('the prompt names each digit in words', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showParentGate(context, random: _Draws(const [6, 1, 4])),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Tap seven, two, five'), findsOneWidget);
    });

    testWidgets('the hold alone does not open parent mode', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);

      await holdLock(tester);

      expect(gateOpen(), isTrue);
      expect(locked(), isTrue);
      expect(
        ttsCalls.where((c) => c.method == 'speak').map((c) => c.arguments),
        isNot(contains('Parent mode')),
      );
    });

    testWidgets('the right digits open parent mode', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await holdLock(tester);

      await solveParentGate(tester);

      expect(gateOpen(), isFalse);
      expect(locked(), isFalse);
    });

    testWidgets('a wrong key closes the gate and leaves the board locked', (
      tester,
    ) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await holdLock(tester);

      await tapGateKey(tester, gateCode(tester).first % 9 + 1);

      expect(gateOpen(), isFalse);
      expect(locked(), isTrue);
    });

    testWidgets('Cancel leaves the board locked', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await holdLock(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(gateOpen(), isFalse);
      expect(locked(), isTrue);
    });

    testWidgets('a tap outside leaves the board locked', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await holdLock(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(gateOpen(), isFalse);
      expect(locked(), isTrue);
    });

    testWidgets('it closes itself when no key comes', (tester) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await holdLock(tester);

      await tester.pump(AppTokens.gateTimeout);
      await tester.pumpAndSettle();

      expect(gateOpen(), isFalse);
      expect(locked(), isTrue);
    });

    testWidgets('each right key gives the parent the full time again', (
      tester,
    ) async {
      installMocks(storedCards: threeCards());
      await pumpApp(tester);
      await holdLock(tester);
      final List<int> code = gateCode(tester);
      final Duration nearly =
          AppTokens.gateTimeout - const Duration(seconds: 1);

      await tester.pump(nearly);
      await tapGateKey(tester, code[0]);
      await tester.pump(nearly);

      expect(gateOpen(), isTrue);
    });
  });

  group('a board the app cannot read', () {
    const String unreadable = 'not a board';

    Future<String?> stored(String key) async =>
        (await SharedPreferences.getInstance()).getString(key);

    testWidgets('shows a message and Try again, not a spinner', (tester) async {
      installMocks(rawStoredCards: unreadable);
      await pumpApp(tester);

      // The lock draws a ring with a value. The loading spinner has none.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CircularProgressIndicator && widget.value == null,
        ),
        findsNothing,
      );
      expect(find.text('The cards could not be loaded'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Ask a grown-up to help.'), findsOneWidget);
    });

    testWidgets('Try again loads the board once it can be read', (
      tester,
    ) async {
      installMocks(rawStoredCards: unreadable);
      await pumpApp(tester);

      await (await SharedPreferences.getInstance()).setString(
        CardRepository.storageKey,
        json.encode(threeCards()),
      );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Apple'), findsOneWidget);
    });

    // A new board puts the starter cards in place of the old ones.
    testWidgets('a child is not offered a new board', (tester) async {
      installMocks(rawStoredCards: unreadable);
      await pumpApp(tester);

      expect(find.text('Start a new board'), findsNothing);
    });

    testWidgets('a new board in parent mode keeps a copy of the old one', (
      tester,
    ) async {
      installMocks(rawStoredCards: unreadable);
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.text('Start a new board'));
      await tester.pumpAndSettle();

      expect(await stored(CardRepository.rescueKey), unreadable);
      expect((await savedOrder()).first, 'Hungry');
      expect(find.text('Hungry'), findsOneWidget);
    });

    // A save would put a new board over the one a retry can read.
    testWidgets('no control that writes the board shows', (tester) async {
      installMocks(rawStoredCards: unreadable);
      await pumpApp(tester);
      await enterParentMode(tester);

      expect(find.byTooltip('Add a card'), findsNothing);
      expect(find.text('Add your first card'), findsNothing);
      expect(find.byTooltip('Settings and backup'), findsNothing);
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(await stored(CardRepository.storageKey), unreadable);
    });
  });
}

/// Hands the gate [values] in order, as its random source.
class _Draws implements Random {
  _Draws(this.values);

  final List<int> values;
  int _next = 0;

  @override
  int nextInt(int max) => values[_next++];

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
