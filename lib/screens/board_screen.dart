import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../data/card_repository.dart';
import '../models/talk_card.dart';
import '../services/speech_service.dart';
import '../theme.dart';
import '../widgets/add_card_sheet.dart';
import '../widgets/card_editor_dialog.dart';
import '../widgets/card_tile.dart';
import '../widgets/parent_lock.dart';
import '../widgets/symbol_picker.dart';

/// The board the child taps, and the editing surface the parent unlocks.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.giphyApiKey});

  /// Empty when no key is configured. Giphy is then left out of the add sheet.
  final String giphyApiKey;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> with WidgetsBindingObserver {
  final CardRepository _repository = CardRepository();
  final SpeechService _speech = SpeechService();
  final ImagePicker _picker = ImagePicker();

  List<TalkCard> _cards = [];
  bool _loading = true;
  bool _parentMode = false;
  String? _busyMessage;

  /// Counts the picker, camera, and editor flows that are open. Those flows
  /// send the app to the background, and backgrounding otherwise locks parent
  /// mode, which would drop the parent out mid-edit.
  int _openFlows = 0;

  Timer? _lockTimer;
  bool _warnedNoSpeech = false;
  bool _warnedMissingRecording = false;

  bool get _giphyEnabled => widget.giphyApiKey.isNotEmpty;

  List<TalkCard> get _childVisibleCards =>
      _cards.where((c) => c.isVisible).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.init();
    _load();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _speech.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app locks editing, so a board handed to the child comes back
    // safe. A picker or the camera also pauses the app, so those are excluded.
    final bool leaving =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (leaving && _parentMode && _openFlows == 0) _lock(announce: false);
  }

  Future<void> _load() async {
    final List<TalkCard> cards = await _repository.load();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  Future<void> _persist() => _repository.save(_cards);

  // --- PARENT MODE ---

  void _unlock() {
    setState(() => _parentMode = true);
    _speech.announce('Parent mode');
    _restartLockTimer();
  }

  void _lock({bool announce = true}) {
    _lockTimer?.cancel();
    _lockTimer = null;
    if (!_parentMode) return;
    setState(() => _parentMode = false);
    if (announce) _speech.announce('Editing locked');
  }

  /// Parent mode closes itself after a spell of no input, so a parent who
  /// forgets does not leave delete buttons under the child's fingers.
  void _restartLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer(AppTokens.parentModeTimeout, () {
      if (!mounted || !_parentMode) return;
      _lock();
      _tell('Editing locked itself.');
    });
  }

  /// Runs [action] with the auto-lock paused, because the flow it opens sends
  /// the app to the background.
  Future<T> _inFlow<T>(Future<T> Function() action) async {
    _openFlows++;
    try {
      return await action();
    } finally {
      _openFlows--;
      if (mounted && _parentMode) _restartLockTimer();
    }
  }

  // --- SPEAKING ---

  Future<void> _speakCard(TalkCard card) async {
    final SpeechOutcome outcome = await _speech.speakCard(card);
    if (!mounted) return;

    switch (outcome) {
      case SpeechOutcome.spoken:
      case SpeechOutcome.played:
        return;
      case SpeechOutcome.recordingMissing:
      case SpeechOutcome.recordingFailed:
        // Warn once. A toddler taps fast, and a snackbar per tap is noise.
        if (_warnedMissingRecording) return;
        _warnedMissingRecording = true;
        _tell(
          outcome == SpeechOutcome.recordingMissing
              ? 'That recording is missing, so the robot voice read the word.'
              : 'That recording would not play, so the robot voice read the '
                    'word.',
        );
      case SpeechOutcome.unavailable:
        if (_warnedNoSpeech) return;
        _warnedNoSpeech = true;
        _tell('This device cannot speak. Check its text-to-speech settings.');
    }
  }

  // --- CARD EDITING ---

  Future<CardMediaSelection?> _chooseMedia() => _inFlow(() async {
    final CardSource? source = await showAddCardSheet(
      context,
      giphyEnabled: _giphyEnabled,
    );
    if (source == null || !mounted) return null;

    switch (source) {
      case CardSource.giphy:
        return _chooseGif();
      case CardSource.library:
        final SymbolChoice? symbol = await showSymbolPicker(context);
        if (symbol == null) return null;
        return CardMediaSelection(
          kind: CardMediaKind.asset,
          content: symbol.assetPath,
          suggestedLabel: symbol.label,
        );
      case CardSource.camera:
      case CardSource.gallery:
        return _choosePhoto(fromCamera: source == CardSource.camera);
    }
  });

  Future<CardMediaSelection?> _chooseGif() async {
    final GiphyGif? gif = await GiphyGet.getGif(
      context: context,
      apiKey: widget.giphyApiKey,
      tabColor: AppTokens.action,
    );
    final String? url = gif?.images?.original?.url;
    if (url == null) return null;

    final String? path = await _run(
      'Saving the GIF...',
      () => _repository.downloadGif(url),
    );
    if (path == null) {
      if (mounted) _tell('That GIF could not be saved. Check the connection.');
      return null;
    }
    return CardMediaSelection(
      kind: CardMediaKind.file,
      content: path,
      suggestedLabel: gif?.title?.split('GIF').first.trim(),
    );
  }

  Future<CardMediaSelection?> _choosePhoto({required bool fromCamera}) async {
    if (fromCamera && !await Permission.camera.request().isGranted) {
      if (mounted) _tell('Toddler Talk needs the camera to take a photo.');
      return null;
    }

    final XFile? photo = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );
    if (photo == null) return null;

    final String path = await _repository.importMedia(photo.path);
    return CardMediaSelection(kind: CardMediaKind.file, content: path);
  }

  Future<void> _addCard() async {
    final CardMediaSelection? media = await _chooseMedia();
    if (media == null || !mounted) return;

    final TalkCard? saved = await _inFlow(
      () => showCardEditor(
        context,
        card: TalkCard(
          id: const Uuid().v4(),
          label: media.suggestedLabel ?? '',
          kind: media.kind,
          content: media.content,
        ),
        repository: _repository,
        onChangeMedia: _chooseMedia,
      ),
    );
    if (saved == null || !mounted) return;

    setState(() => _cards.add(saved));
    await _persist();
  }

  Future<void> _editCard(TalkCard card) async {
    final TalkCard? saved = await _inFlow(
      () => showCardEditor(
        context,
        card: card,
        repository: _repository,
        onChangeMedia: _chooseMedia,
      ),
    );
    if (saved == null || !mounted) return;

    setState(() {
      final int index = _cards.indexWhere((c) => c.id == card.id);
      if (index >= 0) _cards[index] = saved;
    });
    await _persist();
  }

  Future<void> _toggleVisible(TalkCard card) async {
    setState(() {
      final int index = _cards.indexWhere((c) => c.id == card.id);
      if (index >= 0) {
        _cards[index] = card.copyWith(isVisible: !card.isVisible);
      }
    });
    _restartLockTimer();
    await _persist();
  }

  Future<void> _deleteCard(TalkCard card) async {
    final bool confirmed = await _confirm(
      title: 'Delete ${card.label}?',
      message: card.audioPath == null
          ? 'The card goes for good. To take it off the board for now, hide it '
                'instead.'
          : 'The card and your recording of it go for good. To take it off the '
                'board for now, hide it instead.',
      action: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _cards.removeWhere((c) => c.id == card.id));
    await _persist();
    await _repository.deleteMedia(card);
  }

  // --- BACKUP ---

  Future<void> _backup() => _inFlow(() async {
    try {
      final String zipPath = await _run(
        'Packing your cards...',
        () => _repository.exportBackup(_cards),
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(zipPath)], text: 'Toddler Talk backup'),
      );
    } on Object catch (error) {
      debugPrint('Backup failed: $error');
      if (mounted) _tell('The backup could not be made.');
    }
  });

  Future<void> _restore() => _inFlow(() async {
    final bool confirmed = await _confirm(
      title: 'Restore a backup?',
      message:
          'Every card on this device is replaced by the cards in the backup '
          'file. Make a backup first if you want to keep them.',
      action: 'Restore',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final String? path = picked?.files.single.path;
    if (path == null || !mounted) return;

    try {
      final List<TalkCard> cards = await _run(
        'Restoring your cards...',
        () => _repository.importBackup(File(path)),
      );
      if (!mounted) return;
      setState(() => _cards = cards);
      _tell('Your cards are back.');
    } on BackupException catch (error) {
      if (mounted) _tell(error.message);
    } on Object catch (error) {
      debugPrint('Restore failed: $error');
      if (mounted) _tell('That backup could not be read.');
    }
  });

  /// Runs [action] behind a scrim, so a long zip or download does not look
  /// like the app has frozen.
  Future<T> _run<T>(String message, Future<T> Function() action) async {
    setState(() => _busyMessage = message);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _busyMessage = null);
    }
  }

  // --- DIALOGS ---

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: AppTokens.danger)
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  void _tell(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Any touch counts as parent activity, so the auto-lock only fires after
      // real inactivity.
      onPointerDown: (_) {
        if (_parentMode) _restartLockTimer();
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('Toddler Talk'),
              actions: [
                if (_parentMode) ...[
                  PopupMenuButton<String>(
                    tooltip: 'Backup and restore',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) =>
                        value == 'backup' ? _backup() : _restore(),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'backup',
                        child: Text('Backup Data'),
                      ),
                      PopupMenuItem(
                        value: 'restore',
                        child: Text('Restore Data'),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, size: 32),
                    color: AppTokens.action,
                    tooltip: 'Add a card',
                    onPressed: _addCard,
                  ),
                ],
                ParentLock(
                  unlocked: _parentMode,
                  onUnlock: _unlock,
                  onLock: _lock,
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: Column(
              children: [
                if (_parentMode) _banner(),
                Expanded(child: _board()),
              ],
            ),
          ),
          if (_busyMessage != null) _scrim(_busyMessage!),
        ],
      ),
    );
  }

  /// States the mode plainly, and gives one tap back out of it. Red app-bar
  /// text was easy to miss, and leaving needed a second long press.
  Widget _banner() => Material(
    color: AppTokens.parentMode,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(AppTokens.gap, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.lock_open, color: AppTokens.onParentMode, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            // Capped, because at a large text scale a long line wraps until
            // the banner claims the whole screen and the board gets none.
            child: Text(
              'Parent mode: cards can be edited',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTokens.onParentMode),
            ),
          ),
          TextButton(
            onPressed: _lock,
            style: TextButton.styleFrom(
              foregroundColor: AppTokens.onParentMode,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );

  Widget _board() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final List<TalkCard> shown = _parentMode ? _cards : _childVisibleCards;
    if (shown.isEmpty) return _emptyState();

    final SliverGridDelegate delegate =
        SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: AppTokens.tileExtent,
          crossAxisSpacing: AppTokens.gap,
          mainAxisSpacing: AppTokens.gap,
          // A card is taller in parent mode, to make room for its edit row
          // without shrinking the picture.
          childAspectRatio: _parentMode ? 0.78 : 1.0,
        );
    const EdgeInsets padding = EdgeInsets.all(AppTokens.gap);

    // Toddler mode uses a plain grid. A reorderable grid keeps its long-press
    // drag whatever its drag widget draws, so the child could rearrange the
    // board and the change was saved.
    if (!_parentMode) {
      return GridView.builder(
        padding: padding,
        gridDelegate: delegate,
        itemCount: shown.length,
        itemBuilder: (context, index) => _tile(shown[index]),
      );
    }

    return ReorderableGridView.builder(
      padding: padding,
      gridDelegate: delegate,
      itemCount: shown.length,
      onReorder: (oldIndex, newIndex) {
        setState(() => _cards.insert(newIndex, _cards.removeAt(oldIndex)));
        _restartLockTimer();
        _persist();
      },
      itemBuilder: (context, index) => _tile(shown[index]),
    );
  }

  Widget _tile(TalkCard card) => CardTile(
    key: ValueKey(card.id),
    card: card,
    parentMode: _parentMode,
    onSpeak: () => _speakCard(card),
    onEdit: () => _editCard(card),
    onToggleVisible: () => _toggleVisible(card),
    onDelete: () => _deleteCard(card),
  );

  Widget _emptyState() => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _parentMode ? Icons.add_photo_alternate_outlined : Icons.favorite,
            size: 72,
            color: AppTokens.inkMuted,
          ),
          const SizedBox(height: AppTokens.gap),
          Text(
            _parentMode
                ? 'The board is empty'
                : 'Ask a grown-up to add some cards',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _parentMode
                ? 'Add a card for each thing your child asks for most.'
                : 'A grown-up holds the lock at the top to add cards.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_parentMode) ...[
            const SizedBox(height: AppTokens.gap),
            ElevatedButton.icon(
              onPressed: _addCard,
              icon: const Icon(Icons.add),
              label: const Text('Add your first card'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _scrim(String message) => Positioned.fill(
    child: ColoredBox(
      color: AppTokens.scrim,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTokens.onAction),
            const SizedBox(height: AppTokens.gap),
            Text(
              message,
              style: const TextStyle(color: AppTokens.onAction, fontSize: 16),
            ),
          ],
        ),
      ),
    ),
  );
}
