import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock standard dependencies
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => ".",
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (MethodCall methodCall) async => 1,
    );

    // Mock new dependencies to prevent crash
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (MethodCall methodCall) async => null,
    );
  });

  testWidgets('App starts in Toddler Mode (Safe Mode)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ToddlerTalkApp());
    expect(find.byIcon(Icons.add_a_photo), findsNothing);
    expect(find.text("Hungry"), findsOneWidget);
  });

  testWidgets('Long Press unlocks Mom Mode and Settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ToddlerTalkApp());

    final lockIcon = find.byIcon(Icons.lock);

    // Unlock
    await tester.longPress(lockIcon);
    await tester.pump();

    // Check for "Mom Mode" UI
    expect(find.text("Mom Mode"), findsOneWidget);
    expect(find.byIcon(Icons.add_a_photo), findsOneWidget);

    // Check for Settings Icon (Backup/Restore menu)
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
