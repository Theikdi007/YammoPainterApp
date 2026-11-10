import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/svg_asset.dart';
import '../services/svg_asset_service.dart';
import 'asset_tile.dart';

/// A pull-to-refresh grid of **every** [SvgAsset] in [category], rendered as
/// [AssetTile]s. Unlike the stories-first shelves, this lists assets directly —
/// so a tab whose portal has assets but no `story_lines` rows (e.g. Puzzle)
/// still shows its photos.
///
/// Backed by the shared, re-listenable realtime feed
/// ([SvgAssetService.live]) so the grid updates live. Tap is delegated to
/// [onOpen]; while it runs a frosted scrim covers the grid (prevents double
/// taps while the source image downloads / the canvas opens).
class CategoryAssetGrid extends StatefulWidget {
  const CategoryAssetGrid({
    super.key,
    required this.category,
    required this.onOpen,
    this.emptyText,
  });

  final String category;

  /// Opens the asset (loads it and pushes its canvas). Awaited so the grid can
  /// show a loading scrim for the duration.
  final Future<void> Function(SvgAsset asset) onOpen;

  /// Override for the empty-state caption (defaults to "No photos yet").
  final String? emptyText;

  @override
  State<CategoryAssetGrid> createState() => _CategoryAssetGridState();
}

class _CategoryAssetGridState extends State<CategoryAssetGrid> {
  /// True while a tapped asset is opening its canvas.
  bool _opening = false;

  Future<void> _onTap(SvgAsset asset) async {
    if (_opening) return;
    if (asset.isLocked) {
      Get.snackbar(
        'Locked',
        "This photo isn't available yet.",
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    setState(() => _opening = true);
    try {
      await widget.onOpen(asset);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  int _columnsFor(double width) {
    if (width < 600) return 2;
    if (width < 1000) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () =>
          SvgAssetService.to.refreshLive(category: widget.category),
      child: StreamBuilder<List<SvgAsset>>(
        stream: SvgAssetService.to.live(category: widget.category),
        initialData: SvgAssetService.to.lastOf(category: widget.category),
        builder: (context, snap) {
          final loading = snap.connectionState == ConnectionState.waiting &&
              !snap.hasData;
          final assets = snap.data ?? const <SvgAsset>[];
          return Stack(
            children: [
              _body(context, loading, assets),
              if (_opening)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, bool loading, List<SvgAsset> assets) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      // Scrollable host so pull-to-refresh stays armed.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (assets.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 64),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined,
                    color: scheme.onSurfaceVariant, size: 32),
                const SizedBox(height: 8),
                Text(
                  widget.emptyText ?? 'No photos yet.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final cols = _columnsFor(MediaQuery.sizeOf(context).width);
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.9,
      ),
      itemCount: assets.length,
      itemBuilder: (context, i) => AssetTile(
        asset: assets[i],
        onTap: () => _onTap(assets[i]),
      ),
    );
  }
}
