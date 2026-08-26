import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../data/card_repository.dart';
import '../models/talk_card.dart';
import '../theme.dart';
import 'card_media.dart';

/// A picture the parent chose for a card.
class CardMediaSelection {
  const CardMediaSelection({
    required this.kind,
    required this.content,
    this.suggestedLabel,
  });

  final CardMediaKind kind;
  final String content;

  /// A label the source already knows, such as a symbol's name.
  final String? suggestedLabel;
}

/// Asks the caller to run the picture-picking flow again.
typedef MediaChooser = Future<CardMediaSelection?> Function();

/// Opens the card editor. Returns the edited card, or null when the parent
/// cancels.
///
/// The same dialog creates a card and edits one, so renaming, re-recording, or
/// swapping a picture no longer needs delete-and-add.
Future<TalkCard?> showCardEditor(
  BuildContext context, {
  required TalkCard card,
  required CardRepository repository,
  MediaChooser? onChangeMedia,
}) => showDialog<TalkCard>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _CardEditorDialog(
    card: card,
    repository: repository,
    onChangeMedia: onChangeMedia,
  ),
);

class _CardEditorDialog extends StatefulWidget {
  const _CardEditorDialog({
    required this.card,
    required this.repository,
    this.onChangeMedia,
  });

  final TalkCard card;
  final CardRepository repository;
  final MediaChooser? onChangeMedia;

  @override
  State<_CardEditorDialog> createState() => _CardEditorDialogState();
}

class _CardEditorDialogState extends State<_CardEditorDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  late final TextEditingController _label = TextEditingController(
    text: widget.card.label,
  );

  late TalkCard _draft = widget.card;
  bool _isRecording = false;
  bool _isPlaying = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  /// Recordings this dialog created. An abandoned take is deleted on the way
  /// out, so it does not sit on the device forever.
  ///
  /// Only takes made here. The recording the card arrived with is never
  /// deleted: the card still points at it if the parent cancels.
  final Set<String> _takes = {};

  /// The recording the card arrived with, if any.
  late final String? _arrived = widget.card.audioPath;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    _player.dispose();
    _label.dispose();
    super.dispose();
  }

  bool get _canSave => _label.text.trim().isNotEmpty;

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final String? path = await _recorder.stop();
      _ticker?.cancel();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        if (path != null) {
          _takes.add(path);
          _draft = _draft.copyWith(audioPath: path);
        }
      });
      return;
    }

    if (!await Permission.microphone.request().isGranted) {
      if (mounted) _tell('Toddler Talk needs the microphone to record.');
      return;
    }

    final String path = await widget.repository.newRecordingPath();
    try {
      await _recorder.start(const RecordConfig(), path: path);
    } on Object {
      if (mounted) _tell('Recording could not start on this device.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _togglePlayback() async {
    final String? path = _draft.audioPath;
    if (path == null) return;

    if (_isPlaying) {
      await _player.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    await _player.play(DeviceFileSource(path));
    if (mounted) setState(() => _isPlaying = true);
  }

  void _removeRecording() {
    setState(() {
      _draft = _draft.copyWith(clearAudio: true);
      _isPlaying = false;
    });
  }

  Future<void> _changeMedia() async {
    final MediaChooser? chooser = widget.onChangeMedia;
    if (chooser == null) return;

    final CardMediaSelection? picked = await chooser();
    if (picked == null || !mounted) return;
    setState(() {
      _draft = _draft.copyWith(kind: picked.kind, content: picked.content);
    });
  }

  /// Drops every take made here. The card keeps the recording it arrived with.
  void _discardTakes() => _release(_takes);

  /// Drops the recordings the saved card no longer uses.
  ///
  /// That includes the one it arrived with, when the parent has replaced or
  /// removed it: keeping it would leave a file on the device that nothing
  /// points at any more.
  void _keepOnly(String? kept) =>
      _release({..._takes, ?_arrived}..remove(kept));

  void _release(Iterable<String> paths) {
    for (final String path in paths) {
      // Fire and forget, and only if the app wrote it: the dialog is closing.
      widget.repository.deleteOwnedFile(path).ignore();
    }
  }

  void _tell(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Card details'),
      // Scrolls, so the dialog holds up on a short screen and at a large text
      // scale.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _preview(),
            const SizedBox(height: AppTokens.gap),
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'What the card says',
                border: const OutlineInputBorder(),
                errorText: _canSave ? null : 'A card needs a word',
              ),
            ),
            const SizedBox(height: AppTokens.gap),
            _ColourChooser(
              selected: _draft.colorValue,
              onSelected: (value) =>
                  setState(() => _draft = _draft.copyWith(colorValue: value)),
            ),
            const SizedBox(height: AppTokens.gap),
            _recordingControls(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _discardTakes();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canSave
              ? () {
                  _keepOnly(_draft.audioPath);
                  Navigator.pop(
                    context,
                    _draft.copyWith(label: _label.text.trim()),
                  );
                }
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _preview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // A parent could not see what they had picked, so a wrong photo only
      // showed up on the board.
      SizedBox(
        height: 120,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(_draft.colorValue),
            borderRadius: BorderRadius.circular(AppTokens.sheetRadius),
            border: Border.all(color: AppTokens.outline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.sheetRadius),
            child: CardMedia(card: _draft),
          ),
        ),
      ),
      if (widget.onChangeMedia != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _changeMedia,
            icon: const Icon(Icons.image_outlined),
            label: const Text('Change picture'),
          ),
        ),
    ],
  );

  Widget _recordingControls() {
    final bool hasRecording = _draft.audioPath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your voice', style: Theme.of(context).textTheme.bodyMedium),
        Text(
          hasRecording
              ? 'Your recording plays instead of the robot voice.'
              : 'Optional. Without one, the robot voice reads the word.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filled(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              tooltip: _isRecording
                  ? 'Stop recording'
                  : (hasRecording ? 'Record again' : 'Record your voice'),
              onPressed: _toggleRecording,
              style: IconButton.styleFrom(
                backgroundColor: _isRecording
                    ? AppTokens.danger
                    : AppTokens.action,
              ),
            ),
            if (_isRecording) ...[
              const SizedBox(width: 12),
              Text(
                _format(_elapsed),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (hasRecording && !_isRecording) ...[
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                tooltip: _isPlaying ? 'Stop' : 'Play the recording',
                onPressed: _togglePlayback,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: AppTokens.danger,
                tooltip: 'Remove the recording',
                onPressed: _removeRecording,
              ),
            ],
          ],
        ),
      ],
    );
  }

  static String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _ColourChooser extends StatelessWidget {
  const _ColourChooser({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Card colour', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: CardPalette.choices
            .map(
              (value) => Semantics(
                button: true,
                selected: value == selected,
                label: 'Card colour ${CardPalette.choices.indexOf(value) + 1}',
                child: InkWell(
                  onTap: () => onSelected(value),
                  customBorder: const CircleBorder(),
                  child: SizedBox.square(
                    dimension: AppTokens.minTouchTarget,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: value == selected
                                ? AppTokens.ink
                                : AppTokens.outline,
                            width: value == selected ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ],
  );
}
