import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_harness.dart';

/// Nothing showed which card spoke. A recording has its own end signal, apart
/// from the robot voice.
///
/// The only player test in its file: audioplayers keeps its start-up future
/// from the first test, so a second player test never sees a player start.
void main() {
  testWidgets('the ring clears when the recording ends', (tester) async {
    final Directory dir = Directory.systemTemp.createTempSync('tt_ring');
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
    expect(speakingRingOn(tester, 'Mummy'), isTrue);

    final MethodCall create = audioCalls.firstWhere(
      (c) => c.method == 'create',
    );
    final String playerId = (create.arguments as Map)['playerId'] as String;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'xyz.luan/audioplayers/events/$playerId',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'event': 'audio.onComplete',
      }),
      (_) {},
    );
    // The event reaches the player only on a turn of the real event loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(speakingRingOn(tester, 'Mummy'), isFalse);
  });
}
