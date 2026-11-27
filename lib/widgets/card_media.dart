import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/talk_card.dart';
import '../theme.dart';

/// Draws whatever a card shows: a bundled symbol, a photo or GIF, or text.
///
/// Every branch has a visible fallback, so a missing file shows a clear
/// placeholder instead of an empty box the parent cannot explain.
class CardMedia extends StatelessWidget {
  const CardMedia({
    super.key,
    required this.card,
    this.padding,
    this.drawnExtent,
  });

  final TalkCard card;

  /// Inset around a symbol. A photo fills the card instead.
  final EdgeInsets? padding;

  /// The longest side the picture is drawn at, in logical pixels. A photo
  /// decodes near this size. Without it, a photo decodes in full.
  ///
  /// The caller measures, because a [LayoutBuilder] here breaks a dialog,
  /// which asks its content for an intrinsic size first.
  final double? drawnExtent;

  @override
  Widget build(BuildContext context) {
    // The tile already announces the card's label, so the picture itself adds
    // nothing a screen reader needs to hear.
    return ExcludeSemantics(child: _media(context));
  }

  Widget _media(BuildContext context) {
    switch (card.kind) {
      case CardMediaKind.asset:
        return Padding(
          padding: padding ?? const EdgeInsets.all(AppTokens.gap),
          child: SvgPicture.asset(
            card.content,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => const _MissingMedia(),
          ),
        );
      case CardMediaKind.file:
        // Image plays an animated GIF without extra work. A resize keeps the
        // animation.
        return Image(
          image: _decodeNearDrawnSize(
            FileImage(File(card.content)),
            drawnExtent,
            MediaQuery.devicePixelRatioOf(context),
          ),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _MissingMedia(),
        );
      case CardMediaKind.emoji:
        return Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.gap),
              child: Text(card.content, style: const TextStyle(fontSize: 70)),
            ),
          ),
        );
    }
  }

  /// Decodes a photo at about twice the size it is drawn at. A 12 MP photo
  /// decoded at camera resolution takes about 48 MB.
  ///
  /// Twice, because [BoxFit.cover] draws a wide photo larger than the box's
  /// own side. Rounded up to a 256 px step, so a small layout change does not
  /// cause a new decode. An unbounded or empty box decodes in full.
  static ImageProvider _decodeNearDrawnSize(
    ImageProvider image,
    double? extent,
    double pixelRatio,
  ) {
    if (extent == null || !extent.isFinite || extent <= 0) return image;

    final int side = (extent * 2 * pixelRatio / 256).ceil() * 256;
    return ResizeImage(
      image,
      width: side,
      height: side,
      policy: ResizeImagePolicy.fit,
    );
  }
}

class _MissingMedia extends StatelessWidget {
  const _MissingMedia();

  @override
  Widget build(BuildContext context) => const Center(
    child: FittedBox(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: AppTokens.inkMuted,
        ),
      ),
    ),
  );
}
