import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/board_page.dart';
import '../models/board_settings.dart';
import '../models/talk_card.dart';
import '../theme.dart';

/// Raised when a backup cannot be read, so the caller can show a message
/// instead of a bare exception.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a restore brought back.
class Backup {
  const Backup({required this.cards, required this.pages, this.settings});

  final List<TalkCard> cards;

  /// One Home page when the backup holds no pages.
  final List<BoardPage> pages;

  /// Null when the backup holds no settings, so the device keeps its own.
  final BoardSettings? settings;
}

/// Reads and writes the board, and the media files the board points at.
class CardRepository {
  CardRepository({http.Client? client}) : _client = client ?? http.Client();

  /// The storage key. Unchanged, so an existing install keeps its cards.
  static const String storageKey = 'toddler_cards_v5';

  /// The settings key, apart from the board, so the board's shape stays as it
  /// is.
  static const String settingsKey = 'toddler_settings_v1';

  static const String pagesKey = 'toddler_pages_v1';

  /// Keeps a board the app could not read, so a new board does not lose it
  /// for good.
  static const String rescueKey = 'toddler_cards_v5_unreadable';

  /// The file inside a backup that holds the board itself.
  static const String _manifestName = 'cards.json';

  /// The files inside a backup that hold the pages and the settings. An older
  /// build skips them, because `.json` is not in its media allow-list.
  static const String _pagesName = 'pages.json';
  static const String _settingsName = 'settings.json';

  /// Media a backup is allowed to carry. Anything else is skipped.
  static const Set<String> mediaExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.m4a',
  };

  static const Uuid _uuid = Uuid();

  /// The parent waits behind a scrim while a GIF saves, so a stalled
  /// connection must end in a message, not a screen that never clears.
  static const Duration _downloadTimeout = Duration(seconds: 15);

  final http.Client _client;

  /// The board a first run starts with: the needs a toddler asks for most.
  ///
  /// Body care has no colour group of its own, so it takes the neutral fill.
  static List<TalkCard> defaultCards() => [
    _starter('Hungry', 'dinner.svg', CardPalette.food),
    _starter('Thirsty', 'water.svg', CardPalette.drink),
    _starter('Milk', 'milk.svg', CardPalette.drink),
    _starter('Play', 'lego.svg', CardPalette.play),
    _starter('Nappy', 'nappy.svg', CardPalette.neutral),
    _starter('Potty', 'potty_chair.svg', CardPalette.neutral),
    _starter('Sleepy', 'bed_time.svg', CardPalette.feelings),
    _starter('Bath', 'bath.svg', CardPalette.neutral),
    _starter('Outside', 'outside.svg', CardPalette.play),
    _starter('Hug', 'hug_,_to.svg', CardPalette.people),
    _starter('Book', 'read_book_,_to.svg', CardPalette.play),
    _starter('Music', 'music.svg', CardPalette.play),
  ];

  static TalkCard _starter(String label, String symbol, int colorValue) =>
      TalkCard(
        id: _uuid.v4(),
        label: label,
        kind: CardMediaKind.asset,
        content: 'assets/symbols/$symbol',
        colorValue: colorValue,
      );

  /// Returns the stored board, or the defaults on a first run.
  Future<List<TalkCard>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(storageKey);

    if (stored == null) {
      final List<TalkCard> cards = defaultCards();
      await save(cards);
      return cards;
    }
    return decode(stored);
  }

  /// Copies the stored board to [rescueKey], then saves the starter board in
  /// its place.
  ///
  /// The copy comes first, so the old board is on the device at every step.
  Future<void> startNewBoard() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(storageKey);
    if (stored != null) await prefs.setString(rescueKey, stored);
    await save(defaultCards());
  }

  Future<void> save(List<TalkCard> cards) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      json.encode(cards.map((c) => c.toJson()).toList()),
    );
  }

  /// Returns the stored settings. The defaults stand in when nothing is stored
  /// or the stored value cannot be read, so bad settings never block the
  /// board.
  Future<BoardSettings> loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _readSettings(prefs.getString(settingsKey)) ?? const BoardSettings();
  }

  Future<void> saveSettings(BoardSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(settingsKey, json.encode(settings.toJson()));
  }

  /// Null when [source] is null or cannot be read.
  static BoardSettings? _readSettings(String? source) {
    if (source == null) return null;
    try {
      return BoardSettings.fromJson(
        json.decode(source) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  Future<List<BoardPage>> loadPages() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _readPages(prefs.getString(pagesKey));
  }

  Future<void> savePages(List<BoardPage> pages) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      pagesKey,
      json.encode(pages.map((page) => page.toJson()).toList()),
    );
  }

  /// One Home page stands in when [source] is null, empty, or cannot be read,
  /// so the board always has a page.
  static List<BoardPage> _readPages(String? source) {
    if (source == null) return [BoardPage.home];
    try {
      final List<BoardPage> pages = (json.decode(source) as List<dynamic>)
          .map((page) => BoardPage.fromJson(page as Map<String, dynamic>))
          .toList();
      return pages.isEmpty ? [BoardPage.home] : pages;
    } on Object {
      return [BoardPage.home];
    }
  }

  /// Parses the stored board. Skips a record the app cannot read, so one bad
  /// entry does not cost the parent the whole board.
  List<TalkCard> decode(String source) {
    final List<dynamic> raw = json.decode(source) as List<dynamic>;
    final List<TalkCard> cards = [];
    for (final dynamic entry in raw) {
      try {
        cards.add(TalkCard.fromJson(entry as Map<String, dynamic>));
      } on Object {
        continue;
      }
    }
    return cards;
  }

  // --- MEDIA ---

  /// Copies a picked photo into the app's own directory, so the card keeps
  /// working after the gallery entry goes away.
  Future<String> importMedia(String sourcePath) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final String target = p.join(
      dir.path,
      '${_uuid.v4()}${p.extension(sourcePath)}',
    );
    await File(sourcePath).copy(target);
    return target;
  }

  /// Downloads a GIF for offline use. Returns null when the fetch fails.
  Future<String?> downloadGif(String url) async {
    try {
      final http.Response response = await _client
          .get(Uri.parse(url))
          .timeout(_downloadTimeout);
      if (response.statusCode != 200) return null;

      final Directory dir = await getApplicationDocumentsDirectory();
      final String path = p.join(dir.path, '${_uuid.v4()}.gif');
      await File(path).writeAsBytes(response.bodyBytes);
      return path;
    } on Object {
      return null;
    }
  }

  /// A path for a new recording.
  Future<String> newRecordingPath() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, '${_uuid.v4()}.m4a');
  }

  /// Removes the files a deleted card owned. A bundled asset is left alone.
  Future<void> deleteMedia(TalkCard card) async {
    for (final String? path in [
      if (card.kind == CardMediaKind.file) card.content,
      card.audioPath,
    ]) {
      if (path != null) await deleteOwnedFile(path);
    }
  }

  /// Deletes [path], but only if the app is what wrote it.
  ///
  /// Every photo, GIF, and recording the app makes lands in the app's own
  /// documents directory, and a restore rehomes an imported one there too. A
  /// path outside that directory belongs to something else on the device, so
  /// it is not the app's to remove.
  Future<void> deleteOwnedFile(String path) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    if (!p.isWithin(dir.path, path)) return;

    final File file = File(path);
    if (await file.exists()) await file.delete();
  }

  // --- BACKUP ---

  /// Writes a zip holding the board, every media file it points at, and the
  /// [pages] and [settings] when given, and returns its path.
  ///
  /// The zip goes to a temporary directory, so a second backup never packs
  /// the first one. Its name carries the date, so a parent can tell two
  /// backups apart.
  Future<String> exportBackup(
    List<TalkCard> cards, {
    List<BoardPage>? pages,
    BoardSettings? settings,
  }) async {
    final String date = DateTime.now().toIso8601String().substring(0, 10);
    return _writeZip(
      p.join((await getTemporaryDirectory()).path, 'backup'),
      'toddler_talk_backup_$date.zip',
      {
        _manifestName: json.encode(cards.map((c) => c.toJson()).toList()),
        if (pages != null)
          _pagesName: json.encode(pages.map((page) => page.toJson()).toList()),
        if (settings != null) _settingsName: json.encode(settings.toJson()),
      },
      // Pack only the media the board actually references, so a stale file
      // from a deleted card does not travel with the backup.
      _referencedMedia(cards).toList(),
    );
  }

  /// Packs the zip on a background isolate, so a board of many photos does
  /// not freeze the screen. [documents] maps a file name in the zip to its
  /// text.
  ///
  /// Static, and given only strings, so the isolate receives no repository.
  static Future<String> _writeZip(
    String stagingPath,
    String zipName,
    Map<String, String> documents,
    List<String> media,
  ) => Isolate.run(() async {
    // A zip from another day has another name, so nothing overwrites it, and
    // each one holds every photo.
    final Directory staging = Directory(stagingPath);
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    final String zipPath = p.join(staging.path, zipName);
    final ZipFileEncoder encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final MapEntry<String, String> document in documents.entries) {
      encoder.addArchiveFile(ArchiveFile.string(document.key, document.value));
    }

    for (final String path in media) {
      final File file = File(path);
      // JPEG, GIF, and M4A are already compressed, so a second pass costs
      // time and saves nothing.
      if (await file.exists()) {
        await encoder.addFile(file, null, ZipFileEncoder.store);
      }
    }
    await encoder.close();
    return zipPath;
  });

  Iterable<String> _referencedMedia(List<TalkCard> cards) => cards
      .expand((c) => [if (c.kind == CardMediaKind.file) c.content, c.audioPath])
      .whereType<String>();

  /// Unpacks a backup, saves what it holds, and returns it.
  ///
  /// Media lands in the app's documents directory, and every card's paths are
  /// rewritten to point there. The paths inside a backup belong to the device
  /// that wrote it, so a restore onto a second device needs the rewrite to
  /// find its pictures at all.
  ///
  /// A backup with no pages restores as one Home page. A backup with no
  /// settings leaves the device's settings as they are.
  Future<Backup> importBackup(File zip) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final Map<String, String> documents = await _unpack(zip.path, dir.path);

    final List<TalkCard> cards = decode(
      documents[_manifestName]!,
    ).map((c) => _rehomeMedia(c, dir.path)).toList();
    final List<BoardPage> pages = _readPages(documents[_pagesName]);
    final BoardSettings? settings = _readSettings(documents[_settingsName]);
    await save(cards);
    await savePages(pages);
    if (settings != null) await saveSettings(settings);
    return Backup(cards: cards, pages: pages, settings: settings);
  }

  /// Reads the zip from disk on a background isolate, writes its media to
  /// [dirPath], and returns the text of each document it holds, by name.
  ///
  /// Static, and given only strings, so the isolate receives no repository.
  /// No media is written until the manifest is found, so a zip that is not a
  /// backup leaves the app's directory as it was.
  static Future<Map<String, String>> _unpack(
    String zipPath,
    String dirPath,
  ) => Isolate.run(() async {
    final InputFileStream input = InputFileStream(zipPath);
    try {
      final Archive archive = ZipDecoder().decodeStream(input);

      final Map<String, ArchiveFile> documents = {};
      final List<ArchiveFile> media = [];
      for (final ArchiveFile entry in archive) {
        if (!entry.isFile) continue;

        // A zip may name an entry `../../elsewhere`. Keep the base name
        // only, so an entry can never write outside the app's own
        // directory.
        final String name = p.basename(entry.name);
        if (name.isEmpty || name == '.' || name == '..') continue;

        if (name == _manifestName ||
            name == _pagesName ||
            name == _settingsName) {
          documents[name] = entry;
          continue;
        }
        if (!mediaExtensions.contains(p.extension(name).toLowerCase())) {
          continue;
        }
        media.add(entry);
      }

      if (!documents.containsKey(_manifestName)) {
        throw const BackupException('That file is not a Toddler Talk backup.');
      }
      final Map<String, String> texts = {
        for (final MapEntry<String, ArchiveFile> document in documents.entries)
          document.key: utf8.decode(document.value.readBytes() ?? const []),
      };

      for (final ArchiveFile entry in media) {
        final OutputFileStream output = OutputFileStream(
          p.join(dirPath, p.basename(entry.name)),
        );
        entry.writeContent(output);
        await output.close();
      }
      return texts;
    } finally {
      await input.close();
    }
  });

  TalkCard _rehomeMedia(TalkCard card, String dirPath) => card.copyWith(
    content: card.kind == CardMediaKind.file
        ? p.join(dirPath, p.basename(card.content))
        : card.content,
    audioPath: card.audioPath == null
        ? null
        : p.join(dirPath, p.basename(card.audioPath!)),
  );

  /// Deletes the files of a replaced board that the restored board does not
  /// point at.
  ///
  /// A backup made on this device names the same files as the board it
  /// replaces, so a file stays while any restored card points at it.
  Future<void> deleteReplacedMedia(
    List<TalkCard> replaced,
    List<TalkCard> restored,
  ) async {
    final Set<String> inUse = _referencedMedia(restored).toSet();
    for (final String path in _referencedMedia(replaced)) {
      if (!inUse.contains(path)) await deleteOwnedFile(path);
    }
  }
}
