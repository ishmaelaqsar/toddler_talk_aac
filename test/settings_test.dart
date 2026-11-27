import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toddler_talk_aac/data/card_repository.dart';
import 'package:toddler_talk_aac/models/board_settings.dart';
import 'package:toddler_talk_aac/theme.dart';
import 'package:toddler_talk_aac/widgets/card_tile.dart';

import 'test_harness.dart';

/// The voice was American English at one fixed speed, and every card had one
/// fixed size. A parent could change neither.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Map<String, dynamic>> oneCard() => [storedCard(id: 'a', label: 'Cup')];

  /// The values text-to-speech received for [method], in order.
  List<Object?> sent(String method) => ttsCalls
      .where((c) => c.method == method)
      .map((c) => c.arguments)
      .toList();

  group('BoardSettings', () {
    test('a round trip keeps every setting', () {
      const BoardSettings settings = BoardSettings(
        voice: SpeechVoice.american,
        slow: true,
        cardSize: CardSize.large,
      );

      final BoardSettings restored = BoardSettings.fromJson(settings.toJson());

      expect(restored.voice, SpeechVoice.american);
      expect(restored.slow, isTrue);
      expect(restored.cardSize, CardSize.large);
    });

    test('a missing field takes its default', () {
      final BoardSettings settings = BoardSettings.fromJson({});

      expect(settings.voice, SpeechVoice.british);
      expect(settings.slow, isFalse);
      expect(settings.cardSize, CardSize.medium);
    });

    test('an unknown value takes its default', () {
      final BoardSettings settings = BoardSettings.fromJson({
        'voice': 'fr-FR',
        'slow': 'yes',
        'cardSize': 'huge',
      });

      expect(settings.voice, SpeechVoice.british);
      expect(settings.slow, isFalse);
      expect(settings.cardSize, CardSize.medium);
    });

    test('stored settings that cannot be read load as the defaults', () async {
      SharedPreferences.setMockInitialValues({
        CardRepository.settingsKey: 'not json',
      });

      final BoardSettings settings = await CardRepository().loadSettings();

      expect(settings.cardSize, CardSize.medium);
    });
  });

  group('the settings sheet', () {
    testWidgets('the voice starts British, at the normal speed', (
      tester,
    ) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);

      expect(sent('setLanguage'), ['en-GB']);
      expect(sent('setSpeechRate'), [0.5]);
    });

    testWidgets('a change to the voice or the speed applies at once', (
      tester,
    ) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      await openSettings(tester);

      await tester.tap(find.text('American'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Slow'));
      await tester.pumpAndSettle();

      expect(sent('setLanguage').last, 'en-US');
      expect(sent('setSpeechRate').last, 0.35);
    });

    testWidgets('the grid follows the card size', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      final double medium = tester.getSize(find.byType(CardTile)).width;

      await openSettings(tester);
      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(CardTile)).width, greaterThan(medium));
    });

    testWidgets('Hear it speaks a sample', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      await openSettings(tester);
      ttsCalls.clear();

      await tester.tap(find.text('Hear it'));
      await tester.pumpAndSettle();

      expect(sent('speak'), hasLength(1));
    });

    testWidgets('a setting survives a restart', (tester) async {
      installMocks(storedCards: oneCard());
      await pumpApp(tester);
      await enterParentMode(tester);
      await openSettings(tester);
      await tester.tap(find.text('Slow'));
      await tester.pumpAndSettle();

      // A fresh app on the same storage.
      await tester.pumpWidget(const SizedBox.shrink());
      ttsCalls.clear();
      await pumpApp(tester);

      expect(sent('setSpeechRate'), [0.35]);
    });
  });
}
