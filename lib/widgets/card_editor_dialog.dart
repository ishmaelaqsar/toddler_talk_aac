import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../data/card_repository.dart';
import '../models/board_page.dart';
import '../models/talk_card.dart';
import '../theme.dart';
import 'card_media.dart';
import 'choices.dart';

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
///
/// [onHear] speaks the words the card says, so a parent can check them before
/// they save. With more than one of [pages], the parent can move the card to
/// another page.
Future<TalkCard?> showCardEditor(
  BuildContext context, {
  required TalkCard card,
  required CardRepository repository,
  required ValueChanged<String> onHear,
  required List<BoardPage> pages,
  MediaChooser? onChangeMedia,
}) => showDialog<TalkCard>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _CardEditorDialog(
    card: card,
    repository: repository,
    onHear: onHear,
    pages: pages,
    onChangeMedia: onChangeMedia,
  ),
);

class _CardEditorDialog extends StatefulWidget {
  const _CardEditorDialog({
    required this.card,
    required this.repository,
    required this.onHear,
    required this.pages,
    this.onChangeMedia,
  });

  final TalkCard card;
  final CardRepository repository;
  final ValueChanged<String> onHear;
  final List<BoardPage> pages;
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
  late final TextEditingController _speech = TextEditingController(
    text: widget.card.speech,
  );

  late TalkCard _draft = widget.card;
  bool _isRecording = false;
  bool _isPlaying = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  /// Files this dialog wrote: takes recorded here, and pictures picked here.
  ///
  /// Cancelling drops all of them. Nothing else points at them, because the
  /// card the parent cancelled out of is unchanged.
  final Set<String> _wroteHere = {};

  /// The files the card arrived with. A bundled symbol is not one of them.
  late final Set<String> _arrivedWith = {
    if (widget.card.kind == CardMediaKind.file) widget.card.content,
    ?widget.card.audioPath,
  };

  /// Whether saving should also take the replaced files off the device.
  bool _deleteReplaced = true;

  /// The files that saving would leave with nothing pointing at them.
  Set<String> get _replaced =>
      {..._wroteHere, ..._arrivedWith}..removeAll(_inUse);

  Set<String> get _inUse => {
    if (_draft.kind == CardMediaKind.file) _draft.content,
    ?_draft.audioPath,
  };

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
    _speech.dispose();
    super.dispose();
  }

  bool get _canSave => _label.text.trim().isNotEmpty;

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Before the await, so the ticker cannot stop the recorder a second
      // time.
      _ticker?.cancel();
      final String? path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        if (path != null) {
          _wroteHere.add(path);
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
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= AppTokens.recordingLimit) _toggleRecording();
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
      // A bundled symbol is an asset key, not a file on the device.
      if (picked.kind == CardMediaKind.file) _wroteHere.add(picked.content);
      _draft = _draft.copyWith(kind: picked.kind, content: picked.content);
    });
  }

  /// Cancelling: undo what this dialog wrote. The card is unchanged, so it
  /// still points at everything it arrived with.
  void _cancel() {
    _release(_wroteHere.difference(_arrivedWith));
    Navigator.pop(context);
  }

  /// Saving: commit the card, and take the replaced files off the device if
  /// the parent left that box ticked.
  void _save() {
    if (_deleteReplaced) _release(_replaced);
    Navigator.pop(
      context,
      _draft.copyWith(label: _label.text.trim(), speech: _speech.text.trim()),
    );
  }

  void _hear() {
    final String speech = _speech.text.trim();
    widget.onHear(speech.isEmpty ? _label.text.trim() : speech);
  }

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
              // The keyboard covers much of the dialog, so it rises only when
              // the card needs a word.
              autofocus: widget.card.label.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'What the card says',
                border: const OutlineInputBorder(),
                errorText: _canSave ? null : 'A card needs a word',
              ),
            ),
            const SizedBox(height: AppTokens.gap),
            TextField(
              controller: _speech,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What it says (optional)',
                border: OutlineInputBorder(),
                // A widget, not helperText, so the hint wraps instead of
                // ending in an ellipsis at a large text scale.
                helper: Text(
                  'Leave it empty to say the word on the card. A recording, '
                  'when there is one, plays in place of this text.',
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _hear,
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Hear it'),
              ),
            ),
            const SizedBox(height: AppTokens.gap),
            _ColourChooser(
              selected: _draft.colorValue,
              onSelected: (value) =>
                  setState(() => _draft = _draft.copyWith(colorValue: value)),
            ),
            const SizedBox(height: AppTokens.gap),
            if (widget.pages.length > 1)
              Choices<String>(
                title: 'Page',
                names: {
                  for (final BoardPage page in widget.pages) page.id: page.name,
                },
                selected: pageIdOf(_draft, widget.pages),
                onSelected: (id) =>
                    setState(() => _draft = _draft.copyWith(pageId: id)),
              ),
            _recordingControls(),
            _replacedFileChoice(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  /// Offered only when saving would strand a file the app owns.
  Widget _replacedFileChoice() {
    final int count = _replaced.length;
    if (count == 0) return const SizedBox.shrink();

    return CheckboxListTile(
      value: _deleteReplaced,
      onChanged: (value) =>
          setState(() => _deleteReplaced = value ?? _deleteReplaced),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        count == 1
            ? 'Delete the file it replaces from this device'
            : 'Delete the $count files it replaces from this device',
        style: Theme.of(context).textTheme.bodySmall,
      ),
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
                '${_format(_elapsed)} / ${_format(AppTokens.recordingLimit)}',
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
