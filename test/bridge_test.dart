// The test reads what giphy_get and reorderable_grid_view read, through the
// library they import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddler_talk_aac/screens/board_screen.dart';
import 'package:toddler_talk_aac/theme.dart';

import 'test_harness.dart';

/// The app uses material_ui, but giphy_get and reorderable_grid_view import
/// package:flutter/material.dart. Without a bridge, their widgets find no
/// theme and no localisations of that library.
void main() {
  testWidgets('a widget of the legacy library gets the app theme and '
      'localisations', (tester) async {
    installMocks(
      storedCards: [storedCard(id: 'a', label: 'Cup')],
    );
    await pumpApp(tester);

    final BuildContext below = tester.element(find.byType(BoardScreen));
    final legacy.ColorScheme colours = legacy.Theme.of(below).colorScheme;
    expect(colours.primary, AppTokens.action);
    expect(colours.surface, AppTokens.surface);
    expect(legacy.MaterialLocalizations.of(below).cancelButtonLabel, 'Cancel');
  });
}
