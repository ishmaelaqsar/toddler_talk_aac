import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Where the picture on a new card comes from.
enum CardSource { giphy, library, camera, gallery }

/// Asks the parent where a new card's picture comes from.
///
/// Giphy needs an API key. The row is left out when no key is configured,
/// rather than offered and then failing: a parent who sideloaded the APK has no
/// way to add one.
Future<CardSource?> showAddCardSheet(
  BuildContext context, {
  required bool giphyEnabled,
}) => showModalBottomSheet<CardSource>(
  context: context,
  useSafeArea: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.gap),
          child: Text(
            'Create card from...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (giphyEnabled)
          _SourceTile(
            icon: Icons.gif_box_outlined,
            title: 'Giphy Search',
            subtitle: 'Search animated GIFs. Saved for offline use.',
            source: CardSource.giphy,
          ),
        _SourceTile(
          icon: Icons.grid_view_outlined,
          title: 'Symbol Library',
          subtitle: 'Search the built-in picture symbols',
          source: CardSource.library,
        ),
        _SourceTile(
          icon: Icons.camera_alt_outlined,
          title: 'Take Photo',
          subtitle: "Photograph your child's own cup or toy",
          source: CardSource.camera,
        ),
        _SourceTile(
          icon: Icons.photo_library_outlined,
          title: 'Photo Gallery',
          subtitle: 'Supports GIFs',
          source: CardSource.gallery,
        ),
        const SizedBox(height: AppTokens.gap),
      ],
    ),
  ),
);

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.source,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final CardSource source;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppTokens.action, size: 32),
    title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    onTap: () => Navigator.pop(context, source),
  );
}
