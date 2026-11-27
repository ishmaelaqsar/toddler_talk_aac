import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_harness.dart';

/// The app carried no semantics and no tooltips at all, so a screen reader
/// announced nothing a parent or child could act on. The parent gate must not
/// shut out a parent who uses one.
void main() {
  List<Map<String, dynamic>> oneCard() => [storedCard(id: 'a', label: 'Teddy')];

  testWidgets('a card announces its label as a button', (tester) async {
    installMocks(storedCards: oneCard());
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);

    final SemanticsNode node = tester.getSemantics(
      find.bySemanticsLabel('Teddy'),
    );
    expect(node.label, 'Teddy');
    // A button a screen reader can both announce and activate.
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    handle.dispose();
  });

  testWidgets('the lock explains that it needs a hold', (tester) async {
    installMocks(storedCards: oneCard());
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);

    expect(find.bySemanticsLabel('Unlock editing'), findsOneWidget);
    expect(find.byTooltip('Press and hold to edit cards'), findsOneWidget);

    // A hold is a gesture assistive technology cannot make, so the same action
    // is offered as a long press.
    final SemanticsNode node = tester.getSemantics(
      find.bySemanticsLabel('Unlock editing'),
    );
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
    );

    handle.dispose();
  });

  testWidgets('the lock says how to leave parent mode', (tester) async {
    installMocks(storedCards: oneCard());
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);
    await enterParentMode(tester);

    expect(find.bySemanticsLabel('Lock editing'), findsOneWidget);
    expect(find.byTooltip('Tap to stop editing'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('every icon-only control carries a tooltip', (tester) async {
    installMocks(storedCards: oneCard());
    await pumpApp(tester);
    await enterParentMode(tester);

    for (final String tooltip in [
      'Add a card',
      'Settings and backup',
      'Edit Teddy',
      'Hide Teddy from your child',
      'Delete Teddy',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
  });

  testWidgets('a hidden card says so, and offers to show it', (tester) async {
    installMocks(
      storedCards: [storedCard(id: 'a', label: 'Teddy', isVisible: false)],
    );
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);
    await enterParentMode(tester);

    expect(
      find.bySemanticsLabel('Teddy. Hidden from your child. Tap to edit.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Show Teddy to your child'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('each settings choice says its name and whether it is chosen', (
    tester,
  ) async {
    installMocks(storedCards: oneCard());
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);
    await enterParentMode(tester);
    await openSettings(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('British')),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('American')),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
    );
    for (final String name in ['Normal', 'Slow', 'Small', 'Medium', 'Large']) {
      expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
    }

    handle.dispose();
  });

  List<Map<String, dynamic>> twoPages() => [
    storedPage('home', 'Home'),
    storedPage('food', 'Food'),
  ];

  List<Map<String, dynamic>> pagedCards() => [
    storedCard(id: 'a', label: 'Teddy', pageId: 'home'),
    storedCard(id: 'b', label: 'Apple', pageId: 'food'),
  ];

  testWidgets('a page tab says its name and whether it is open', (
    tester,
  ) async {
    installMocks(storedCards: pagedCards(), storedPages: twoPages());
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Home')),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Food')),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
    );

    handle.dispose();
  });

  testWidgets('each control in the pages sheet names its page', (tester) async {
    installMocks(storedCards: pagedCards(), storedPages: twoPages());
    await pumpApp(tester);
    await enterParentMode(tester);
    await openPages(tester);

    for (final String page in ['Home', 'Food']) {
      for (final String tooltip in [
        'Rename $page',
        'Choose a symbol for $page',
        'Move $page up',
        'Move $page down',
        'Delete $page',
      ]) {
        expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      }
    }
  });

  testWidgets('the empty board tells the child what to do', (tester) async {
    installMocks(storedCards: const []);
    await pumpApp(tester);

    expect(find.text('Ask a grown-up to add some cards'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle), findsNothing);
  });

  testWidgets('the long-press action on the lock opens the gate too', (
    tester,
  ) async {
    installMocks(storedCards: oneCard());
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);

    tester.semantics.longPress(find.semantics.byLabel('Unlock editing'));
    await tester.pumpAndSettle();

    expect(find.text('Grown-ups only'), findsOneWidget);
    expect(find.bySemanticsLabel('Lock editing'), findsNothing);

    handle.dispose();
  });

  testWidgets('each gate key announces its digit as a button', (tester) async {
    installMocks(storedCards: oneCard());
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);
    await holdLock(tester);

    for (int digit = 1; digit <= 9; digit++) {
      final SemanticsNode node = tester.getSemantics(gateKey(digit));
      expect(node.label, '$digit');
      expect(node.flagsCollection.isButton, isTrue, reason: '$digit');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: '$digit',
      );
    }

    handle.dispose();
  });

  testWidgets('a screen reader reaches the gate prompt', (tester) async {
    installMocks(storedCards: oneCard());
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester);
    await holdLock(tester);

    expect(
      find.bySemanticsLabel(RegExp(r'^Tap [a-z]+, [a-z]+, [a-z]+$')),
      findsOneWidget,
    );

    handle.dispose();
  });
}
