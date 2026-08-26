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
  const CardMedia({super.key, required this.card, this.padding});

  final TalkCard card;

  /// Inset around a symbol. A photo fills the card instead.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    // The tile already announces the card's label, so the picture itself adds
    // nothing a screen reader needs to hear.
    return ExcludeSemantics(child: _media());
  }

  Widget _media() {
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
        // Image.file plays an animated GIF without extra work.
        return Image.file(
          File(card.content),
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
