import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toddler_talk_aac/data/card_repository.dart';
import 'package:toddler_talk_aac/models/talk_card.dart';
import 'package:toddler_talk_aac/theme.dart';

/// Restore used to write every zip entry straight to the app directory under
/// the name the zip carried, and to keep the paths of the device that wrote the
/// backup, so a restore onto a second device found none of its pictures.
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

  group('importBackup', () {
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

      final List<TalkCard> restored = await repository.importBackup(zip);

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

      final List<TalkCard> restored = await repository.importBackup(zip);

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
        Directory(
          p.dirname(await repository.exportBackup(const [])),
        ).listSync().map((e) => p.basename(e.path)),
        isNot(contains('cards.json')),
      );
    });
  });
}
