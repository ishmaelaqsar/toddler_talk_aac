import 'package:material_ui/material_ui.dart';

/// Colour and metric tokens for the whole app.
///
/// Every colour lives here. Widgets read them through [Theme.of] or through the
/// static members below, so a palette change is a one-file change.
abstract final class AppTokens {
  /// Sky blue. The app's identity colour, and the seed for the scheme.
  static const Color seed = Color(0xFF81D4FA);

  /// The page behind the cards. Warm cream, so a pale card still reads as
  /// raised.
  static const Color canvas = Color(0xFFFFFDE7);

  /// Raised surfaces: the app bar, dialogs, and the symbol sheet.
  static const Color surface = Color(0xFFFFFFFF);

  /// Card and sheet outlines.
  static const Color outline = Color(0xFFBCC3C7);

  /// Body text. Also the card label.
  static const Color ink = Color(0xFF1A1A17);

  /// Hint and secondary text. Reaches 6.2:1 on [canvas].
  static const Color inkMuted = Color(0xFF5A5F62);

  /// Interactive controls: buttons, the add action, and a focus ring.
  /// Reaches 6.7:1 on [surface].
  static const Color action = Color(0xFF00637D);

  /// Text and icons drawn on top of [action].
  static const Color onAction = Color(0xFFFFFFFF);

  /// Destructive actions.
  static const Color danger = Color(0xFFB3261E);

  /// The parent-mode banner and its lock indicator.
  static const Color parentMode = Color(0xFF8A4B00);

  /// Text and icons drawn on top of [parentMode].
  static const Color onParentMode = Color(0xFFFFFFFF);

  /// The card border drawn while parent mode is on, so an editable card is
  /// obvious at a glance.
  static const Color editableBorder = Color(0xFF8A4B00);

  /// The ring on the card whose sound plays, so the child sees which card
  /// speaks. Reaches 7.3:1 on the darkest card fill. [action] reaches only
  /// 2.9:1 there.
  static const Color speakingRing = ink;

  /// The toggle that hides a card from the child without deleting it.
  static const Color hidden = Color(0xFF5A5F62);

  /// Dims the screen while a backup or a restore runs.
  static const Color scrim = Color(0x99000000);

  /// The band that carries a card's label, over the card fill.
  static const Color labelBand = Color(0xEBFFFFFF);

  /// The plate behind a symbol in the picker.
  static const Color symbolPlate = Color(0xFFF1F3F4);

  /// The drop shadow that lifts a card off the page.
  static const Color cardShadow = Color(0x1A000000);

  /// The minimum touch target, per the Material accessibility guideline.
  static const double minTouchTarget = 48.0;

  static const double editableBorderWidth = 3.0;

  /// The lift of a card while a parent drags it.
  static const double dragElevation = 3.0;

  /// Wider than [editableBorderWidth], so the ring reads at a glance. It does
  /// not move, so it does not pull the eye away from the picture.
  static const double speakingRingWidth = 4.0;

  /// The minimum height of a page tab. Larger than [minTouchTarget], because a
  /// toddler taps it.
  static const double tabMinHeight = 64.0;

  /// The widest a page tab grows. A longer name ends in an ellipsis, so the
  /// next tab shows at the edge and the row reads as one that scrolls.
  static const double tabMaxWidth = 240.0;

  static const double tabSymbolSize = 32.0;

  /// The height of a key on the parent gate. Its width is a third of the
  /// dialog.
  static const double gateKeySize = 64.0;

  /// The border of the open tab. Thicker than the others, so the open tab
  /// differs in shape as well as in colour.
  static const double tabOpenBorder = 3.0;

  /// The target width of one symbol in the picker. Smaller than a card,
  /// because the picker is a parent-facing browse list.
  static const double symbolExtent = 120.0;

  /// The unscaled size of a card label.
  static const double labelSize = 20.0;

  /// The share of a card's height the label band may take at a large text
  /// scale. Above this the label ellipsizes, so the picture never vanishes.
  static const double labelBandMaxFraction = 0.6;

  /// How long a parent holds the lock to reach parent mode. Long enough that a
  /// toddler's idle press does not open it.
  static const Duration unlockHold = Duration(milliseconds: 1500);

  /// A recording stops itself after this long. A card says a word or a short
  /// phrase.
  static const Duration recordingLimit = Duration(seconds: 10);

  /// The parent gate closes itself after this long with no key, so a child
  /// who reaches it gets the board back.
  static const Duration gateTimeout = Duration(seconds: 10);

  /// Parent mode returns to toddler mode after this much inactivity.
  static const Duration parentModeTimeout = Duration(seconds: 60);

  static const double cardRadius = 24.0;
  static const double sheetRadius = 16.0;
  static const double gap = 16.0;
}

/// The card sizes a parent can choose from.
///
/// Each [extent] is the target width of one card. The grid fits as many as it
/// can, so a card stays a large motor target on a phone and on a tablet alike.
enum CardSize {
  small(180),
  medium(260),
  large(400);

  const CardSize(this.extent);

  final double extent;
}

abstract final class AppTheme {
  static ThemeData build() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppTokens.seed,
      primary: AppTokens.action,
      onPrimary: AppTokens.onAction,
      surface: AppTokens.surface,
      error: AppTokens.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppTokens.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.surface,
        foregroundColor: AppTokens.ink,
        elevation: 1,
        centerTitle: false,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        thickness: 1,
        space: 1,
        color: AppTokens.outline,
      ),
      textTheme: const TextTheme(
        // The card label. Widgets scale it with the viewer's text scale.
        titleMedium: TextStyle(
          fontSize: AppTokens.labelSize,
          fontWeight: FontWeight.bold,
          color: AppTokens.ink,
        ),
        bodyMedium: TextStyle(fontSize: 16, color: AppTokens.ink),
        bodySmall: TextStyle(fontSize: 13, color: AppTokens.inkMuted),
      ),
    );
  }
}

/// Fills for the cards, kept pale so the picture on top stays legible.
///
/// Stored as `int` because a card's colour round-trips through JSON.
abstract final class CardPalette {
  static const int food = 0xFFFFCC80;
  static const int drink = 0xFF81D4FA;
  static const int play = 0xFFA5D6A7;
  static const int people = 0xFFCE93D8;
  static const int feelings = 0xFFFFAB91;
  static const int neutral = 0xFFECEFF1;

  /// Offered in the card editor, in this order.
  static const List<int> choices = [
    neutral,
    food,
    drink,
    play,
    people,
    feelings,
  ];

  /// Fallback fill for a card whose stored colour is missing.
  static const int fallback = neutral;
}
