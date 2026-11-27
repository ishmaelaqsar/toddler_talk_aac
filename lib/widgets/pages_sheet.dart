import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';

import '../models/board_page.dart';
import '../theme.dart';
import 'symbol_picker.dart';

/// Opens the page manager.
///
/// [pages] reads the board's pages on each build, so the sheet holds no copy
/// that can go stale. Each change goes to [onChanged] at once, as in the
/// settings sheet. [onDelete] asks first, and moves the page's cards.
Future<void> showPagesSheet(
  BuildContext context, {
  required List<BoardPage> Function() pages,
  required ValueChanged<List<BoardPage>> onChanged,
  required Future<void> Function(BoardPage page) onDelete,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      _PagesSheet(pages: pages, onChanged: onChanged, onDelete: onDelete),
);

class _PagesSheet extends StatefulWidget {
  const _PagesSheet({
    required this.pages,
    required this.onChanged,
    required this.onDelete,
  });

  final List<BoardPage> Function() pages;
  final ValueChanged<List<BoardPage>> onChanged;
  final Future<void> Function(BoardPage page) onDelete;

  @override
  State<_PagesSheet> createState() => _PagesSheetState();
}

class _PagesSheetState extends State<_PagesSheet> {
  void _apply(List<BoardPage> pages) {
    widget.onChanged(pages);
    setState(() {});
  }

  void _replace(BoardPage page) => _apply([
    for (final BoardPage other in widget.pages())
      other.id == page.id ? page : other,
  ]);

  Future<void> _rename(BoardPage page) async {
    final String? name = await _askName(
      context,
      title: 'Rename ${page.name}',
      initial: page.name,
      action: 'Save',
    );
    if (name == null || !mounted) return;
    _replace(page.copyWith(name: name));
  }

  Future<void> _chooseSymbol(BoardPage page) async {
    final SymbolChoice? choice = await showSymbolPicker(context);
    if (choice == null || !mounted) return;
    _replace(page.copyWith(symbol: choice.assetPath));
  }

  void _move(BoardPage page, int by) {
    final List<BoardPage> pages = [...widget.pages()];
    final int from = pages.indexWhere((other) => other.id == page.id);
    pages.insert(from + by, pages.removeAt(from));
    _apply(pages);
  }

  Future<void> _add() async {
    final String? name = await _askName(
      context,
      title: 'New page',
      initial: '',
      action: 'Add',
    );
    if (name == null || !mounted) return;
    _apply([...widget.pages(), BoardPage(id: const Uuid().v4(), name: name)]);
  }

  Future<void> _delete(BoardPage page) async {
    await widget.onDelete(page);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<BoardPage> pages = widget.pages();
    // Scrolls, so the sheet holds up on a short screen and at a large text
    // scale.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.gap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pages', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.gap),
            for (int index = 0; index < pages.length; index++)
              _row(pages, index),
            ElevatedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add a page'),
            ),
          ],
        ),
      ),
    );
  }

  /// One page: its symbol and name, then its controls. The controls wrap, so
  /// a narrow screen does not push them off the edge.
  Widget _row(List<BoardPage> pages, int index) {
    final BoardPage page = pages[index];
    final String? symbol = page.symbol;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (symbol != null) ...[
                SvgPicture.asset(
                  symbol,
                  width: AppTokens.tabSymbolSize,
                  height: AppTokens.tabSymbolSize,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  page.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          Wrap(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                color: AppTokens.action,
                tooltip: 'Rename ${page.name}',
                onPressed: () => _rename(page),
              ),
              IconButton(
                icon: const Icon(Icons.image_outlined),
                color: AppTokens.action,
                tooltip: 'Choose a symbol for ${page.name}',
                onPressed: () => _chooseSymbol(page),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                color: AppTokens.action,
                tooltip: 'Move ${page.name} up',
                onPressed: index == 0 ? null : () => _move(page, -1),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward),
                color: AppTokens.action,
                tooltip: 'Move ${page.name} down',
                onPressed: index == pages.length - 1
                    ? null
                    : () => _move(page, 1),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: AppTokens.danger,
                tooltip: 'Delete ${page.name}',
                // The board always keeps one page.
                onPressed: pages.length == 1 ? null : () => _delete(page),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for a page name. Returns null when the parent cancels.
///
/// A name cannot be empty, because a tab with no name tells nobody what is on
/// it.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String initial,
  required String action,
}) {
  String name = initial;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocalState) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) => setLocalState(() => name = value),
          decoration: InputDecoration(
            labelText: 'Page name',
            border: const OutlineInputBorder(),
            errorText: name.trim().isEmpty ? 'A page needs a name' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: name.trim().isEmpty
                ? null
                : () => Navigator.pop(context, name.trim()),
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}
