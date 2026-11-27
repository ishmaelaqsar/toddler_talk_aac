import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toddler_talk_aac/data/card_repository.dart';
import 'package:toddler_talk_aac/main.dart';
import 'package:toddler_talk_aac/models/board_page.dart';
import 'package:toddler_talk_aac/models/talk_card.dart';
import 'package:toddler_talk_aac/theme.dart';
import 'package:toddler_talk_aac/widgets/card_tile.dart';
import 'package:toddler_talk_aac/widgets/page_tabs.dart';
import 'package:toddler_talk_aac/widgets/parent_lock.dart';

/// Every text-to-speech call the app made during a test, in order.
final List<MethodCall> ttsCalls = [];

/// Every audio-playback call the app made during a test, in order.
final List<MethodCall> audioCalls = [];

/// Every recorder call the app made during a test, in order.
final List<MethodCall> recorderCalls = [];

/// Every system call the app made during a test, in order: the system bars,
/// and a Back press that leaves the app.
final List<MethodCall> platformCalls = [];

Directory? _appDocuments;

/// Where the app thinks its own files live, for the current test.
///
/// The app only deletes a file inside this directory, so a test that checks
/// deletion has to write its fixture here. Stable for the whole test, so a
/// test can call [installMocks] once to learn the path and again with the
/// cards it built from it.
Directory get appDocuments => _appDocuments!;

/// The prefix `shared_preferences` puts on a key in its mock store.
const String _prefsPrefix = 'flutter.';

/// Installs the plugin mocks the app needs to boot in a test.
///
/// Pass [storedCards] to start from a saved board. Pass nothing to get the
/// first-run defaults. Pass [storedSettings] or [storedPages] to start from
/// saved settings or saved pages. Pass [rawStoredCards] in place of
/// [storedCards] to store text that is not a board.
void installMocks({
  List<Map<String, dynamic>>? storedCards,
  String? rawStoredCards,
  Map<String, dynamic>? storedSettings,
  List<Map<String, dynamic>>? storedPages,
}) {
  ttsCalls.clear();
  audioCalls.clear();
  recorderCalls.clear();
  platformCalls.clear();

  SharedPreferences.setMockInitialValues({
    if (storedCards != null || rawStoredCards != null)
      '$_prefsPrefix${CardRepository.storageKey}':
          rawStoredCards ?? json.encode(storedCards),
    if (storedSettings != null)
      '$_prefsPrefix${CardRepository.settingsKey}': json.encode(storedSettings),
    if (storedPages != null)
      '$_prefsPrefix${CardRepository.pagesKey}': json.encode(storedPages),
  });

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // A directory of its own per test. Pointing this at '.' let a recording the
  // app wrote land in the repository.
  final Directory documents = _appDocuments ??= Directory.systemTemp
      .createTempSync('tt_app');
  addTearDown(() {
    if (documents.existsSync()) documents.deleteSync(recursive: true);
    _appDocuments = null;
  });
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => documents.path,
  );

  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    platformCalls.add(call);
    return null;
  });

  messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
    call,
  ) async {
    ttsCalls.add(call);
    return 1;
  });

  for (final String channel in [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
      audioCalls.add(call);
      // Each player listens to an event channel of its own, as on a device.
      // Unanswered, the listen fails as soon as the test gives real time.
      if (call.method == 'create') {
        final Object? id = (call.arguments as Map)['playerId'];
        messenger.setMockMethodCallHandler(
          MethodChannel('xyz.luan/audioplayers/events/$id'),
          (_) async => null,
        );
      }
      return null;
    });
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global/events'),
    (_) async => null,
  );

  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async {
      // 1 = granted. Granted for whichever permission is asked for, rather
      // than for one hardcoded index.
      if (call.method == 'requestPermissions') {
        final List<Object?> asked = (call.arguments as List<Object?>);
        return <Object?, int>{for (final Object? p in asked) p: 1};
      }
      return 1;
    },
  );

  // Stands in for the recorder: `start` writes the file the plugin would have
  // written, and `stop` hands back its path.
  String? recordingPath;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (call) async {
      recorderCalls.add(call);
      final Object? args = call.arguments;
      switch (call.method) {
        case 'start':
          recordingPath = args is Map ? args['path'] as String? : null;
          final String? path = recordingPath;
          if (path != null) File(path).writeAsBytesSync(const [0, 1, 2]);
          return null;
        case 'stop':
          return recordingPath;
        default:
          return null;
      }
    },
  );
}

/// Pumps the app at a chosen viewport and text scale.
Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(800, 1280),
  double textScale = 1.0,
  String giphyApiKey = '',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Set the scale on the dispatcher, not in a MediaQuery above the app.
  // MaterialApp installs MediaQuery.fromView itself, which would overwrite it.
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(ToddlerTalkApp(giphyApiKey: giphyApiKey));
  await tester.pumpAndSettle();
}

/// A stored card in the shape the app itself writes.
Map<String, dynamic> storedCard({
  required String id,
  required String label,
  CardMediaKind kind = CardMediaKind.file,
  String content = 'missing.jpg',
  String? audioPath,
  String? speech,
  String? pageId,
  bool isVisible = true,
}) => TalkCard(
  id: id,
  label: label,
  kind: kind,
  content: content,
  audioPath: audioPath,
  speech: speech,
  pageId: pageId,
  isVisible: isVisible,
).toJson();

/// A stored page in the shape the app itself writes.
Map<String, dynamic> storedPage(String id, String name, {String? symbol}) =>
    BoardPage(id: id, name: name, symbol: symbol).toJson();

/// Enters parent mode the way a parent does: the hold, then the gate.
Future<void> enterParentMode(WidgetTester tester) async {
  await holdLock(tester);
  await solveParentGate(tester);
}

/// Holds the lock until the parent gate opens.
///
/// [WidgetTester.longPress] is too short: the lock asks for a deliberate
/// [AppTokens.unlockHold] hold.
Future<void> holdLock(WidgetTester tester) async {
  final TestGesture hold = await tester.startGesture(
    tester.getCenter(find.byType(ParentLock)),
  );
  // Two frames before the clock is advanced: one to deliver the press, one for
  // the hold's ticker to record its start.
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(Duration.zero);
  await tester.pump(AppTokens.unlockHold + const Duration(milliseconds: 50));
  await hold.up();
  await tester.pumpAndSettle();
}

const List<String> _digitWords = [
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
];

/// The digits the open parent gate asks for, read from its prompt.
List<int> gateCode(WidgetTester tester) {
  final String prompt = tester
      .widget<Text>(find.textContaining(RegExp(r'^Tap ')))
      .data!;
  return [
    for (final String word in prompt.substring('Tap '.length).split(', '))
      _digitWords.indexOf(word) + 1,
  ];
}

/// The key for [digit] on the open parent gate.
Finder gateKey(int digit) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.text('$digit'),
);

/// Taps [digit] on the open parent gate. A key can sit below the fold on a
/// small screen, so it is scrolled into view first.
Future<void> tapGateKey(WidgetTester tester, int digit) async {
  await tester.ensureVisible(gateKey(digit));
  await tester.pumpAndSettle();
  await tester.tap(gateKey(digit));
  await tester.pumpAndSettle();
}

/// Taps the digits the open parent gate asks for, in order.
Future<void> solveParentGate(WidgetTester tester) async {
  for (final int digit in gateCode(tester)) {
    await tapGateKey(tester, digit);
  }
}

/// Drags the card labelled [label] one place to the right, holding first so a
/// reorderable grid picks the drag up.
Future<void> dragCardRight(WidgetTester tester, String label) async {
  final TestGesture drag = await tester.startGesture(
    tester.getCenter(find.text(label)),
  );
  await tester.pump(const Duration(milliseconds: 800));
  await drag.moveBy(const Offset(40, 0));
  await tester.pump(const Duration(milliseconds: 100));
  await drag.moveBy(const Offset(200, 0));
  await tester.pumpAndSettle();
  await drag.up();
  await tester.pumpAndSettle();
}

/// The saved board, in saved order.
Future<List<TalkCard>> savedCards() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String? raw = prefs.getString(CardRepository.storageKey);
  if (raw == null) return [];
  return CardRepository().decode(raw);
}

/// The labels of the saved board, in saved order.
Future<List<String>> savedOrder() async =>
    (await savedCards()).map((c) => c.label).toList();

/// Opens the settings sheet from the menu. Parent mode must be open.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings and backup'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

/// Opens the pages sheet from the menu. Parent mode must be open.
Future<void> openPages(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings and backup'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pages'));
  await tester.pumpAndSettle();
}

/// Whether the card labelled [label] wears the speaking ring.
bool speakingRingOn(WidgetTester tester, String label) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.widgetWithText(CardTile, label),
        matching: find.byType(DecoratedBox),
      ),
    )
    .any(
      (box) =>
          box.decoration is BoxDecoration &&
          (box.decoration as BoxDecoration).border ==
              Border.all(
                color: AppTokens.speakingRing,
                width: AppTokens.speakingRingWidth,
              ),
    );

/// The tab named [name] in the page tab row.
Finder pageTab(String name) =>
    find.descendant(of: find.byType(PageTabs), matching: find.text(name));

/// Sends the app to the background and brings it back.
///
/// The states are walked in the order the framework requires. A paused binding
/// draws no frames, so the return leg is what lets the tree rebuild: on a
/// device too, a parent sees the locked board when they come back.
void backgroundAndReturn(WidgetTester tester) {
  for (final AppLifecycleState state in [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

/// Lets the app's fire-and-forget file work finish.
///
/// A widget test runs in fake async, so a real file delete never completes
/// inside [WidgetTester.pumpAndSettle]. This hands the run real time.
Future<void> settleFileWork(WidgetTester tester) async {
  // Several rounds, because a delete can sit behind other awaits: the app
  // saves the board first, and each hop needs the real event loop again.
  for (int i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }
}
