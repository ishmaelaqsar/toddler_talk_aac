import '../theme.dart';

/// What a card shows.
enum CardMediaKind {
  /// An SVG bundled under `assets/symbols/`.
  asset,

  /// A photo, or a GIF, stored in the app's documents directory.
  file,

  /// A literal string, drawn large. Kept because early records used it.
  emoji,
}

/// One card on the board.
///
/// Records already on a device use the `toddler_cards_v5` shape, so
/// [TalkCard.fromJson] reads that shape and [toJson] writes it back unchanged.
class TalkCard {
  const TalkCard({
    required this.id,
    required this.label,
    required this.kind,
    required this.content,
    this.audioPath,
    this.colorValue = CardPalette.fallback,
    this.isVisible = true,
  });

  final String id;
  final String label;
  final CardMediaKind kind;

  /// An asset key, a file path, or the literal text, per [kind].
  final String content;

  /// A parent's own recording. Played instead of text-to-speech when present.
  final String? audioPath;

  final int colorValue;

  /// False hides the card from the child while keeping it, and its recording,
  /// on disk. A parent sees it dimmed in parent mode.
  final bool isVisible;

  static const Map<String, CardMediaKind> _kindNames = {
    'asset': CardMediaKind.asset,
    'image': CardMediaKind.file,
    'emoji': CardMediaKind.emoji,
  };

  factory TalkCard.fromJson(Map<String, dynamic> json) => TalkCard(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    kind: _kindNames[json['type']] ?? CardMediaKind.emoji,
    content: json['content'] as String? ?? '',
    audioPath: json['audioPath'] as String?,
    // An older record may carry neither a colour nor a visibility flag.
    colorValue: json['color'] as int? ?? CardPalette.fallback,
    isVisible: json['isVisible'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': _kindNames.entries.firstWhere((e) => e.value == kind).key,
    'content': content,
    'audioPath': audioPath,
    'color': colorValue,
    'isVisible': isVisible,
  };

  TalkCard copyWith({
    String? label,
    CardMediaKind? kind,
    String? content,
    String? audioPath,
    bool clearAudio = false,
    int? colorValue,
    bool? isVisible,
  }) => TalkCard(
    id: id,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    content: content ?? this.content,
    audioPath: clearAudio ? null : (audioPath ?? this.audioPath),
    colorValue: colorValue ?? this.colorValue,
    isVisible: isVisible ?? this.isVisible,
  );
}
