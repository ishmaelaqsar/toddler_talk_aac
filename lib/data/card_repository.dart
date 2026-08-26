import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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

/// Reads and writes the board, and the media files the board points at.
class CardRepository {
  /// The storage key. Unchanged, so an existing install keeps its cards.
  static const String storageKey = 'toddler_cards_v5';

  /// The file inside a backup that holds the board itself.
  static const String _manifestName = 'cards.json';

  /// Media a backup is allowed to carry. Anything else is skipped.
  static const Set<String> mediaExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.m4a',
  };

  static const Uuid _uuid = Uuid();

  /// The board a first run starts with.
  static List<TalkCard> defaultCards() => [
    TalkCard(
      id: _uuid.v4(),
      label: 'Hungry',
      kind: CardMediaKind.asset,
      content: 'assets/symbols/dinner.svg',
      colorValue: CardPalette.food,
    ),
    TalkCard(
      id: _uuid.v4(),
      label: 'Thirsty',
      kind: CardMediaKind.asset,
      content: 'assets/symbols/water.svg',
      colorValue: CardPalette.drink,
    ),
    TalkCard(
      id: _uuid.v4(),
      label: 'Play',
      kind: CardMediaKind.asset,
      content: 'assets/symbols/lego.svg',
      colorValue: CardPalette.play,
    ),
  ];

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

  Future<void> save(List<TalkCard> cards) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      json.encode(cards.map((c) => c.toJson()).toList()),
    );
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
    final http.Response response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final Directory dir = await getApplicationDocumentsDirectory();
    final String path = p.join(dir.path, '${_uuid.v4()}.gif');
    await File(path).writeAsBytes(response.bodyBytes);
    return path;
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

  /// Writes a zip holding the board and every media file it points at, and
  /// returns its path.
  ///
  /// The zip and its manifest go to a temporary directory, so a second backup
  /// never packs the first one.
  Future<String> exportBackup(List<TalkCard> cards) async {
    final Directory staging = await Directory(
      p.join((await getTemporaryDirectory()).path, 'backup'),
    ).create(recursive: true);

    final File manifest = File(p.join(staging.path, _manifestName));
    await manifest.writeAsString(
      json.encode(cards.map((c) => c.toJson()).toList()),
    );

    final String zipPath = p.join(staging.path, 'toddler_talk_backup.zip');
    final ZipFileEncoder encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addFile(manifest);

    // Pack only the media the board actually references, so a stale file from
    // a deleted card does not travel with the backup.
    for (final String path in _referencedMedia(cards)) {
      final File file = File(path);
      if (await file.exists()) await encoder.addFile(file);
    }
    await encoder.close();
    await manifest.delete();
    return zipPath;
  }

  Iterable<String> _referencedMedia(List<TalkCard> cards) => cards
      .expand((c) => [if (c.kind == CardMediaKind.file) c.content, c.audioPath])
      .whereType<String>();

  /// Unpacks a backup and returns the board it holds.
  ///
  /// Media lands in the app's documents directory, and every card's paths are
  /// rewritten to point there. The paths inside a backup belong to the device
  /// that wrote it, so a restore onto a second device needs the rewrite to
  /// find its pictures at all.
  Future<List<TalkCard>> importBackup(File zip) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final Archive archive = ZipDecoder().decodeBytes(await zip.readAsBytes());

    String? manifest;
    for (final ArchiveFile entry in archive) {
      if (!entry.isFile) continue;

      // A zip may name an entry `../../elsewhere`. Keep the base name only, so
      // an entry can never write outside the app's own directory.
      final String name = p.basename(entry.name);
      if (name.isEmpty || name == '.' || name == '..') continue;

      if (name == _manifestName) {
        manifest = utf8.decode(entry.readBytes() ?? const []);
        continue;
      }
      if (!mediaExtensions.contains(p.extension(name).toLowerCase())) continue;

      await File(p.join(dir.path, name)).writeAsBytes(entry.readBytes() ?? []);
    }

    if (manifest == null) {
      throw const BackupException('That file is not a Toddler Talk backup.');
    }

    final List<TalkCard> cards = decode(
      manifest,
    ).map((c) => _rehomeMedia(c, dir.path)).toList();
    await save(cards);
    return cards;
  }

  TalkCard _rehomeMedia(TalkCard card, String dirPath) => card.copyWith(
    content: card.kind == CardMediaKind.file
        ? p.join(dirPath, p.basename(card.content))
        : card.content,
    audioPath: card.audioPath == null
        ? null
        : p.join(dirPath, p.basename(card.audioPath!)),
  );
}
