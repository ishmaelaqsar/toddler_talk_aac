import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to inject mock data into SharedPreferences
  Future<void> setMockData(List<Map<String, dynamic>> cards) async {
    SharedPreferences.setMockInitialValues({
      'toddler_cards': json.encode(cards),
    });
  }

  setUp(() {
    // Reset SharedPreferences mock
    SharedPreferences.setMockInitialValues({});

    // Mock Path Provider
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async => ".",
        );

    // Mock TTS
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (MethodCall methodCall) async => 1,
        );

    // Mock Share Plus
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (MethodCall methodCall) async => null,
        );
  });

  testWidgets('Core App starts safely', (WidgetTester tester) async {
    await tester.pumpWidget(const ToddlerTalkApp());
    expect(find.text("Hungry"), findsOneWidget); // Core word exists
    expect(find.byIcon(Icons.add_a_photo), findsNothing); // Add button hidden
  });

  testWidgets(
    'Hidden cards are invisible in Toddler Mode but visible in Mom Mode',
    (WidgetTester tester) async {
      // 1. Setup Data: One Visible card, One Hidden card
      await setMockData([
        {
          "id": "1",
          "label": "Visible Toy",
          "imagePath": "test.jpg",
          "isVisible": true,
        },
        {
          "id": "2",
          "label": "Hidden Toy",
          "imagePath": "test.jpg",
          "isVisible": false,
        },
      ]);

      await tester.pumpWidget(const ToddlerTalkApp());
      await tester.pumpAndSettle(); // Wait for data to load

      // 2. Verify Toddler Mode
      // We scroll just in case "Visible Toy" is off-screen
      await tester.scrollUntilVisible(
        find.text("Visible Toy"),
        500.0,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text("Visible Toy"), findsOneWidget);

      // "Hidden Toy" should NOT be found, even if we try to scroll to it
      // (We can't easily scroll to something that doesn't exist, so we check existence first)
      expect(find.text("Hidden Toy"), findsNothing);

      // 3. Switch to Mom Mode
      final lockIcon = find.byIcon(Icons.lock);
      await tester.longPress(lockIcon);
      await tester.pumpAndSettle(); // Allow UI to rebuild

      // 4. Verify Mom Mode (Both should show)
      // "Hidden Toy" is likely at the bottom, so we MUST scroll to find it
      await tester.scrollUntilVisible(
        find.text("Hidden Toy"),
        500.0, // Scroll down up to 500 pixels
        scrollable: find.byType(Scrollable),
      );

      expect(find.text("Visible Toy"), findsOneWidget);
      expect(find.text("Hidden Toy"), findsOneWidget);

      // 5. Verify Visibility Toggle Button exists
      // (This button is on the Custom Card, so finding the card finds the button)
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    },
  );
}
