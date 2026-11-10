import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/jigsaw_controller.dart';
import '../models/svg_asset.dart';
import '../services/svg_asset_service.dart';
import '../theme/app_surfaces.dart';
import '../utils/page_transitions.dart';
import '../widgets/category_asset_grid.dart';
import '../widgets/common/common.dart';
import 'jigsaw_play_screen.dart';

/// The **Jigsaw Puzzle** tab. Lists every puzzle photo directly (not gated
/// behind stories), so the tab shows content even when the portal has puzzle
/// `svg_assets` but no `story_lines`. Tap a photo to start a jigsaw from it.
class JigsawPuzzleScreen extends StatefulWidget {
  const JigsawPuzzleScreen({super.key});

  @override
  State<JigsawPuzzleScreen> createState() => _JigsawPuzzleScreenState();
}

class _JigsawPuzzleScreenState extends State<JigsawPuzzleScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure the controller exists early so the grid's open handler can reuse
    // it (and so puzzle progress survives tab switches).
    if (!Get.isRegistered<JigsawController>()) {
      Get.put(JigsawController(), permanent: true);
    }
  }

  /// Loads the photo as the jigsaw source image and opens the play screen.
  Future<void> _openPuzzle(SvgAsset asset) async {
    final c = Get.isRegistered<JigsawController>()
        ? Get.find<JigsawController>()
        : Get.put(JigsawController(), permanent: true);
    final ok = await c.useAsset(asset);
    if (!ok || !mounted) return;
    c.prepareNewGame();
    Navigator.of(context).push(
      FadeSlideRoute<void>(
        builder: (_) => JigsawPlayScreen(controller: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageSurface(context),
      appBar: const GradientAppBar(
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Puzzle'),
          ],
        ),
        actions: [NotificationBell()],
      ),
      body: SafeArea(
        child: CategoryAssetGrid(
          category: SvgAssetCategory.puzzle,
          onOpen: _openPuzzle,
          emptyText: 'No puzzle photos yet.',
        ),
      ),
    );
  }
}
