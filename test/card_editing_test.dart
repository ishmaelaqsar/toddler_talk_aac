import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/widgets/symbol_picker.dart';

import 'test_harness.dart';

/// A card could only be added or deleted. Renaming one, re-recording it, or
/// swapping its picture meant deleting it and starting again.
void main() {
  List<Map<String, dynamic>> oneCard() => [storedCard(id: 'a', label: 'Cup')];

  group('the editor', () {
    testWidgets('opens from the pencil, seeded with the card', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      expect(find.text('Card details'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Cup',
      );
    });

    testWidgets('opens from a tap on the card in parent mode', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.text('Cup'));
      await tester.pumpAndSettle();

      expect(find.text('Card details'), findsOneWidget);
    });

    testWidgets('renaming a card sticks', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Milk');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);
      expect(await savedOrder(), ['Milk']);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Milk');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await savedOrder(), ['Cup']);
    });

    testWidgets('an empty label cannot be saved, and says why', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();

      // Save used to look live and then do nothing at all.
      expect(find.text('A card needs a word'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).enabled,
        isFalse,
      );
    });

    testWidgets('it offers a colour for the card', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      expect(find.text('Card colour'), findsOneWidget);
      expect(find.bySemanticsLabel('Card colour 3'), findsOneWidget);
    });

    testWidgets('it explains what a recording is for', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Record your voice'), findsOneWidget);
      expect(
        find.text('Optional. Without one, the robot voice reads the word.'),
        findsOneWidget,
      );
    });
  });

  group('the add sheet', () {
    testWidgets('leaves Giphy out when no key is configured', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Add a card'));
      await tester.pumpAndSettle();

      // Offering it and then failing told the parent to edit a file they have
      // no way to reach.
      expect(find.text('Giphy Search'), findsNothing);
      expect(find.text('Symbol Library'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Photo Gallery'), findsOneWidget);
    });

    testWidgets('offers Giphy when a key is configured', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester, giphyApiKey: 'a-key');
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Add a card'));
      await tester.pumpAndSettle();

      expect(find.text('Giphy Search'), findsOneWidget);
    });
  });

  group('the symbol library', () {
    testWidgets('is searchable, and names the symbols readably', (
      tester,
    ) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Add a card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Symbol Library'));
      await tester.pumpAndSettle();

      // Hundreds of symbols in a plain grid was not browsable.
      expect(find.textContaining('Search'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bathe');
      await tester.pumpAndSettle();
      expect(find.text('Bathe'), findsOneWidget);
    });

    test('a file name becomes a label a parent would write', () {
      // The bundled set qualifies an entry after a comma or a dash.
      expect(prettifySymbolName('assets/symbols/bathe_,_to.svg'), 'Bathe');
      expect(prettifySymbolName('assets/symbols/shoe_-_mans.svg'), 'Shoe');
      expect(
        prettifySymbolName('assets/symbols/chest_of_drawers.svg'),
        'Chest of drawers',
      );
      expect(prettifySymbolName('assets/symbols/settee_1.svg'), 'Settee 1');
      // A dash inside a word is part of the word, not a qualifier.
      expect(prettifySymbolName('assets/symbols/t-shirt.svg'), 'T-shirt');
    });
  });

  group('a recording', () {
    /// Records a take and returns the file the recorder wrote.
    Future<File> recordTake(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Record your voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stop recording'));
      await tester.pumpAndSettle();

      final MethodCall start = recorderCalls.firstWhere(
        (c) => c.method == 'start',
      );
      return File((start.arguments as Map)['path'] as String);
    }

    testWidgets('offers playback once it is made', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      await recordTake(tester);

      expect(find.byTooltip('Play the recording'), findsOneWidget);
      expect(find.byTooltip('Record again'), findsOneWidget);
      expect(find.byTooltip('Remove the recording'), findsOneWidget);
      expect(
        find.text('Your recording plays instead of the robot voice.'),
        findsOneWidget,
      );
    });

    testWidgets('is kept on the card when saved', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      final File take = await recordTake(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(take.existsSync(), isTrue);
      addTearDown(() => take.deleteSync());
    });

    testWidgets('an abandoned take is cleaned off the device', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      final File take = await recordTake(tester);
      expect(take.existsSync(), isTrue);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);

      expect(take.existsSync(), isFalse);
    });

    testWidgets("cancelling keeps the card's existing recording", (
      tester,
    ) async {
      final Directory dir = Directory.systemTemp.createTempSync('tt_keep');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File original = File('${dir.path}/original.m4a')
        ..writeAsBytesSync(const [9]);

      installMocks(
        storedCards: [
          storedCard(id: 'a', label: 'Cup', audioPath: original.path),
        ],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      // Re-record, then change your mind. The card still points at the
      // original, so deleting it would lose a recording the parent still has.
      await tester.tap(find.byTooltip('Record again'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stop recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);

      expect(original.existsSync(), isTrue);
    });
  });

  group('removing a recording', () {
    /// A recording sitting where the app writes its own.
    File appRecording() =>
        File('${appDocuments.path}/mine.m4a')..writeAsBytesSync(const [9]);

    Future<void> openEditorAndRemove(WidgetTester tester) async {
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove the recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);
    }

    testWidgets('deletes the file, when the app is what recorded it', (
      tester,
    ) async {
      installMocks();
      final File recording = appRecording();
      installMocks(
        storedCards: [
          storedCard(id: 'a', label: 'Cup', audioPath: recording.path),
        ],
      );
      await pumpApp(tester);

      await openEditorAndRemove(tester);

      expect(recording.existsSync(), isFalse);
      expect(await savedOrder(), ['Cup']);
    });

    testWidgets('leaves a file the app did not record', (tester) async {
      final Directory elsewhere = Directory.systemTemp.createTempSync(
        'tt_else',
      );
      addTearDown(() => elsewhere.deleteSync(recursive: true));
      final File theirs = File('${elsewhere.path}/theirs.m4a')
        ..writeAsBytesSync(const [9]);

      installMocks(
        storedCards: [
          storedCard(id: 'a', label: 'Cup', audioPath: theirs.path),
        ],
      );
      await pumpApp(tester);

      await openEditorAndRemove(tester);

      expect(theirs.existsSync(), isTrue);
    });

    testWidgets('re-recording drops the take it replaced', (tester) async {
      installMocks();
      final File recording = appRecording();
      installMocks(
        storedCards: [
          storedCard(id: 'a', label: 'Cup', audioPath: recording.path),
        ],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Record again'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stop recording'));
      await tester.pumpAndSettle();

      final MethodCall start = recorderCalls.firstWhere(
        (c) => c.method == 'start',
      );
      final File fresh = File((start.arguments as Map)['path'] as String);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);

      expect(fresh.existsSync(), isTrue);
      expect(recording.existsSync(), isFalse);
    });
  });
}
