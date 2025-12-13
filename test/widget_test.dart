import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    dotenv.loadFromString(envString: "GIPHY_API_KEY=test_key");
  });

  Future<void> setMockData(List<Map<String, dynamic>> cards) async {
    SharedPreferences.setMockInitialValues({
      'toddler_cards_v5': json.encode(cards),
    });
  }

  setUp(() {
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

    expect(find.text("Hungry"), findsOneWidget);
    // Ensure Admin controls are hidden
    expect(find.byIcon(Icons.add_circle), findsNothing);
    expect(
      find.byIcon(Icons.more_vert),
      findsNothing,
    ); // Backup menu should be hidden
  });

  testWidgets('Admin Mode reveals new Giphy and Library options', (
    WidgetTester tester,
  ) async {
    await setMockData([]);
    await tester.pumpWidget(const ToddlerTalkApp());
    await tester.pumpAndSettle();

    // Enter Mom Mode
    await tester.longPress(find.byIcon(Icons.lock));
    await tester.pumpAndSettle();

    // Tap "Add Card" button
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();

    expect(find.text("Giphy Search"), findsOneWidget);
    expect(find.text("Symbol Library"), findsOneWidget);
  });

  testWidgets('Admin Mode reveals Backup/Restore menu', (
    WidgetTester tester,
  ) async {
    await setMockData([]);
    await tester.pumpWidget(const ToddlerTalkApp());
    await tester.pumpAndSettle();

    // 1. Enter Mom Mode
    await tester.longPress(find.byIcon(Icons.lock));
    await tester.pumpAndSettle();

    // 2. Verify Menu Icon (Three dots) exists
    final menuButton = find.byIcon(Icons.more_vert);
    expect(menuButton, findsOneWidget);

    // 3. Open the menu
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    // 4. Verify Options exist
    expect(find.text("Backup Data"), findsOneWidget);
    expect(find.text("Restore Data"), findsOneWidget);
  });
}
