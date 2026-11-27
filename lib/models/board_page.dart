import 'talk_card.dart';

/// One page of the board, such as Food or Play.
class BoardPage {
  const BoardPage({required this.id, required this.name, this.symbol});

  /// The page every board starts with, and the one that stands in when the
  /// stored pages cannot be read.
  static const BoardPage home = BoardPage(id: 'home', name: 'Home');

  final String id;
  final String name;

  /// An asset key under `assets/symbols/`, drawn on the page's tab.
  final String? symbol;

  factory BoardPage.fromJson(Map<String, dynamic> json) => BoardPage(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    symbol: json['symbol'] as String?,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'symbol': symbol};

  BoardPage copyWith({String? name, String? symbol}) =>
      BoardPage(id: id, name: name ?? this.name, symbol: symbol ?? this.symbol);
}

/// The page [card] sits on. A missing or unknown page puts the card on the
/// first page, so no card is ever lost from view.
String pageIdOf(TalkCard card, List<BoardPage> pages) {
  final String? id = card.pageId;
  return pages.any((p) => p.id == id) ? id! : pages.first.id;
}

/// The cards on page [pageId], in board order.
List<TalkCard> cardsOnPage(
  List<TalkCard> cards,
  List<BoardPage> pages,
  String pageId,
) => cards.where((c) => pageIdOf(c, pages) == pageId).toList();

/// Applies a drag on page [pageId] to the whole board.
///
/// [oldIndex] and [newIndex] index the cards on the page, with the meaning
/// `list.insert(newIndex, list.removeAt(oldIndex))`. The moved cards fill the
/// places the page's cards held before, so every other card keeps its place.
List<TalkCard> reorderWithinPage(
  List<TalkCard> cards,
  List<BoardPage> pages,
  String pageId,
  int oldIndex,
  int newIndex,
) {
  final List<TalkCard> onPage = cardsOnPage(cards, pages, pageId);
  onPage.insert(newIndex, onPage.removeAt(oldIndex));
  int next = 0;
  return [
    for (final TalkCard card in cards)
      pageIdOf(card, pages) == pageId ? onPage[next++] : card,
  ];
}
