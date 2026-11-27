import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/data/card_repository.dart';
import 'package:toddler_talk_aac/models/board_page.dart';
import 'package:toddler_talk_aac/models/talk_card.dart';
import 'package:toddler_talk_aac/widgets/page_tabs.dart';

import 'test_harness.dart';

/// Every card sat on one long board. As the board grew, a parent had no way
/// to group the cards, and a child had to scroll past all of them.
void main() {
  List<Map<String, dynamic>> threePages() => [
    storedPage('home', 'Home'),
    storedPage('food', 'Food'),
    storedPage('play', 'Play'),
  ];

  List<Map<String, dynamic>> pagedCards() => [
    storedCard(id: 'cup', label: 'Cup', pageId: 'home'),
    storedCard(id: 'apple', label: 'Apple', pageId: 'food'),
    storedCard(id: 'ball', label: 'Ball', pageId: 'play'),
    storedCard(id: 'banana', label: 'Banana', pageId: 'food'),
  ];

  List<String> spokenWords() => ttsCalls
      .where((c) => c.method == 'speak')
      .map((c) => c.arguments.toString())
      .toList();

  Future<List<String>> savedPageNames() async =>
      (await CardRepository().loadPages()).map((page) => page.name).toList();

  group('the page helpers', () {
    const List<BoardPage> pages = [
      BoardPage(id: 'home', name: 'Home'),
      BoardPage(id: 'food', name: 'Food'),
    ];

    TalkCard card(String id, {String? page}) => TalkCard(
      id: id,
      label: id,
      kind: CardMediaKind.emoji,
      content: id,
      pageId: page,
    );

    List<String> ids(List<TalkCard> cards) => cards.map((c) => c.id).toList();

    // Two cards on each page, in alternate places on the board.
    final List<TalkCard> board = [
      card('h1', page: 'home'),
      card('f1', page: 'food'),
      card('h2', page: 'home'),
      card('f2', page: 'food'),
      card('f3', page: 'food'),
      card('h3', page: 'home'),
    ];

    test('a card with a missing or unknown page lands on the first page', () {
      expect(pageIdOf(card('a'), pages), 'home');
      expect(pageIdOf(card('b', page: 'gone'), pages), 'home');
      expect(pageIdOf(card('c', page: 'food'), pages), 'food');
    });

    test('the cards on a page keep their board order', () {
      final List<TalkCard> mixed = [
        card('a', page: 'food'),
        card('b'),
        card('c', page: 'food'),
        card('d', page: 'gone'),
      ];

      expect(ids(cardsOnPage(mixed, pages, 'food')), ['a', 'c']);
      expect(ids(cardsOnPage(mixed, pages, 'home')), ['b', 'd']);
    });

    test('a drag inside one page leaves the other pages alone', () {
      expect(ids(reorderWithinPage(board, pages, 'food', 0, 1)), [
        'h1',
        'f2',
        'h2',
        'f1',
        'f3',
        'h3',
      ]);
    });

    test('a drag reaches the first and the last place on a page', () {
      expect(ids(reorderWithinPage(board, pages, 'food', 2, 0)), [
        'h1',
        'f3',
        'h2',
        'f1',
        'f2',
        'h3',
      ]);
      expect(ids(reorderWithinPage(board, pages, 'food', 0, 2)), [
        'h1',
        'f2',
        'h2',
        'f3',
        'f1',
        'h3',
      ]);
    });
  });

  group('the tabs', () {
    testWidgets('a tab opens its page', (tester) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await pumpApp(tester);
      expect(find.text('Cup'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);

      await tester.tap(pageTab('Food'));
      await tester.pumpAndSettle();

      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('Banana'), findsOneWidget);
      expect(find.text('Cup'), findsNothing);
    });

    testWidgets('a tab speaks its name to a child, and not to a parent', (
      tester,
    ) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await pumpApp(tester);

      await tester.tap(pageTab('Food'));
      await tester.pumpAndSettle();
      expect(spokenWords(), ['Food']);

      await enterParentMode(tester);
      ttsCalls.clear();
      await tester.tap(pageTab('Play'));
      await tester.pumpAndSettle();
      expect(spokenWords(), isEmpty);
    });

    testWidgets('a page with only hidden cards has no tab for a child', (
      tester,
    ) async {
      installMocks(
        storedCards: [
          storedCard(id: 'cup', label: 'Cup', pageId: 'home'),
          storedCard(
            id: 'apple',
            label: 'Apple',
            pageId: 'food',
            isVisible: false,
          ),
          storedCard(id: 'ball', label: 'Ball', pageId: 'play'),
        ],
        storedPages: threePages(),
      );
      await pumpApp(tester);
      expect(pageTab('Home'), findsOneWidget);
      expect(pageTab('Food'), findsNothing);
      expect(pageTab('Play'), findsOneWidget);

      // A parent sees every page.
      await enterParentMode(tester);
      expect(pageTab('Food'), findsOneWidget);
    });

    testWidgets('one tab to show means no tab row', (tester) async {
      installMocks(
        storedCards: [
          storedCard(id: 'cup', label: 'Cup', pageId: 'home'),
          storedCard(
            id: 'apple',
            label: 'Apple',
            pageId: 'food',
            isVisible: false,
          ),
        ],
        storedPages: [storedPage('home', 'Home'), storedPage('food', 'Food')],
      );
      await pumpApp(tester);

      expect(find.byType(PageTabs), findsNothing);
      expect(find.text('Cup'), findsOneWidget);
    });

    testWidgets('an open page with every card hidden gives way at the lock', (
      tester,
    ) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(pageTab('Food'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Hide Apple from your child'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide Banana from your child'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(pageTab('Food'), findsNothing);
      expect(find.text('Cup'), findsOneWidget);
    });
  });

  group('the pages sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      await pumpApp(tester);
      await enterParentMode(tester);
      await openPages(tester);
    }

    IconButton control(WidgetTester tester, String tooltip) =>
        tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          ),
        );

    testWidgets('Add a page appends one', (tester) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await openSheet(tester);

      await tester.tap(find.text('Add a page'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Toys');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(await savedPageNames(), ['Home', 'Food', 'Play', 'Toys']);
      expect(find.byTooltip('Rename Toys'), findsOneWidget);
      expect(pageTab('Toys'), findsOneWidget);
    });

    testWidgets('rename changes the name, and an empty name cannot be saved', (
      tester,
    ) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await openSheet(tester);

      await tester.tap(find.byTooltip('Rename Food'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  ');
      await tester.pumpAndSettle();
      expect(find.text('A page needs a name'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save'))
            .enabled,
        isFalse,
      );

      await tester.enterText(find.byType(TextField), 'Snacks');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await savedPageNames(), ['Home', 'Snacks', 'Play']);
      expect(find.byTooltip('Rename Snacks'), findsOneWidget);
      expect(pageTab('Snacks'), findsOneWidget);
    });

    testWidgets('a chosen symbol is saved and shows on the tab', (
      tester,
    ) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await openSheet(tester);

      await tester.tap(find.byTooltip('Choose a symbol for Food'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bathe');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bathe'));
      await tester.pumpAndSettle();

      expect(
        (await CardRepository().loadPages())[1].symbol,
        'assets/symbols/bathe_,_to.svg',
      );
      expect(
        find.descendant(
          of: find.byType(PageTabs),
          matching: find.byType(SvgPicture),
        ),
        findsOneWidget,
      );
    });

    testWidgets('move up and move down reorder the pages', (tester) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await openSheet(tester);

      expect(control(tester, 'Move Home up').onPressed, isNull);
      expect(control(tester, 'Move Play down').onPressed, isNull);

      await tester.tap(find.byTooltip('Move Food up'));
      await tester.pumpAndSettle();
      expect(await savedPageNames(), ['Food', 'Home', 'Play']);

      await tester.tap(find.byTooltip('Move Food down'));
      await tester.pumpAndSettle();
      expect(await savedPageNames(), ['Home', 'Food', 'Play']);
    });

    testWidgets('the last page cannot be deleted', (tester) async {
      installMocks(
        storedCards: pagedCards(),
        storedPages: [storedPage('home', 'Home')],
      );
      await openSheet(tester);

      expect(control(tester, 'Delete Home').onPressed, isNull);
    });

    testWidgets('a deleted page hands its cards to the first page', (
      tester,
    ) async {
      installMocks(
        storedCards: [
          storedCard(id: 'cup', label: 'Cup', pageId: 'home'),
          storedCard(
            id: 'apple',
            label: 'Apple',
            pageId: 'food',
            isVisible: false,
          ),
          storedCard(id: 'banana', label: 'Banana', pageId: 'food'),
          storedCard(id: 'ball', label: 'Ball', pageId: 'play'),
        ],
        storedPages: threePages(),
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(pageTab('Food'));
      await tester.pumpAndSettle();
      await openPages(tester);

      await tester.tap(find.byTooltip('Delete Food'));
      await tester.pumpAndSettle();
      expect(
        find.text('Its 2 cards move to Home. No card is deleted.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await savedPageNames(), ['Home', 'Play']);
      final List<TalkCard> saved = await savedCards();
      expect(saved.map((c) => c.label), ['Cup', 'Apple', 'Banana', 'Ball']);
      expect(saved.map((c) => c.pageId), ['home', 'home', 'home', 'play']);
      // A hidden card stays hidden.
      expect(saved.map((c) => c.isVisible), [true, false, true, true]);
      expect(find.byTooltip('Delete Food'), findsNothing);

      // The deleted page was open, so the first page opens.
      expect(find.byTooltip('Edit Banana'), findsOneWidget);
      expect(find.byTooltip('Edit Ball'), findsNothing);
    });
  });

  group('cards and pages', () {
    testWidgets('a new card lands on the open page', (tester) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(pageTab('Food'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add a card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Symbol Library'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bathe');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bathe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final TalkCard added = (await savedCards()).last;
      expect(added.label, 'Bathe');
      expect(added.pageId, 'food');
    });

    testWidgets('the editor moves a card to the page chosen', (tester) async {
      installMocks(storedCards: pagedCards(), storedPages: threePages());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(pageTab('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit Apple'));
      await tester.pumpAndSettle();

      Finder inEditor(String text) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(text),
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.ancestor(
                of: inEditor('Food'),
                matching: find.byType(ChoiceChip),
              ),
            )
            .selected,
        isTrue,
      );
      await tester.ensureVisible(inEditor('Play'));
      await tester.tap(inEditor('Play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        (await savedCards()).firstWhere((c) => c.id == 'apple').pageId,
        'play',
      );
      expect(find.text('Apple'), findsNothing);
    });

    testWidgets('with one page, the editor offers no page choice', (
      tester,
    ) async {
      installMocks(
        storedCards: [storedCard(id: 'cup', label: 'Cup')],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      expect(find.text('Page'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('a drag reorders one page and leaves the others in place', (
      tester,
    ) async {
      installMocks(
        storedCards: [
          storedCard(id: 'cup', label: 'Cup', pageId: 'home'),
          storedCard(id: 'apple', label: 'Apple', pageId: 'food'),
          storedCard(id: 'ball', label: 'Ball', pageId: 'home'),
          storedCard(id: 'banana', label: 'Banana', pageId: 'food'),
          storedCard(id: 'car', label: 'Car', pageId: 'home'),
        ],
        storedPages: [storedPage('home', 'Home'), storedPage('food', 'Food')],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(pageTab('Food'));
      await tester.pumpAndSettle();

      await dragCardRight(tester, 'Apple');

      expect(await savedOrder(), ['Cup', 'Banana', 'Ball', 'Apple', 'Car']);
    });
  });
}
