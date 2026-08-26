import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/talk_card.dart';
import '../theme.dart';
import 'card_media.dart';

/// One card on the board.
///
/// Holds its own pressed state, so a tap repaints this card alone instead of
/// the whole board.
class CardTile extends StatefulWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.parentMode,
    required this.onSpeak,
    required this.onEdit,
    required this.onToggleVisible,
    required this.onDelete,
  });

  final TalkCard card;

  /// True while a parent is editing. The card stops speaking and shows its
  /// edit controls.
  final bool parentMode;

  final VoidCallback onSpeak;
  final VoidCallback onEdit;
  final VoidCallback onToggleVisible;
  final VoidCallback onDelete;

  @override
  State<CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<CardTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    if (widget.parentMode) {
      widget.onEdit();
      return;
    }
    HapticFeedback.selectionClick();
    widget.onSpeak();
  }

  @override
  Widget build(BuildContext context) {
    final TalkCard card = widget.card;
    final bool dimmed = widget.parentMode && !card.isVisible;

    return Semantics(
      container: true,
      button: true,
      label: widget.parentMode
          ? (card.isVisible
                ? '${card.label}. Tap to edit.'
                : '${card.label}. Hidden from your child. Tap to edit.')
          : card.label,
      excludeSemantics: true,
      onTap: _handleTap,
      child: GestureDetector(
        onTap: _handleTap,
        onTapDown: widget.parentMode ? null : (_) => _setPressed(true),
        onTapUp: widget.parentMode ? null : (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(card.colorValue),
              borderRadius: BorderRadius.circular(AppTokens.cardRadius),
              border: widget.parentMode
                  ? Border.all(color: AppTokens.editableBorder, width: 3)
                  : null,
              boxShadow: const [
                BoxShadow(
                  color: AppTokens.cardShadow,
                  blurRadius: 6,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.cardRadius),
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _body(context, constraints.maxHeight, dimmed: dimmed),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    double tileHeight, {
    required bool dimmed,
  }) {
    final double toolbarHeight = widget.parentMode
        ? AppTokens.minTouchTarget
        : 0.0;
    final double forCard = math.max(0.0, tileHeight - toolbarHeight);

    // The band grows with the viewer's text scale, up to a share of the card.
    // Past that the label ellipsizes, so the picture never disappears and the
    // column never overflows.
    final double bandHeight = math.min(
      MediaQuery.textScalerOf(context).scale(AppTokens.labelSize) * 2.4 + 12,
      forCard * AppTokens.labelBandMaxFraction,
    );

    return Column(
      children: [
        SizedBox(
          height: forCard,
          child: Opacity(
            opacity: dimmed ? 0.4 : 1.0,
            child: Column(
              children: [
                Expanded(child: CardMedia(card: widget.card)),
                SizedBox(height: bandHeight, child: _label(context)),
              ],
            ),
          ),
        ),
        if (widget.parentMode)
          SizedBox(height: toolbarHeight, child: _toolbar()),
      ],
    );
  }

  Widget _label(BuildContext context) => ColoredBox(
    color: AppTokens.labelBand,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Center(
        child: Text(
          widget.card.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ),
  );

  Widget _toolbar() {
    final TalkCard card = widget.card;
    return ColoredBox(
      color: AppTokens.surface,
      // Each control takes an equal share of the card's width. A fixed 48dp
      // minimum would overflow a narrow card on a small phone.
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit ${card.label}',
            color: AppTokens.action,
            onPressed: widget.onEdit,
          ),
          _ToolbarButton(
            icon: card.isVisible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            tooltip: card.isVisible
                ? 'Hide ${card.label} from your child'
                : 'Show ${card.label} to your child',
            color: card.isVisible ? AppTokens.action : AppTokens.hidden,
            onPressed: widget.onToggleVisible,
          ),
          _ToolbarButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete ${card.label}',
            color: AppTokens.danger,
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          // Fills its share of the row, so the touch target is as large as the
          // card allows and is always the full toolbar height.
          child: Center(child: Icon(icon, color: color)),
        ),
      ),
    ),
  );
}
