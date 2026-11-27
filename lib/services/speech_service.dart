import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/board_settings.dart';
import '../models/talk_card.dart';

/// What came out of the speaker when a card was tapped.
enum SpeechOutcome {
  /// Text-to-speech said the card's words.
  spoken,

  /// A parent's own recording played.
  played,

  /// The recording file was gone, so the card's words were spoken instead.
  recordingMissing,

  /// The recording would not play, so the card's words were spoken instead.
  recordingFailed,

  /// Nothing came out. Text-to-speech is not working on this device.
  unavailable,
}

/// Speaks a card, either through text-to-speech or through the recording a
/// parent made for it.
class SpeechService {
  SpeechService({FlutterTts? tts, AudioPlayer? player})
    : _tts = tts ?? FlutterTts(),
      _injectedPlayer = player {
    // Not on cancel: the cancel of a stopped word arrives after the next card
    // has set its id, and would clear the new ring.
    _tts.setCompletionHandler(() => _speaking.value = null);
    _tts.setErrorHandler((_) => _speaking.value = null);
  }

  final FlutterTts _tts;
  final AudioPlayer? _injectedPlayer;

  final ValueNotifier<String?> _speaking = ValueNotifier<String?>(null);

  /// The id of the card whose sound plays, or null.
  ValueListenable<String?> get speaking => _speaking;

  /// Built on first use. Most boards have no recordings at all, so a player is
  /// not worth creating, or stopping, until one is played.
  AudioPlayer? _player;

  AudioPlayer get _audio =>
      _player ??= (_injectedPlayer ?? AudioPlayer())
        ..onPlayerComplete.listen((_) => _speaking.value = null);

  /// The normal rate. The Android plugin doubles the value for the engine,
  /// where 1.0 is normal.
  static const double normalRate = 0.5;

  /// Slower than normal, for a child who is learning the word.
  static const double slowRate = 0.35;

  /// Sets the voice and the speed.
  Future<void> apply(BoardSettings settings) async {
    try {
      await _tts.setLanguage(settings.voice.language);
      await _tts.setSpeechRate(settings.slow ? slowRate : normalRate);
    } on Object {
      // The first tap tells the parent when the voice does not work.
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
        return await _speak(card.spokenText, card.id)
            ? SpeechOutcome.recordingMissing
            : SpeechOutcome.unavailable;
      }
      try {
        await stop();
        _speaking.value = card.id;
        await _audio.play(DeviceFileSource(recording));
        return SpeechOutcome.played;
      } on Object {
        // A file that will not decode must not leave the child in silence.
        return await _speak(card.spokenText, card.id)
            ? SpeechOutcome.recordingFailed
            : SpeechOutcome.unavailable;
      }
    }

    return await _speak(card.spokenText, card.id)
        ? SpeechOutcome.spoken
        : SpeechOutcome.unavailable;
  }

  /// Speaks a short piece of app feedback, such as entering parent mode. No
  /// card wears the ring while it plays.
  Future<void> announce(String text) => _speak(text, null);

  /// Returns false when text-to-speech throws on this call.
  ///
  /// The answer comes from this call alone. A tap before [apply] ends gets a
  /// true answer when it speaks. One failure does not mark later taps as
  /// failed. An empty [text] has nothing to say, which is not a failure.
  Future<bool> _speak(String text, String? cardId) async {
    if (text.isEmpty) return true;
    await stop();
    _speaking.value = cardId;
    try {
      await _tts.speak(text);
      return true;
    } on Object {
      _speaking.value = null;
      return false;
    }
  }

  /// Silences both outputs.
  ///
  /// Each failure is swallowed on purpose. A stop that fails leaves nothing for
  /// a parent to act on, and letting it throw used to swallow the speech that
  /// was meant to follow it.
  Future<void> stop() async {
    _speaking.value = null;
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
    _speaking.dispose();
  }
}
