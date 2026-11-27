import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/board_page.dart';
import '../theme.dart';

/// The row of page tabs under the app bar. It scrolls sideways when the tabs
/// do not fit.
class PageTabs extends StatelessWidget {
  const PageTabs({
    super.key,
    required this.pages,
    required this.openId,
    required this.onOpen,
  });

  final List<BoardPage> pages;
  final String openId;
  final ValueChanged<BoardPage> onOpen;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(AppTokens.gap, 8, AppTokens.gap, 0),
    child: Row(
      children: [
        for (final BoardPage page in pages)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Tab(
              page: page,
              open: page.id == openId,
              onTap: () => onOpen(page),
            ),
          ),
      ],
    ),
  );
}

/// One tab. The open tab differs in fill, border width, and text weight, so
/// it does not rely on colour alone.
class _Tab extends StatelessWidget {
  const _Tab({required this.page, required this.open, required this.onTap});

  final BoardPage page;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? symbol = page.symbol;
    return Semantics(
      container: true,
      button: true,
      selected: open,
      label: page.name,
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppTokens.tabMinHeight,
          maxWidth: AppTokens.tabMaxWidth,
        ),
        child: Material(
          color: open ? AppTokens.action : AppTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.sheetRadius),
            side: open
                ? const BorderSide(
                    color: AppTokens.ink,
                    width: AppTokens.tabOpenBorder,
                  )
                : const BorderSide(color: AppTokens.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.gap,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (symbol != null) ...[
                    SvgPicture.asset(
                      symbol,
                      width: AppTokens.tabSymbolSize,
                      height: AppTokens.tabSymbolSize,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      page.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: open ? AppTokens.onAction : AppTokens.ink,
                        fontWeight: open ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
