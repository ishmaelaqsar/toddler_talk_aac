import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/models/talk_card.dart';

import 'test_harness.dart';

/// Speech was fired without stopping what was already playing, so a run of
/// taps queued a backlog. A missing recording failed silently.
void main() {
  List<String> spokenWords() => ttsCalls
      .where((c) => c.method == 'speak')
      .map((c) => c.arguments.toString())
      .toList();

  testWidgets('tapping a card speaks its label', (tester) async {
    installMocks(
      storedCards: [storedCard(id: 'a', label: 'Cup')],
    );
    await pumpApp(tester);

    await tester.tap(find.text('Cup'));
    await tester.pumpAndSettle();

    expect(spokenWords(), contains('Cup'));
  });

  testWidgets('a second tap stops the first before speaking again', (
    tester,
  ) async {
    installMocks(
      storedCards: [
        storedCard(id: 'a', label: 'Cup'),
        storedCard(id: 'b', label: 'Ball'),
      ],
    );
    await pumpApp(tester);

    await tester.tap(find.text('Cup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ball'));
    await tester.pumpAndSettle();

    final List<String> methods = ttsCalls.map((c) => c.method).toList();
    final int secondSpeak = methods.lastIndexOf('speak');
    expect(methods.lastIndexOf('stop'), lessThan(secondSpeak));
    expect(spokenWords(), ['Cup', 'Ball']);
  });

  // A widget test has no audio platform, so the recording cannot really play.
  // What it can prove is the routing: the recording is what the app reaches for
  // in place of text-to-speech. The fallback when a file is gone is covered
  // below; the fallback when a present file will not decode needs a device.
  testWidgets('a card with a recording reaches for the file, not the robot '
      'voice', (tester) async {
    final Directory dir = Directory.systemTemp.createTempSync('tt_speech');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File recording = File('${dir.path}/mummy.m4a')
      ..writeAsBytesSync(const [0, 1, 2]);

    installMocks(
      storedCards: [
        storedCard(id: 'a', label: 'Mummy', audioPath: recording.path),
      ],
    );
    await pumpApp(tester);

    await tester.tap(find.text('Mummy'));
    await tester.pumpAndSettle();

    expect(
      audioCalls.map((MethodCall c) => c.arguments.toString()).join(' '),
      contains(recording.path),
    );
    // The robot voice stays out of it while the recording has the floor.
    expect(spokenWords(), isEmpty);
  });

  testWidgets('a card with no recording never touches the audio player', (
    tester,
  ) async {
    installMocks(
      storedCards: [storedCard(id: 'a', label: 'Cup')],
    );
    await pumpApp(tester);

    await tester.tap(find.text('Cup'));
    await tester.pumpAndSettle();

    expect(audioCalls, isEmpty);
  });

  testWidgets('a missing recording falls back to the robot voice', (
    tester,
  ) async {
    installMocks(
      storedCards: [
        storedCard(id: 'a', label: 'Mummy', audioPath: '/nowhere/gone.m4a'),
      ],
    );
    await pumpApp(tester);

    await tester.tap(find.text('Mummy'));
    await tester.pumpAndSettle();

    expect(spokenWords(), contains('Mummy'));
    expect(
      find.text('That recording is missing, so the robot voice read the word.'),
      findsOneWidget,
    );
  });

  testWidgets('entering and leaving parent mode are both announced', (
    tester,
  ) async {
    installMocks(
      storedCards: [storedCard(id: 'a', label: 'Cup')],
    );
    await pumpApp(tester);

    await enterParentMode(tester);
    expect(spokenWords(), contains('Parent mode'));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(spokenWords(), contains('Editing locked'));
  });

  testWidgets('a card with no label speaks nothing', (tester) async {
    installMocks(
      storedCards: [
        storedCard(
          id: 'a',
          label: '',
          kind: CardMediaKind.emoji,
          content: '\u{1F36A}',
        ),
      ],
    );
    await pumpApp(tester);

    await tester.tap(find.text('\u{1F36A}'));
    await tester.pumpAndSettle();

    expect(spokenWords(), isEmpty);
  });
}
