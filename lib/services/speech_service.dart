import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/talk_card.dart';

/// What came out of the speaker when a card was tapped.
enum SpeechOutcome {
  /// Text-to-speech said the label.
  spoken,

  /// A parent's own recording played.
  played,

  /// The recording file was gone, so the label was spoken instead.
  recordingMissing,

  /// The recording would not play, so the label was spoken instead.
  recordingFailed,

  /// Nothing came out. Text-to-speech is not working on this device.
  unavailable,
}

/// Speaks a card, either through text-to-speech or through the recording a
/// parent made for it.
class SpeechService {
  SpeechService({FlutterTts? tts, AudioPlayer? player})
    : _tts = tts ?? FlutterTts(),
      _injectedPlayer = player;

  final FlutterTts _tts;
  final AudioPlayer? _injectedPlayer;

  /// Built on first use. Most boards have no recordings at all, so a player is
  /// not worth creating, or stopping, until one is played.
  AudioPlayer? _player;

  AudioPlayer get _audio => _player ??= _injectedPlayer ?? AudioPlayer();

  bool _ready = false;

  /// False once [init] has found that text-to-speech does not answer, so the
  /// board can tell the parent instead of failing silently.
  bool get isAvailable => _ready;

  Future<void> init() async {
    try {
      await _tts.setLanguage('en-US');
      // Slow, because a toddler is learning the word, not just hearing it.
      await _tts.setSpeechRate(0.5);
      _ready = true;
    } on Object {
      _ready = false;
    }
  }

  /// Plays [card] and reports what happened.
  ///
  /// Stops whatever is playing first, so a fast run of taps replaces the sound
  /// each time rather than queueing a backlog the child never asked for.
  Future<SpeechOutcome> speakCard(TalkCard card) async {
    final String? recording = card.audioPath;
    if (recording != null) {
      if (!File(recording).existsSync()) {
        await _speak(card.label);
        return _ready
            ? SpeechOutcome.recordingMissing
            : SpeechOutcome.unavailable;
      }
      try {
        await stop();
        await _audio.play(DeviceFileSource(recording));
        return SpeechOutcome.played;
      } on Object {
        // A file that will not decode must not leave the child in silence.
        await _speak(card.label);
        return _ready
            ? SpeechOutcome.recordingFailed
            : SpeechOutcome.unavailable;
      }
    }

    await _speak(card.label);
    return _ready ? SpeechOutcome.spoken : SpeechOutcome.unavailable;
  }

  /// Speaks a short piece of app feedback, such as entering parent mode.
  Future<void> announce(String text) => _speak(text);

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    await stop();
    try {
      await _tts.speak(text);
    } on Object {
      _ready = false;
    }
  }

  /// Silences both outputs.
  ///
  /// Each failure is swallowed on purpose. A stop that fails leaves nothing for
  /// a parent to act on, and letting it throw used to swallow the speech that
  /// was meant to follow it.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Nothing was speaking.
    }
    final AudioPlayer? player = _player;
    if (player == null) return;
    try {
      await player.stop();
    } on Object {
      // Nothing was playing.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player?.dispose();
  }
}
