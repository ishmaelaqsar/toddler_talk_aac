import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // REQUIRED IMPORT

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    dotenv.loadFromString(envString: "GIPHY_API_KEY=test_key");
  });

  // Helper to inject mock data into SharedPreferences
  Future<void> setMockData(List<Map<String, dynamic>> cards) async {
    SharedPreferences.setMockInitialValues({
      'toddler_cards_v5': json.encode(cards),
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

    // Mock Audio Players
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (MethodCall methodCall) async => null,
        );

    // Mock Permissions
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (MethodCall methodCall) async => {0: 1}, // 1 = granted
        );
  });

  testWidgets('Core App starts safely with defaults', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ToddlerTalkApp());
    await tester.pumpAndSettle();

    // Check for a default core word
    expect(find.text("Hungry"), findsOneWidget);

    // Ensure "Mom Mode" controls are HIDDEN by default
    expect(find.byIcon(Icons.add_circle), findsNothing);
    expect(find.byIcon(Icons.cancel), findsNothing);
  });

  testWidgets('Admin Mode reveals new Giphy and Library options', (
    WidgetTester tester,
  ) async {
    // 1. Setup Data
    await setMockData([]); // Start empty
    await tester.pumpWidget(const ToddlerTalkApp());
    await tester.pumpAndSettle();

    // 2. Enter Mom Mode
    final lockIcon = find.byIcon(Icons.lock);
    await tester.longPress(lockIcon);
    await tester.pumpAndSettle();

    // 3. Tap "Add Card" button
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();

    // 4. VERIFY NEW MENU OPTIONS
    // Check that our new features are visible in the dialog
    expect(find.text("Giphy Search"), findsOneWidget);
    expect(find.text("Symbol Library"), findsOneWidget);
    expect(find.byIcon(Icons.gif_box), findsOneWidget);
  });

  testWidgets('Admin Mode toggle reveals editing tools', (
    WidgetTester tester,
  ) async {
    await setMockData([
      {
        "id": "1",
        "label": "Test Toy",
        "color": 0xFFFFFFFF,
        "type": "emoji",
        "content": "🧸",
        "audioPath": null,
        "isVisible": true,
      },
    ]);

    await tester.pumpWidget(const ToddlerTalkApp());
    await tester.pumpAndSettle();

    // Verify Toddler Mode (Default)
    expect(find.text("Test Toy"), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsNothing);

    // Switch to Mom Mode
    await tester.longPress(find.byIcon(Icons.lock));
    await tester.pumpAndSettle();

    // Verify Mom Mode Indicators
    expect(find.text("Mom Mode (Edit)"), findsOneWidget);
    expect(find.byIcon(Icons.add_circle), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
  });
}
