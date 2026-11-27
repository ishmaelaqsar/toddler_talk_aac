import 'package:material_ui/material_ui.dart';

import 'screens/board_screen.dart';
import 'theme.dart';

/// The Giphy key, supplied at build time:
/// `flutter run --dart-define=GIPHY_API_KEY=<key>`.
///
/// A key is optional. Without one the add sheet leaves the GIF search out, and
/// every other source still works. The key used to come from a `.env` asset,
/// which broke two ways: a clean clone would not build without the file, and
/// an installed APK could never be given one.
const String _giphyApiKey = String.fromEnvironment('GIPHY_API_KEY');

void main() {
  runApp(const ToddlerTalkApp(giphyApiKey: _giphyApiKey));
}

class ToddlerTalkApp extends StatelessWidget {
  const ToddlerTalkApp({super.key, this.giphyApiKey = ''});

  final String giphyApiKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toddler Talk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      // giphy_get and reorderable_grid_view import package:flutter/material.dart,
      // so their widgets read the theme and the localisations of that library.
      // The bridge gives them this app's theme. material_ui marks the bridge as
      // deprecated because it is a temporary aid.
      // ignore: deprecated_member_use
      builder: (context, child) => MaterialUiCompatibilityBridge(child: child!),
      home: BoardScreen(giphyApiKey: giphyApiKey),
    );
  }
}
