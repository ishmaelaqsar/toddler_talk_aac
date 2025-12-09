import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_voice_aac/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock Database (SharedPreferences)
    SharedPreferences.setMockInitialValues({});

    // Mock File System (path_provider)
    const MethodChannel channelPath = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    channelPath.setMockMethodCallHandler((MethodCall methodCall) async => ".");

    // Mock Text-to-Speech (flutter_tts)
    const MethodChannel channelTTS = MethodChannel('flutter_tts');
    channelTTS.setMockMethodCallHandler((MethodCall methodCall) async => 1);
  });

  testWidgets('App loads and Core Vocabulary is visible', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyVoiceApp());

    expect(find.text('My Voice'), findsOneWidget);
    expect(find.text('I'), findsOneWidget);
    expect(find.text('Want'), findsOneWidget);
  });

  testWidgets('Tapping a card adds it to the Sentence Strip', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyVoiceApp());

    // Tap "Want"
    await tester.tap(find.text('Want'));
    await tester.pump();

    // Identify the "Go" button
    final goButton = find.text('Go');

    // Scroll until "Go" is visible, targeting the GridView (the last scrollable widget)
    await tester.scrollUntilVisible(
      goButton,
      500.0,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    // Tap "Go"
    await tester.tap(goButton);
    await tester.pump();

    // Verify both are now in the Sentence Strip (Grid copy + Strip copy = 2)
    expect(find.text('Want'), findsNWidgets(2));
    expect(find.text('Go'), findsNWidgets(2));
  });

  testWidgets('Delete button only appears in Edit Mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyVoiceApp());

    // Ensure delete icon is NOT there initially
    expect(find.byIcon(Icons.delete), findsNothing);

    // Enter Edit Mode
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();

    // Verify toggle changed
    expect(find.byIcon(Icons.edit_off), findsOneWidget);
  });
}
