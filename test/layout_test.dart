import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/models/board_settings.dart';
import 'package:toddler_talk_aac/theme.dart';
import 'package:toddler_talk_aac/widgets/card_tile.dart';

import 'test_harness.dart';

/// The old board fixed the card label at 20 logical pixels inside a quarter of
/// a square card, and chose two or three columns off a single 600px threshold.
/// It overflowed at a large text scale, and it wasted a tablet in landscape.
/// Each photo card decoded its picture at full camera resolution. Every card
/// had one fixed size, and every card sat on one page. A square or portrait
/// photo sat in the middle of its card, with the card colour on both sides.
void main() {
  const Map<String, Size> viewports = {
    'small phone portrait': Size(320, 568),
    'small phone landscape': Size(568, 320),
    'tablet portrait': Size(800, 1280),
    'tablet landscape': Size(1280, 800),
  };

  List<Map<String, dynamic>> cards() => [
    storedCard(id: 'a', label: 'Cup'),
    storedCard(id: 'b', label: 'A very long card label indeed, and then some'),
    storedCard(id: 'c', label: 'Ball'),
  ];

  /// The first card shows at least a touch target's height above the bottom
  /// edge, under the app bar, the banner, and the tabs.
  void expectBoardRoom(WidgetTester tester, Size screen) {
    final Rect card = tester.getRect(find.byType(CardTile).first);
    expect(
      screen.height - card.top,
      greaterThanOrEqualTo(AppTokens.minTouchTarget),
    );
  }

  for (final CardSize cardSize in CardSize.values) {
    for (final MapEntry<String, Size> viewport in viewports.entries) {
      for (final double scale in [1.0, 1.5, 2.0]) {
        testWidgets('${viewport.key} at text scale $scale with '
            '${cardSize.name} cards does not overflow', (tester) async {
          installMocks(
            storedCards: cards(),
            storedSettings: BoardSettings(cardSize: cardSize).toJson(),
          );
          await pumpApp(tester, size: viewport.value, textScale: scale);
          expect(tester.takeException(), isNull);

          // Parent mode adds the edit row, which is where a card runs out of
          // room first.
          await enterParentMode(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('the parent gate holds on a small phone at text scale 2.0', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);
    await holdLock(tester);
    expect(tester.takeException(), isNull);

    // Each key scrolls into reach, and stays a full touch target.
    for (int digit = 1; digit <= 9; digit++) {
      await tester.ensureVisible(gateKey(digit));
      await tester.pumpAndSettle();
      final Size key = tester.getSize(
        find.ancestor(
          of: gateKey(digit),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(key.width, greaterThanOrEqualTo(AppTokens.minTouchTarget));
      expect(key.height, greaterThanOrEqualTo(AppTokens.minTouchTarget));
    }
    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await solveParentGate(tester);
    expect(find.text('Grown-ups only'), findsNothing);
  });

  testWidgets('the settings sheet holds on a small phone at text scale 2.0', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);
    await enterParentMode(tester);
    await openSettings(tester);
    expect(tester.takeException(), isNull);

    // The last control scrolls into reach.
    await tester.ensureVisible(find.text('Hear it'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final MapEntry<String, Size> viewport in viewports.entries) {
    for (final double scale in [1.0, 1.5, 2.0]) {
      testWidgets('${viewport.key} at text scale $scale with three pages does '
          'not overflow, and the board keeps its room', (tester) async {
        installMocks(
          storedCards: [
            storedCard(id: 'a', label: 'Cup', pageId: 'home'),
            storedCard(
              id: 'b',
              label: 'A very long card label indeed, and then some',
              pageId: 'home',
            ),
            storedCard(id: 'c', label: 'Apple', pageId: 'food'),
            storedCard(id: 'd', label: 'Ball', pageId: 'outside'),
          ],
          storedPages: [
            storedPage('home', 'Home', symbol: 'assets/symbols/hug_,_to.svg'),
            storedPage('food', 'Food', symbol: 'assets/symbols/dinner.svg'),
            storedPage('outside', 'Things to do outside in the garden'),
          ],
        );
        await pumpApp(tester, size: viewport.value, textScale: scale);
        expect(tester.takeException(), isNull);
        expectBoardRoom(tester, viewport.value);

        // Parent mode adds the banner above the tabs.
        await enterParentMode(tester);
        expect(tester.takeException(), isNull);
        expectBoardRoom(tester, viewport.value);
      });
    }
  }

  testWidgets('the board fits more cards across a wider screen', (
    tester,
  ) async {
    installMocks(storedCards: cards());

    await pumpApp(tester, size: const Size(320, 568));
    final double onPhone = tester.getSize(find.byType(CardTile).first).width;

    await pumpApp(tester, size: const Size(1280, 800));
    final double onTablet = tester.getSize(find.byType(CardTile).first).width;

    // A card stays about the same size, rather than growing to fill a tablet.
    expect(onTablet, lessThan(onPhone * 2));
    expect(onTablet, greaterThan(100));
  });

  testWidgets('a photo is decoded near the size it is drawn at', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester);

    final Finder tile = find.byType(CardTile).first;
    final ImageProvider provider = tester
        .widget<Image>(find.descendant(of: tile, matching: find.byType(Image)))
        .image;

    // A 12 MP camera photo decoded in full takes about 48 MB.
    expect(provider, isA<ResizeImage>());
    final ResizeImage resized = provider as ResizeImage;
    // Fit, not exact, so the photo keeps its shape.
    expect(resized.policy, ResizeImagePolicy.fit);
    // Twice the tile, so a wide photo covers it too.
    expect(resized.width, greaterThanOrEqualTo(2 * tester.getSize(tile).width));
  });

  testWidgets('a square photo and a portrait photo fill the width of their '
      'card', (tester) async {
    installMocks();
    // A missing file shows a placeholder that fills the card anyway, so the
    // photos must be real ones that decode.
    Future<String> writePhoto(String name, int width, int height) async {
      final File file = File('${appDocuments.path}/$name');
      await tester.runAsync(() async {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF336699), BlendMode.src);
        final ui.Image image = await recorder.endRecording().toImage(
          width,
          height,
        );
        final ByteData? png = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await file.writeAsBytes(png!.buffer.asUint8List());
      });
      return file.path;
    }

    installMocks(
      storedCards: [
        storedCard(
          id: 'a',
          label: 'Square',
          content: await writePhoto('square.png', 200, 200),
        ),
        storedCard(
          id: 'b',
          label: 'Portrait',
          content: await writePhoto('portrait.png', 200, 400),
        ),
      ],
    );
    await pumpApp(tester);
    // A file read and a decode finish only in real time.
    bool decoded() => tester
        .renderObjectList<RenderImage>(find.byType(RawImage))
        .every((image) => image.image != null);
    for (int round = 0; round < 50 && !decoded(); round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    for (final String label in ['Square', 'Portrait']) {
      final Finder card = find.widgetWithText(CardTile, label);
      final Finder photo = find.descendant(
        of: card,
        matching: find.byType(RawImage),
      );
      expect(
        tester.renderObject<RenderImage>(photo).image,
        isNotNull,
        reason: '$label decodes',
      );
      expect(
        tester.getSize(photo).width,
        tester.getSize(card).width,
        reason: label,
      );
    }
  });

  testWidgets('a card stays a large touch target at every text scale', (
    tester,
  ) async {
    for (final double scale in [1.0, 1.5, 2.0]) {
      installMocks(storedCards: cards());
      await pumpApp(tester, size: const Size(320, 568), textScale: scale);

      final Size size = tester.getSize(find.byType(CardTile).first);
      expect(
        size.shortestSide,
        greaterThanOrEqualTo(AppTokens.minTouchTarget),
        reason: 'text scale $scale',
      );
    }
  });

  testWidgets('the label survives a long word instead of overflowing', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);

    // Rendered, clipped by the band, and no overflow exception.
    expect(
      find.textContaining('A very long card label', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picture keeps room even when the label is huge', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);

    final Size card = tester.getSize(find.byType(CardTile).first);
    final Size label = tester.getSize(
      find.descendant(
        of: find.byType(CardTile).first,
        matching: find.byType(ColoredBox),
      ),
    );
    expect(label.height, lessThanOrEqualTo(card.height * 0.61));
  });

  testWidgets('an empty board holds up on a small screen at scale 2.0', (
    tester,
  ) async {
    installMocks(storedCards: const []);
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);
    expect(tester.takeException(), isNull);

    await enterParentMode(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('The board is empty'), findsOneWidget);
  });

  testWidgets('the parent-mode banner leaves the board its room', (
    tester,
  ) async {
    installMocks(storedCards: cards());
    await pumpApp(tester, size: const Size(320, 568), textScale: 2.0);
    await enterParentMode(tester);

    // The banner used to wrap until it claimed the whole screen.
    expect(find.byType(CardTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
