import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/models/talk_card.dart';
import 'package:toddler_talk_aac/theme.dart';
import 'package:toddler_talk_aac/widgets/card_tile.dart';
import 'package:toddler_talk_aac/widgets/symbol_picker.dart';

import 'test_harness.dart';

/// A card could only be added or deleted. Renaming one, re-recording it, or
/// swapping its picture meant deleting it and starting again. A restore left
/// the replaced board's files on the device. A card could only say its label.
/// The editor raised the keyboard over every card, and a recording had no
/// time limit.
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
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
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
      await tester.enterText(find.byType(TextField).first, 'Milk');
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
      await tester.enterText(find.byType(TextField).first, 'Milk');
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
      await tester.enterText(find.byType(TextField).first, '   ');
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

    bool labelHasFocus(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText).first)
        .focusNode
        .hasFocus;

    // The keyboard covered most of the dialog, so a parent who opened a card
    // to change its colour had to close the keyboard first.
    testWidgets('it leaves the keyboard down when the card has a word', (
      tester,
    ) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      expect(labelHasFocus(tester), isFalse);
    });

    testWidgets('it puts the cursor in an empty label', (tester) async {
      installMocks(
        storedCards: [storedCard(id: 'a', label: '')],
      );
      await pumpApp(tester);
      await enterParentMode(tester);

      await tester.tap(find.byType(CardTile));
      await tester.pumpAndSettle();

      expect(labelHasFocus(tester), isTrue);
    });
  });

  group('the speech text', () {
    Finder speechField() =>
        find.widgetWithText(TextField, 'What it says (optional)');

    Future<void> openEditor(WidgetTester tester) async {
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();
    }

    List<String> spokenWords() => ttsCalls
        .where((c) => c.method == 'speak')
        .map((c) => c.arguments.toString())
        .toList();

    testWidgets('is saved with the card', (tester) async {
      installMocks(storedCards: oneCard());
      await openEditor(tester);

      await tester.enterText(speechField(), 'Can I have a drink?');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect((await savedCards()).single.speech, 'Can I have a drink?');
    });

    testWidgets('cleared, it gives the card back its label', (tester) async {
      installMocks(
        storedCards: [storedCard(id: 'a', label: 'Cup', speech: 'A drink')],
      );
      await openEditor(tester);

      await tester.enterText(speechField(), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final TalkCard saved = (await savedCards()).single;
      expect(saved.speech, isNull);
      expect(saved.spokenText, 'Cup');
    });

    testWidgets('Hear it speaks the speech text, or the label when it is '
        'empty', (tester) async {
      installMocks(storedCards: oneCard());
      await openEditor(tester);

      await tester.tap(find.text('Hear it'));
      await tester.pumpAndSettle();
      expect(spokenWords().last, 'Cup');

      await tester.enterText(speechField(), 'A drink, please');
      await tester.tap(find.text('Hear it'));
      await tester.pumpAndSettle();
      expect(spokenWords().last, 'A drink, please');
    });

    testWidgets('it says that a recording plays in its place', (tester) async {
      installMocks(storedCards: oneCard());
      await openEditor(tester);

      expect(
        find.textContaining(
          'A recording, when there is one, plays in place '
          'of this text.',
        ),
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

    testWidgets('the timer shows the time limit', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Record your voice'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('0:03 / 0:10'), findsOneWidget);
    });

    // A take had no end, so a take a parent forgot kept recording.
    testWidgets('it stops itself at the limit, and keeps the take', (
      tester,
    ) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Record your voice'));
      await tester.pumpAndSettle();
      await tester.pump(AppTokens.recordingLimit);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Stop recording'), findsNothing);
      expect(find.byTooltip('Play the recording'), findsOneWidget);
      expect(recorderCalls.where((c) => c.method == 'stop'), hasLength(1));
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

  group('replacing a picture', () {
    /// A card whose picture is a file the app owns.
    Future<File> pumpCardWithPhoto(WidgetTester tester) async {
      installMocks();
      final File photo = File('${appDocuments.path}/face.jpg')
        ..writeAsBytesSync(const [9]);
      installMocks(
        storedCards: [storedCard(id: 'a', label: 'Cup', content: photo.path)],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();
      return photo;
    }

    /// Swaps the picture for a bundled symbol, which owns no file.
    Future<void> pickSymbol(WidgetTester tester) async {
      await tester.tap(find.text('Change picture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Symbol Library'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'bathe');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bathe'));
      await tester.pumpAndSettle();
    }

    testWidgets('saving deletes the old picture by default', (tester) async {
      final File photo = await pumpCardWithPhoto(tester);
      await pickSymbol(tester);

      expect(
        find.text('Delete the file it replaces from this device'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);

      expect(photo.existsSync(), isFalse);
    });

    testWidgets('unticking the box keeps the old picture', (tester) async {
      final File photo = await pumpCardWithPhoto(tester);
      await pickSymbol(tester);

      await tester.tap(
        find.text('Delete the file it replaces from this device'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);

      expect(photo.existsSync(), isTrue);
    });

    testWidgets('cancelling keeps the old picture', (tester) async {
      final File photo = await pumpCardWithPhoto(tester);
      await pickSymbol(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);

      expect(photo.existsSync(), isTrue);
    });

    testWidgets('the box is not offered when nothing is replaced', (
      tester,
    ) async {
      installMocks(
        storedCards: [
          storedCard(
            id: 'a',
            label: 'Cup',
            kind: CardMediaKind.asset,
            content: 'assets/symbols/water.svg',
          ),
        ],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Milk');
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('both replaced files are counted together', (tester) async {
      installMocks();
      final File photo = File('${appDocuments.path}/face.jpg')
        ..writeAsBytesSync(const [9]);
      final File voice = File('${appDocuments.path}/mummy.m4a')
        ..writeAsBytesSync(const [9]);
      installMocks(
        storedCards: [
          storedCard(
            id: 'a',
            label: 'Cup',
            content: photo.path,
            audioPath: voice.path,
          ),
        ],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Edit Cup'));
      await tester.pumpAndSettle();

      await pickSymbol(tester);
      await tester.tap(find.byTooltip('Remove the recording'));
      await tester.pumpAndSettle();

      expect(
        find.text('Delete the 2 files it replaces from this device'),
        findsOneWidget,
      );
    });
  });

  group('deleting a card', () {
    Future<File> pumpCardWithPhoto(WidgetTester tester) async {
      installMocks();
      final File photo = File('${appDocuments.path}/face.jpg')
        ..writeAsBytesSync(const [9]);
      installMocks(
        storedCards: [storedCard(id: 'a', label: 'Cup', content: photo.path)],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Delete Cup'));
      await tester.pumpAndSettle();
      return photo;
    }

    testWidgets('its picture goes with it by default', (tester) async {
      final File photo = await pumpCardWithPhoto(tester);

      expect(find.text('Delete its picture from this device'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);

      expect(await savedOrder(), isEmpty);
      expect(photo.existsSync(), isFalse);
    });

    testWidgets('unticking the box keeps the picture on the device', (
      tester,
    ) async {
      final File photo = await pumpCardWithPhoto(tester);

      // A family photo can outlive the card that used it.
      await tester.tap(find.text('Delete its picture from this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await settleFileWork(tester);

      expect(await savedOrder(), isEmpty);
      expect(photo.existsSync(), isTrue);
    });

    testWidgets('a recording is named alongside the picture', (tester) async {
      installMocks();
      installMocks(
        storedCards: [
          storedCard(
            id: 'a',
            label: 'Cup',
            content: '${appDocuments.path}/face.jpg',
            audioPath: '${appDocuments.path}/mummy.m4a',
          ),
        ],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Delete Cup'));
      await tester.pumpAndSettle();

      expect(
        find.text('Delete its picture and recording from this device'),
        findsOneWidget,
      );
    });

    testWidgets('a bundled symbol is offered no box, having no file', (
      tester,
    ) async {
      installMocks(
        storedCards: [
          storedCard(
            id: 'a',
            label: 'Cup',
            kind: CardMediaKind.asset,
            content: 'assets/symbols/water.svg',
          ),
        ],
      );
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Delete Cup'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await savedOrder(), isEmpty);
    });
  });

  group('restoring a backup', () {
    Future<void> openRestore(WidgetTester tester) async {
      await pumpApp(tester);
      await enterParentMode(tester);
      await tester.tap(find.byTooltip('Settings and backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore Data'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers to delete the old files, ticked by default', (
      tester,
    ) async {
      installMocks(storedCards: oneCard());
      await openRestore(tester);

      // The replaced board's photos stayed on the device with nothing to
      // reach them.
      expect(
        find.text(
          "Delete the replaced cards' pictures and recordings from this "
          'device',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
    });

    testWidgets('a board of bundled symbols is offered no box', (tester) async {
      installMocks(
        storedCards: [
          storedCard(
            id: 'a',
            label: 'Cup',
            kind: CardMediaKind.asset,
            content: 'assets/symbols/water.svg',
          ),
        ],
      );
      await openRestore(tester);

      expect(find.text('Restore a backup?'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    });
  });
}
