import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../data/card_repository.dart';
import '../models/board_page.dart';
import '../models/board_settings.dart';
import '../models/talk_card.dart';
import '../services/speech_service.dart';
import '../theme.dart';
import '../widgets/add_card_sheet.dart';
import '../widgets/card_editor_dialog.dart';
import '../widgets/card_tile.dart';
import '../widgets/page_tabs.dart';
import '../widgets/pages_sheet.dart';
import '../widgets/parent_gate.dart';
import '../widgets/parent_lock.dart';
import '../widgets/settings_sheet.dart';
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
  List<BoardPage> _pages = [BoardPage.home];

  /// The page the parent or the child last opened. Null opens the first page
  /// with a tab.
  String? _openPageId;

  BoardSettings _settings = const BoardSettings();
  bool _loading = true;

  /// True when the stored board could not be read. Nothing saves the board
  /// while this holds, so a retry reads the stored value as it was.
  bool _loadFailed = false;

  bool _parentMode = false;
  String? _busyMessage;

  /// Counts the flows that are open: the pickers, the camera, the editor, and
  /// the sheets. A picker or the camera sends the app to the background, and
  /// backgrounding otherwise locks parent mode, which would drop the parent
  /// out mid-edit.
  int _openFlows = 0;

  Timer? _lockTimer;
  bool _warnedNoSpeech = false;
  bool _warnedMissingRecording = false;

  bool get _giphyEnabled => widget.giphyApiKey.isNotEmpty;

  /// The pages with a tab in the current mode. A parent sees every page. A
  /// child sees only a page with a card to tap.
  List<BoardPage> get _shownPages => _parentMode
      ? _pages
      : [
          for (final BoardPage page in _pages)
            if (cardsOnPage(_cards, _pages, page.id).any((c) => c.isVisible))
              page,
        ];

  /// The open page. When it has no tab, the first page with a tab stands in.
  /// Null only for a child with no card to tap.
  BoardPage? get _openPage {
    final List<BoardPage> shown = _shownPages;
    if (shown.isEmpty) return null;
    return shown.firstWhere(
      (page) => page.id == _openPageId,
      orElse: () => shown.first,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySystemUi();
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
    // Android can show the system bars again after a resume.
    if (state == AppLifecycleState.resumed && !_parentMode) _applySystemUi();
  }

  Future<void> _load() async {
    final List<TalkCard> cards;
    final BoardSettings settings;
    final List<BoardPage> pages;
    try {
      cards = await _repository.load();
      settings = await _repository.loadSettings();
      pages = await _repository.loadPages();
    } on Object catch (error) {
      debugPrint('Load failed: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    // Not awaited: a slow voice engine must not hold back the board.
    _speech.apply(settings);
    setState(() {
      _cards = cards;
      _pages = pages;
      _settings = settings;
      _loading = false;
    });
  }

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    _load();
  }

  Future<void> _startNewBoard() async {
    await _repository.startNewBoard();
    if (mounted) _retryLoad();
  }

  Future<void> _persist() => _repository.save(_cards);

  // --- PARENT MODE ---

  Future<void> _unlock() async {
    if (!await showParentGate(context) || !mounted) return;
    setState(() => _parentMode = true);
    _applySystemUi();
    _speech.announce('Parent mode');
    _restartLockTimer();
  }

  void _lock({bool announce = true}) {
    _lockTimer?.cancel();
    _lockTimer = null;
    if (!_parentMode) return;
    setState(() {
      _parentMode = false;
      // A page with no card left for the child has no tab, so the first page
      // with a tab opens in its place, and stays open.
      _openPageId = _openPage?.id;
    });
    _applySystemUi();
    if (announce) _speech.announce('Editing locked');
  }

  /// Hides the system bars from the child, so a swipe from the edge does not
  /// take them out of the app. A parent gets the bars back.
  void _applySystemUi() => SystemChrome.setEnabledSystemUIMode(
    _parentMode ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
  );

  /// Opens [page]. A child also hears its name, the way a card speaks.
  void _openTab(BoardPage page) {
    setState(() => _openPageId = page.id);
    if (!_parentMode) _speech.announce(page.name);
  }

  /// Parent mode closes itself after a spell of no input, so a parent who
  /// forgets does not leave delete buttons under the child's fingers.
  ///
  /// No timer runs while a flow is open, because the parent is busy in it.
  /// The outermost flow starts the timer when it ends.
  void _restartLockTimer() {
    _lockTimer?.cancel();
    if (_openFlows > 0) return;
    _lockTimer = Timer(AppTokens.parentModeTimeout, () {
      if (!mounted || !_parentMode) return;
      _lock();
      _tell('Editing locked itself.');
    });
  }

  /// Runs [action] with the auto-lock paused. The flow it opens is a route of
  /// its own, or it sends the app to the background, so the board sees none
  /// of the parent's touches until it ends.
  Future<T> _inFlow<T>(Future<T> Function() action) async {
    _openFlows++;
    _lockTimer?.cancel();
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

    // A camera photo is far larger than a card needs. A gallery pick keeps its
    // size, because a resize drops the animation from a GIF.
    final XFile? photo = fromCamera
        ? await _picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 85,
          )
        : await _picker.pickImage(source: ImageSource.gallery);
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
          pageId: _openPage?.id,
        ),
        repository: _repository,
        onHear: _speech.announce,
        pages: _pages,
        onChangeMedia: _chooseMedia,
      ),
    );
    if (saved == null) {
      // The parent backed out, so the picture they picked belongs to nothing.
      if (media.kind == CardMediaKind.file) {
        await _repository.deleteOwnedFile(media.content);
      }
      return;
    }
    if (!mounted) return;

    setState(() => _cards.add(saved));
    await _persist();
  }

  Future<void> _editCard(TalkCard card) async {
    final TalkCard? saved = await _inFlow(
      () => showCardEditor(
        context,
        card: card,
        repository: _repository,
        onHear: _speech.announce,
        pages: _pages,
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
    final bool? deleteFiles = await _confirmDelete(card);
    if (deleteFiles == null || !mounted) return;

    setState(() => _cards.removeWhere((c) => c.id == card.id));
    await _persist();
    // The parent can keep the photo or the recording even when the card goes,
    // so a family photo is not lost with the card that used it.
    if (deleteFiles) await _repository.deleteMedia(card);
  }

  /// Asks whether to delete [card], and whether its files go too.
  ///
  /// The file question is only asked when the card owns a file. A bundled
  /// symbol owns nothing.
  Future<bool?> _confirmDelete(TalkCard card) {
    final bool ownsFiles =
        card.kind == CardMediaKind.file || card.audioPath != null;
    return _confirm(
      title: 'Delete ${card.label}?',
      message:
          'The card goes for good. To take it off the board for now, '
          'hide it instead.',
      action: 'Delete',
      tickBox: !ownsFiles
          ? null
          : (card.audioPath == null
                ? 'Delete its picture from this device'
                : 'Delete its picture and recording from this device'),
    );
  }

  // --- SETTINGS ---

  Future<void> _openSettings() => _inFlow(
    () => showSettingsSheet(
      context,
      settings: _settings,
      onChanged: _changeSettings,
      onHear: _speech.announce,
    ),
  );

  void _changeSettings(BoardSettings settings) {
    setState(() => _settings = settings);
    _speech.apply(settings);
    _repository.saveSettings(settings);
  }

  // --- PAGES ---

  Future<void> _openPagesSheet() => _inFlow(
    () => showPagesSheet(
      context,
      pages: () => _pages,
      onChanged: _changePages,
      onDelete: _deletePage,
    ),
  );

  void _changePages(List<BoardPage> pages) {
    setState(() => _pages = pages);
    _repository.savePages(pages);
  }

  /// Deletes [page] once the parent agrees. Its cards move to the first page
  /// that remains, each as hidden or shown as it was, so no card is lost.
  Future<void> _deletePage(BoardPage page) async {
    final List<BoardPage> remaining = [
      for (final BoardPage other in _pages)
        if (other.id != page.id) other,
    ];
    final BoardPage target = remaining.first;
    final int moving = cardsOnPage(_cards, _pages, page.id).length;
    final bool? confirmed = await _confirm(
      title: 'Delete the ${page.name} page?',
      message: switch (moving) {
        0 => 'It has no cards.',
        1 => 'Its 1 card moves to ${target.name}. No card is deleted.',
        _ => 'Its $moving cards move to ${target.name}. No card is deleted.',
      },
      action: 'Delete',
    );
    if (confirmed == null || !mounted) return;

    setState(() {
      _cards = [
        for (final TalkCard card in _cards)
          pageIdOf(card, _pages) == page.id
              ? card.copyWith(pageId: target.id)
              : card,
      ];
      _pages = remaining;
      if (_openPageId == page.id) _openPageId = target.id;
    });
    // The cards first, so a card never points at a page that is gone.
    await _persist();
    await _repository.savePages(_pages);
  }

  // --- BACKUP ---

  Future<void> _backup() => _inFlow(() async {
    try {
      final String zipPath = await _run(
        'Packing your cards...',
        () => _repository.exportBackup(
          _cards,
          pages: _pages,
          settings: _settings,
        ),
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
    final bool? deleteFiles = await _confirmRestore();
    if (deleteFiles == null || !mounted) return;

    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final String? path = picked?.files.single.path;
    if (path == null || !mounted) return;

    final List<TalkCard> replaced = _cards;
    final Backup backup;
    try {
      backup = await _run(
        'Restoring your cards...',
        () => _repository.importBackup(File(path)),
      );
      if (!mounted) return;
      final BoardSettings? settings = backup.settings;
      if (settings != null) _speech.apply(settings);
      setState(() {
        _cards = backup.cards;
        _pages = backup.pages;
        _settings = settings ?? _settings;
        _openPageId = backup.pages.first.id;
      });
      _tell('Your cards are back.');
    } on BackupException catch (error) {
      if (mounted) _tell(error.message);
      return;
    } on Object catch (error) {
      debugPrint('Restore failed: $error');
      if (mounted) _tell('That backup could not be read.');
      return;
    }
    // Outside the try, so a failed delete is not reported as a failed restore.
    if (deleteFiles) {
      await _repository.deleteReplacedMedia(replaced, backup.cards);
    }
  });

  /// Asks whether to replace the board, and whether the replaced cards' files
  /// go too.
  ///
  /// The file question is only asked when the board owns a file.
  Future<bool?> _confirmRestore() => _confirm(
    title: 'Restore a backup?',
    message:
        'Every card on this device is replaced by the cards in the backup '
        'file. Make a backup first if you want to keep them.',
    action: 'Restore',
    tickBox:
        _cards.any((c) => c.kind == CardMediaKind.file || c.audioPath != null)
        ? "Delete the replaced cards' pictures and recordings from this device"
        : null,
  );

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

  /// Asks the parent to confirm a destructive [action].
  ///
  /// Returns null when the parent keeps things as they are. Otherwise it
  /// returns their answer to the [tickBox] question, ticked by default, or
  /// false when there is no question.
  Future<bool?> _confirm({
    required String title,
    required String message,
    required String action,
    String? tickBox,
  }) {
    bool ticked = true;

    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (tickBox != null)
                CheckboxListTile(
                  value: ticked,
                  onChanged: (value) =>
                      setLocalState(() => ticked = value ?? ticked),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    tickBox,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, tickBox != null && ticked),
              style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }

  void _tell(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final List<BoardPage> tabs = _shownPages;
    final BoardPage? open = _openPage;
    // A child's Back press does nothing. A dialog or a sheet is a route of its
    // own, so Back closes it as usual.
    return PopScope(
      canPop: _parentMode,
      child: Listener(
        // Any touch counts as parent activity, so the auto-lock only fires
        // after real inactivity.
        onPointerDown: (_) {
          if (_parentMode) _restartLockTimer();
        },
        child: Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text('Toddler Talk'),
                actions: [
                  if (_parentMode && !_loadFailed) ...[
                    PopupMenuButton<String>(
                      tooltip: 'Settings and backup',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) => switch (value) {
                        'settings' => _openSettings(),
                        'pages' => _openPagesSheet(),
                        'backup' => _backup(),
                        _ => _restore(),
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'settings',
                          child: Text('Settings'),
                        ),
                        PopupMenuItem(value: 'pages', child: Text('Pages')),
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
                  // One tab alone would be a control that does nothing, so a
                  // board with one page looks as it always has.
                  if (!_loading && open != null && tabs.length > 1)
                    PageTabs(pages: tabs, openId: open.id, onOpen: _openTab),
                  Expanded(child: _board(open)),
                ],
              ),
            ),
            if (_busyMessage != null) _scrim(_busyMessage!),
          ],
        ),
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

  Widget _board(BoardPage? page) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed) return _loadError();

    final List<TalkCard> shown = [
      if (page != null)
        for (final TalkCard card in cardsOnPage(_cards, _pages, page.id))
          if (_parentMode || card.isVisible) card,
    ];
    if (page == null || shown.isEmpty) return _emptyState();

    final SliverGridDelegate delegate =
        SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _settings.cardSize.extent,
          crossAxisSpacing: AppTokens.gap,
          mainAxisSpacing: AppTokens.gap,
          // A card is taller in parent mode, to make room for its edit row
          // without shrinking the picture.
          childAspectRatio: _parentMode ? 0.78 : 1.0,
        );
    const EdgeInsets padding = EdgeInsets.all(AppTokens.gap);

    // A key per page, so each page opens at the top of its own scroll.
    final Key key = ValueKey(page.id);

    // Toddler mode uses a plain grid. A reorderable grid keeps its long-press
    // drag whatever its drag widget draws, so the child could rearrange the
    // board and the change was saved.
    if (!_parentMode) {
      return GridView.builder(
        key: key,
        padding: padding,
        gridDelegate: delegate,
        itemCount: shown.length,
        itemBuilder: (context, index) => _tile(shown[index]),
      );
    }

    return ReorderableGridView.builder(
      key: key,
      padding: padding,
      gridDelegate: delegate,
      itemCount: shown.length,
      onReorder: (oldIndex, newIndex) {
        setState(
          () => _cards = reorderWithinPage(
            _cards,
            _pages,
            page.id,
            oldIndex,
            newIndex,
          ),
        );
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
    speaking: _speech.speaking,
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
                ? (_cards.isEmpty ? 'The board is empty' : 'This page is empty')
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
              label: Text(
                _cards.isEmpty ? 'Add your first card' : 'Add a card',
              ),
            ),
          ],
        ],
      ),
    ),
  );

  /// A child gets no new board, because it puts the starter cards in place of
  /// the old ones.
  Widget _loadError() => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.gap * 2),
      child: Column(
        children: [
          Text(
            'The cards could not be loaded',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _parentMode
                ? 'Try again first. A new board starts from the starter cards, '
                      'and keeps a copy of the old cards on this device.'
                : 'Ask a grown-up to help.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppTokens.gap),
          ElevatedButton.icon(
            onPressed: _retryLoad,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
          if (_parentMode) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _startNewBoard,
              child: const Text('Start a new board'),
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
