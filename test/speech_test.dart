import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/models/talk_card.dart';

import 'test_harness.dart';

/// Speech was fired without stopping what was already playing, so a run of
/// taps queued a backlog. A missing recording failed silently. A tap before
/// start-up ended spoke, but told the parent that the device could not speak.
/// A card could only say its own label. Nothing showed which card spoke.
void main() {
  const String noSpeechWarning =
      'This device cannot speak. Check its text-to-speech settings.';

  List<String> spokenWords() => ttsCalls
      .where((c) => c.method == 'speak')
      .map((c) => c.arguments.toString())
      .toList();

  /// Replaces the text-to-speech mock with [handler], after the call log.
  void answerSpeech(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) {
          ttsCalls.add(call);
          return handler(call);
        });
  }

  testWidgets('a tap before start-up ends speaks, and warns of nothing', (
    tester,
  ) async {
    installMocks(
      storedCards: [storedCard(id: 'a', label: 'Cup')],
    );
    // Start-up stops at the language call until the end of the test.
    final Completer<Object?> language = Completer<Object?>();
    answerSpeech(
      (call) async => call.method == 'setLanguage' ? language.future : 1,
    );
    await pumpApp(tester);

    await tester.tap(find.text('Cup'));
    await tester.pumpAndSettle();

    expect(spokenWords(), ['Cup']);
    expect(find.text(noSpeechWarning), findsNothing);

    language.complete(1);
    await tester.pumpAndSettle();
  });

  testWidgets('a voice that fails to speak warns the parent once', (
    tester,
  ) async {
    installMocks(
      storedCards: [storedCard(id: 'a', label: 'Cup')],
    );
    answerSpeech((call) async {
      if (call.method == 'speak') throw PlatformException(code: 'no_engine');
      return 1;
    });
    await pumpApp(tester);

    await tester.tap(find.text('Cup'));
    await tester.pumpAndSettle();
    expect(find.text(noSpeechWarning), findsOneWidget);

    // A toddler taps fast. The second failure must not queue a second warning
    // behind the first.
    await tester.tap(find.text('Cup'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(noSpeechWarning), findsNothing);
  });

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

  testWidgets('a card with speech text speaks it, not the label', (
    tester,
  ) async {
    installMocks(
      storedCards: [
        storedCard(id: 'a', label: 'Milk', speech: 'I want milk, please'),
      ],
    );
    await pumpApp(tester);

    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();

    expect(spokenWords(), ['I want milk, please']);
  });

  testWidgets('a recording wins over the speech text', (tester) async {
    final Directory dir = Directory.systemTemp.createTempSync('tt_speech');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File recording = File('${dir.path}/mummy.m4a')
      ..writeAsBytesSync(const [0, 1, 2]);

    installMocks(
      storedCards: [
        storedCard(
          id: 'a',
          label: 'Mummy',
          speech: 'Where is Mummy?',
          audioPath: recording.path,
        ),
      ],
    );
    await pumpApp(tester);

    await tester.tap(find.text('Mummy'));
    await tester.pumpAndSettle();

    // The test that reaches for the file proves the route to the player. A
    // second test in one file never sees the player start, because
    // audioplayers keeps its start-up future from the first test, in a test
    // zone that has ended.
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

  group('the speaking ring', () {
    List<Map<String, dynamic>> twoCards() => [
      storedCard(id: 'a', label: 'Cup'),
      storedCard(id: 'b', label: 'Ball'),
    ];

    /// Sends [method] from the speech engine to the app, as the plugin does.
    Future<void> fromSpeechEngine(WidgetTester tester, String method) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter_tts',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );
      await tester.pump();
    }

    testWidgets('a tap puts it on that card', (tester) async {
      installMocks(storedCards: twoCards());
      await pumpApp(tester);

      await tester.tap(find.text('Cup'));
      await tester.pumpAndSettle();

      expect(speakingRingOn(tester, 'Cup'), isTrue);
      expect(speakingRingOn(tester, 'Ball'), isFalse);
    });

    testWidgets('the end of the word clears it', (tester) async {
      installMocks(storedCards: twoCards());
      await pumpApp(tester);
      await tester.tap(find.text('Cup'));
      await tester.pumpAndSettle();

      await fromSpeechEngine(tester, 'speak.onComplete');

      expect(speakingRingOn(tester, 'Cup'), isFalse);
    });

    testWidgets('an error from the speech engine clears it', (tester) async {
      installMocks(storedCards: twoCards());
      await pumpApp(tester);
      await tester.tap(find.text('Cup'));
      await tester.pumpAndSettle();

      await fromSpeechEngine(tester, 'speak.onError');

      expect(speakingRingOn(tester, 'Cup'), isFalse);
    });

    testWidgets('a tap on a second card moves it', (tester) async {
      installMocks(storedCards: twoCards());
      await pumpApp(tester);

      await tester.tap(find.text('Cup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ball'));
      await tester.pumpAndSettle();

      expect(speakingRingOn(tester, 'Cup'), isFalse);
      expect(speakingRingOn(tester, 'Ball'), isTrue);
    });

    // The engine cancels the first word when the second card stops it, and
    // the cancel arrives after the second card has its ring.
    testWidgets('a late cancel of the first word leaves the new ring', (
      tester,
    ) async {
      installMocks(storedCards: twoCards());
      await pumpApp(tester);
      await tester.tap(find.text('Cup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ball'));
      await tester.pumpAndSettle();

      await fromSpeechEngine(tester, 'speak.onCancel');

      expect(speakingRingOn(tester, 'Ball'), isTrue);
    });

    testWidgets('entering parent mode clears it', (tester) async {
      installMocks(storedCards: twoCards());
      await pumpApp(tester);
      await tester.tap(find.text('Cup'));
      await tester.pumpAndSettle();

      await enterParentMode(tester);

      expect(speakingRingOn(tester, 'Cup'), isFalse);
    });
  });
}
