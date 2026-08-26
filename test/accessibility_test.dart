import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_harness.dart';

/// The app carried no semantics and no tooltips at all, so a screen reader
/// announced nothing a parent or child could act on.
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
      'Backup and restore',
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

  testWidgets('the empty board tells the child what to do', (tester) async {
    installMocks(storedCards: const []);
    await pumpApp(tester);

    expect(find.text('Ask a grown-up to add some cards'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle), findsNothing);
  });
}
