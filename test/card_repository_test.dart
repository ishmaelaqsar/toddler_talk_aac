import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toddler_talk_aac/data/card_repository.dart';
import 'package:toddler_talk_aac/models/board_page.dart';
import 'package:toddler_talk_aac/models/board_settings.dart';
import 'package:toddler_talk_aac/models/talk_card.dart';
import 'package:toddler_talk_aac/theme.dart';

/// Restore used to write every zip entry straight to the app directory under
/// the name the zip carried, and to keep the paths of the device that wrote the
/// backup, so a restore onto a second device found none of its pictures. A zip
/// with no board wrote its pictures anyway. A restore left the old board's
/// files on the device. A GIF download had no time limit, and it threw when
/// the device was offline. A backup had no place for pages or settings. Every
/// backup had the same file name. A board the app could not read had no way
/// back that kept a copy of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory temporary;
  late CardRepository repository;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('tt_docs');
    temporary = Directory.systemTemp.createTempSync('tt_tmp');
    repository = CardRepository();
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getTemporaryDirectory'
              ? temporary.path
              : documents.path,
        );
  });

  tearDown(() {
    documents.deleteSync(recursive: true);
    temporary.deleteSync(recursive: true);
  });

  File writeZip(Map<String, List<int>> entries) {
    final Archive archive = Archive();
    entries.forEach(
      (name, bytes) => archive.add(ArchiveFile.bytes(name, bytes)),
    );
    final File zip = File(p.join(temporary.path, 'backup.zip'));
    zip.writeAsBytesSync(ZipEncoder().encode(archive));
    return zip;
  }

  List<int> asJson(List<TalkCard> cards) =>
      utf8.encode(json.encode(cards.map((c) => c.toJson()).toList()));

  group('decode', () {
    test('an older record with no visibility flag counts as visible', () {
      final List<TalkCard> cards = repository.decode(
        json.encode([
          {
            'id': 'a',
            'label': 'Cup',
            'type': 'asset',
            'content': 'assets/symbols/water.svg',
          },
        ]),
      );

      expect(cards.single.isVisible, isTrue);
      expect(cards.single.colorValue, CardPalette.fallback);
      expect(cards.single.audioPath, isNull);
    });

    test('a round trip keeps every field', () {
      const TalkCard card = TalkCard(
        id: 'a',
        label: 'Mummy',
        kind: CardMediaKind.file,
        content: '/docs/face.jpg',
        audioPath: '/docs/mummy.m4a',
        colorValue: CardPalette.people,
        isVisible: false,
      );

      final TalkCard restored = repository
          .decode(json.encode([card.toJson()]))
          .single;

      expect(restored.id, card.id);
      expect(restored.label, card.label);
      expect(restored.kind, card.kind);
      expect(restored.content, card.content);
      expect(restored.audioPath, card.audioPath);
      expect(restored.colorValue, card.colorValue);
      expect(restored.isVisible, card.isVisible);
    });

    test('speech text survives a round trip', () {
      const TalkCard card = TalkCard(
        id: 'a',
        label: 'Milk',
        kind: CardMediaKind.asset,
        content: 'assets/symbols/milk.svg',
        speech: 'I want milk, please',
      );

      final TalkCard restored = repository
          .decode(json.encode([card.toJson()]))
          .single;

      expect(restored.speech, 'I want milk, please');
      expect(restored.spokenText, 'I want milk, please');
    });

    test('an older record has no speech text, so it says its label', () {
      final TalkCard card = repository
          .decode(
            json.encode([
              {'id': 'a', 'label': 'Cup', 'type': 'asset', 'content': 'c.svg'},
            ]),
          )
          .single;

      expect(card.speech, isNull);
      expect(card.spokenText, 'Cup');
    });

    test('one unreadable record does not cost the parent the whole board', () {
      final List<TalkCard> cards = repository.decode(
        json.encode([
          {'label': 'no id at all'},
          {'id': 'b', 'label': 'Ball', 'type': 'asset', 'content': 'b.svg'},
        ]),
      );

      expect(cards.map((c) => c.label), ['Ball']);
    });
  });

  group('defaultCards', () {
    test('a first run gets 12 cards with distinct labels', () {
      expect(CardRepository.defaultCards().map((c) => c.label), [
        'Hungry',
        'Thirsty',
        'Milk',
        'Play',
        'Nappy',
        'Potty',
        'Sleepy',
        'Bath',
        'Outside',
        'Hug',
        'Book',
        'Music',
      ]);
    });

    test('each default card names a symbol that is bundled', () {
      for (final TalkCard card in CardRepository.defaultCards()) {
        expect(card.kind, CardMediaKind.asset, reason: card.label);
        expect(card.content, startsWith('assets/symbols/'), reason: card.label);
        expect(File(card.content).existsSync(), isTrue, reason: card.label);
      }
    });
  });

  group('pages', () {
    test('pages survive a round trip', () async {
      await repository.savePages(const [
        BoardPage(id: 'home', name: 'Home'),
        BoardPage(id: 'food', name: 'Food', symbol: 'assets/symbols/milk.svg'),
      ]);

      final List<BoardPage> pages = await CardRepository().loadPages();

      expect(pages.map((page) => page.id), ['home', 'food']);
      expect(pages.map((page) => page.name), ['Home', 'Food']);
      expect(pages.map((page) => page.symbol), [
        null,
        'assets/symbols/milk.svg',
      ]);
    });

    test('no stored pages, or pages that cannot be read, load as one Home '
        'page', () async {
      for (final Map<String, Object> stored in [
        <String, Object>{},
        {CardRepository.pagesKey: '[]'},
        {CardRepository.pagesKey: 'not json'},
      ]) {
        SharedPreferences.setMockInitialValues(stored);

        final List<BoardPage> pages = await CardRepository().loadPages();

        expect(pages.map((page) => (page.id, page.name)), [
          ('home', 'Home'),
        ], reason: '$stored');
      }
    });

    test('a card record with no page key lands on the first page', () {
      final TalkCard card = repository
          .decode(
            json.encode([
              {'id': 'a', 'label': 'Cup', 'type': 'asset', 'content': 'c.svg'},
            ]),
          )
          .single;

      expect(card.pageId, isNull);
      expect(
        pageIdOf(card, const [
          BoardPage(id: 'food', name: 'Food'),
          BoardPage(id: 'home', name: 'Home'),
        ]),
        'food',
      );
    });
  });

  group('importBackup', () {
    test('a backup round trip keeps pages, card pages, and settings', () async {
      final String zipPath = await repository.exportBackup(
        const [
          TalkCard(
            id: 'a',
            label: 'Apple',
            kind: CardMediaKind.asset,
            content: 'assets/symbols/dinner.svg',
            pageId: 'food',
          ),
        ],
        pages: const [
          BoardPage(id: 'home', name: 'Home'),
          BoardPage(id: 'food', name: 'Food'),
        ],
        settings: const BoardSettings(
          voice: SpeechVoice.american,
          cardSize: CardSize.large,
        ),
      );

      final Backup backup = await CardRepository().importBackup(File(zipPath));

      expect(backup.pages.map((page) => page.name), ['Home', 'Food']);
      expect(backup.cards.single.pageId, 'food');
      expect(backup.settings?.voice, SpeechVoice.american);
      expect(backup.settings?.cardSize, CardSize.large);
      // Saved, so the restore survives a restart.
      expect((await repository.loadPages()).map((page) => page.name), [
        'Home',
        'Food',
      ]);
      expect((await repository.loadSettings()).cardSize, CardSize.large);
    });

    test('a backup with only cards.json restores as one page and keeps the '
        'device settings', () async {
      await repository.savePages(const [
        BoardPage(id: 'home', name: 'Home'),
        BoardPage(id: 'food', name: 'Food'),
      ]);
      await repository.saveSettings(const BoardSettings(slow: true));

      final Backup backup = await repository.importBackup(
        writeZip({
          'cards.json': asJson(const [
            TalkCard(
              id: 'a',
              label: 'Apple',
              kind: CardMediaKind.asset,
              content: 'assets/symbols/dinner.svg',
            ),
          ]),
        }),
      );

      expect(backup.settings, isNull);
      expect(backup.pages.map((page) => page.id), ['home']);
      expect((await repository.loadPages()).map((page) => page.id), ['home']);
      expect((await repository.loadSettings()).slow, isTrue);
    });

    test('an entry that escapes the app directory is not written', () async {
      final File zip = writeZip({
        CardRepository.storageKey: const [],
        'cards.json': asJson(const []),
        '../escape.png': const [1, 2, 3],
      });

      await repository.importBackup(zip);

      expect(
        File(p.join(documents.parent.path, 'escape.png')).existsSync(),
        isFalse,
      );
      // Kept, under a name that cannot leave the app's own directory.
      expect(File(p.join(documents.path, 'escape.png')).existsSync(), isTrue);
    });

    test('media paths are rewritten to this device', () async {
      const TalkCard card = TalkCard(
        id: 'a',
        label: 'Mummy',
        kind: CardMediaKind.file,
        // The path of whichever device wrote the backup.
        content: '/data/user/0/other.app/files/face.jpg',
        audioPath: '/data/user/0/other.app/files/mummy.m4a',
      );

      final File zip = writeZip({
        'cards.json': asJson([card]),
        'face.jpg': const [1],
        'mummy.m4a': const [2],
      });

      final List<TalkCard> restored = (await repository.importBackup(zip))
          .cards;

      expect(restored.single.content, p.join(documents.path, 'face.jpg'));
      expect(restored.single.audioPath, p.join(documents.path, 'mummy.m4a'));
      expect(File(restored.single.content).existsSync(), isTrue);
      expect(File(restored.single.audioPath!).existsSync(), isTrue);
    });

    test('a bundled symbol keeps its asset key', () async {
      const TalkCard card = TalkCard(
        id: 'a',
        label: 'Thirsty',
        kind: CardMediaKind.asset,
        content: 'assets/symbols/water.svg',
      );
      final File zip = writeZip({
        'cards.json': asJson([card]),
      });

      final List<TalkCard> restored = (await repository.importBackup(zip))
          .cards;

      expect(restored.single.content, 'assets/symbols/water.svg');
    });

    test('a zip that is not a backup says so', () async {
      final File zip = writeZip({
        'holiday.png': const [1, 2],
      });

      expect(
        () => repository.importBackup(zip),
        throwsA(isA<BackupException>()),
      );
    });

    test('a zip with no manifest writes no file', () async {
      final File zip = writeZip({
        'holiday.png': const [1, 2],
      });

      await expectLater(
        repository.importBackup(zip),
        throwsA(isA<BackupException>()),
      );
      expect(documents.listSync(), isEmpty);
    });

    test('a restored board is saved, so it survives a restart', () async {
      const TalkCard card = TalkCard(
        id: 'a',
        label: 'Ball',
        kind: CardMediaKind.asset,
        content: 'assets/symbols/lego.svg',
      );
      await repository.importBackup(
        writeZip({
          'cards.json': asJson([card]),
        }),
      );

      expect((await repository.load()).single.label, 'Ball');
    });
  });

  group('exportBackup', () {
    test('it packs the board and the media the board points at', () async {
      final File used = File(p.join(documents.path, 'used.jpg'))
        ..writeAsBytesSync(const [1]);
      File(p.join(documents.path, 'orphan.jpg')).writeAsBytesSync(const [2]);

      final String zipPath = await repository.exportBackup([
        TalkCard(
          id: 'a',
          label: 'Ball',
          kind: CardMediaKind.file,
          content: used.path,
        ),
      ]);

      final Archive archive = ZipDecoder().decodeBytes(
        File(zipPath).readAsBytesSync(),
      );
      final List<String> names = archive.files.map((f) => f.name).toList();
      expect(names, contains('cards.json'));
      expect(names, contains('used.jpg'));
      // A file left behind by a deleted card does not travel with the backup.
      expect(names, isNot(contains('orphan.jpg')));
    });

    test(
      'the zip lands outside the app directory, so it never packs itself',
      () async {
        final String first = await repository.exportBackup(const []);
        expect(p.isWithin(documents.path, first), isFalse);

        final String second = await repository.exportBackup(const []);
        final Archive archive = ZipDecoder().decodeBytes(
          File(second).readAsBytesSync(),
        );
        expect(
          archive.files.map((f) => f.name),
          isNot(contains(p.basename(first))),
        );
      },
    );

    test('the manifest is not left behind', () async {
      await repository.exportBackup(const []);

      expect(
        Directory(p.dirname(await repository.exportBackup(const [])))
            .listSync()
            .map((e) => p.basename(e.path)),
        isNot(contains('cards.json')),
      );
    });

    test('the file name carries the date', () async {
      final String zipPath = await repository.exportBackup(const []);

      expect(
        p.basename(zipPath),
        matches(RegExp(r'^toddler_talk_backup_\d{4}-\d{2}-\d{2}\.zip$')),
      );
    });

    // Each zip holds every photo, and a zip from another day has another
    // name, so nothing would overwrite it.
    test('a backup from an earlier day does not stay behind', () async {
      final String first = await repository.exportBackup(const []);
      final File older = File(
        p.join(p.dirname(first), 'toddler_talk_backup_2000-01-01.zip'),
      );
      File(first).renameSync(older.path);

      await repository.exportBackup(const []);

      expect(older.existsSync(), isFalse);
    });
  });

  group('startNewBoard', () {
    test(
      'it keeps the board it cannot read, then saves the starter board',
      () async {
        SharedPreferences.setMockInitialValues({
          CardRepository.storageKey: 'not json',
        });
        await expectLater(repository.load(), throwsFormatException);

        await repository.startNewBoard();

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(CardRepository.rescueKey), 'not json');
        expect(
          (await repository.load()).map((c) => c.label),
          CardRepository.defaultCards().map((c) => c.label),
        );
      },
    );
  });

  group('deleteReplacedMedia', () {
    File appFile(String name) =>
        File(p.join(documents.path, name))..writeAsBytesSync(const [1]);

    TalkCard photoCard(String path, {String? audioPath}) => TalkCard(
      id: 'a',
      label: 'Mummy',
      kind: CardMediaKind.file,
      content: path,
      audioPath: audioPath,
    );

    test('a file only the replaced board used is deleted', () async {
      final File photo = appFile('face.jpg');
      final File voice = appFile('mummy.m4a');

      await repository.deleteReplacedMedia([
        photoCard(photo.path, audioPath: voice.path),
      ], const []);

      expect(photo.existsSync(), isFalse);
      expect(voice.existsSync(), isFalse);
    });

    test('a file the restored board points at is kept', () async {
      // A backup made on this device names the same files as the board it
      // replaces.
      final File photo = appFile('face.jpg');

      await repository.deleteReplacedMedia(
        [photoCard(photo.path)],
        [photoCard(photo.path)],
      );

      expect(photo.existsSync(), isTrue);
    });

    test('a file outside the app directory is left alone', () async {
      final File theirs = File(p.join(temporary.path, 'theirs.jpg'))
        ..writeAsBytesSync(const [1]);

      await repository.deleteReplacedMedia([photoCard(theirs.path)], const []);

      expect(theirs.existsSync(), isTrue);
    });
  });

  group('downloadGif', () {
    const String url = 'https://media.giphy.com/media/a/giphy.gif';

    test('an offline device gets null, not an error', () async {
      final CardRepository offline = CardRepository(
        client: MockClient((request) => throw const SocketException('offline')),
      );

      expect(await offline.downloadGif(url), isNull);
    });

    test('a failed response gets null', () async {
      final CardRepository failing = CardRepository(
        client: MockClient((request) async => http.Response('', 404)),
      );

      expect(await failing.downloadGif(url), isNull);
    });

    test('a GIF lands in the app directory', () async {
      final CardRepository online = CardRepository(
        client: MockClient(
          (request) async => http.Response.bytes(const [1, 2, 3], 200),
        ),
      );

      final String? path = await online.downloadGif(url);

      expect(p.isWithin(documents.path, path!), isTrue);
      expect(p.extension(path), '.gif');
      expect(File(path).readAsBytesSync(), const [1, 2, 3]);
    });

    // The parent waits behind a scrim while the GIF saves.
    testWidgets('a download that never answers gives up', (tester) async {
      final CardRepository stalled = CardRepository(
        client: MockClient((request) => Completer<http.Response>().future),
      );

      final Future<String?> path = stalled.downloadGif(url);
      await tester.pump(const Duration(seconds: 16));

      expect(await path, isNull);
    });
  });
}
