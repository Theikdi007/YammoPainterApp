import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/drawing_controller.dart';
import '../controllers/jigsaw_controller.dart';
import '../models/story_line.dart';
import '../models/svg_asset.dart';
import '../services/svg_asset_service.dart';
import '../theme/app_surfaces.dart';
import '../utils/page_transitions.dart';
import '../widgets/asset_tile.dart';
import '../widgets/common/common.dart';
import 'ar_drawing_screen.dart';
import 'jigsaw_play_screen.dart';
import 'painting_canvas_screen.dart';

/// Shows all [SvgAsset] photos linked to a [StoryLine] as a clean white-card
/// grid. Tapping a photo opens the canvas for the story's category.
class StoryDetailScreen extends StatefulWidget {
  const StoryDetailScreen({super.key, required this.story});

  final StoryLine story;

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  List<SvgAsset>? _assets;
  bool _loading = true;
  String? _error;

  /// True while a tapped photo is loading/opening its canvas.
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final assets = await SvgAssetService.to.fetch(
        category: widget.story.category,
        storyLineId: widget.story.id,
      );
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load photos.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = (_assets?.isNotEmpty ?? false) ? _assets!.length : null;
    return Scaffold(
      backgroundColor: pageSurface(context),
      appBar: GradientAppBar(
        titleWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.story.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (count != null)
              Text(
                '$count photo${count == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _body(context),
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
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorRetry(message: _error!, onRetry: _load);
    }
    final assets = _assets ?? const <SvgAsset>[];
    if (assets.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined,
                  color: scheme.onSurfaceVariant, size: 32),
              const SizedBox(height: 8),
              Text(
                'No photos in this story yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    final cols = _columnsFor(MediaQuery.of(context).size.width);
    return GridView.builder(
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
        onTap: () => _onTapPhoto(context, assets[i]),
      ),
    );
  }

  Future<void> _onTapPhoto(BuildContext context, SvgAsset asset) async {
    if (asset.isLocked) {
      Get.snackbar(
        'Locked',
        'This photo isn\'t available yet.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    setState(() => _opening = true);
    try {
      switch (widget.story.category) {
        case SvgAssetCategory.painting:
          await _openPainting(asset);
        case SvgAssetCategory.drawing:
          _openAr(asset);
        case SvgAssetCategory.puzzle:
          await _openPuzzle(asset);
        default:
          break;
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Painting: SVG → region-fill coloring template; raster photo → color-over
  /// backdrop. Then open the painting canvas.
  Future<void> _openPainting(SvgAsset asset) async {
    final dc = Get.isRegistered<DrawingController>()
        ? Get.find<DrawingController>()
        : Get.put(DrawingController(), permanent: true);
    final isSvg = await SvgAssetService.to.resolveIsSvg(asset);
    if (!mounted) return;
    final ok = isSvg
        ? await dc.selectTemplateFromUrl(asset)
        : await dc.colorOverImageUrl(asset);
    if (!mounted || !ok) return;
    Navigator.of(context).push(
      FadeSlideRoute<void>(
        builder: (_) => PaintingCanvasScreen(controller: dc),
      ),
    );
  }

  /// AR Drawing: project the photo over the live camera.
  void _openAr(SvgAsset asset) {
    Navigator.of(context).push(
      FadeSlideRoute<void>(
        builder: (_) => ArDrawingScreen(presetSvgUrl: asset.resolvedUrl),
      ),
    );
  }

  /// Puzzle: load the photo as the source image and open the play screen.
  Future<void> _openPuzzle(SvgAsset asset) async {
    final c = Get.isRegistered<JigsawController>()
        ? Get.find<JigsawController>()
        : Get.put(JigsawController(), permanent: true);
    final ok = await c.useAsset(asset);
    if (!mounted || !ok) return;
    c.prepareNewGame();
    Navigator.of(context).push(
      FadeSlideRoute<void>(
        builder: (_) => JigsawPlayScreen(controller: c),
      ),
    );
  }

  int _columnsFor(double width) {
    if (width < 600) return 2;
    if (width < 1000) return 3;
    return 4;
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, color: scheme.onSurfaceVariant, size: 32),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

