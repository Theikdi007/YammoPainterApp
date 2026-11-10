import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/drawing_controller.dart';
import '../models/saved_drawing.dart';
import '../services/saved_drawing_service.dart';
import '../services/story_line_service.dart';
import '../services/svg_asset_service.dart';
import '../theme/app_dimens.dart';
import '../theme/app_surfaces.dart';
import '../utils/page_transitions.dart';
import '../widgets/common/common.dart';
import '../widgets/story_shelves.dart';
import 'painting_canvas_screen.dart';
import 'saved_drawing_viewer.dart';

/// The **Library** tab — the user's saved drawings plus the Painting-category
/// story list on one screen. Tap a drawing to view/repaint/share/delete it;
/// tap a story to browse its photos and open the canvas.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  // Shared painting controller (reused by the canvas + story detail + repaint).
  final DrawingController _controller = Get.isRegistered<DrawingController>()
      ? Get.find<DrawingController>()
      : Get.put(DrawingController(), permanent: true);

  List<SavedDrawing>? _drawings;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
    // A save in the canvas refreshes this row when the user comes back.
    _controller.onDrawingSaved = _load;
  }

  @override
  void dispose() {
    if (_controller.onDrawingSaved != null) {
      _controller.onDrawingSaved = null;
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await SavedDrawingService.to.fetchSaved();
      if (!mounted) return;
      setState(() {
        _drawings = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
    // Refresh the painting shelf's photo counts alongside the drawings list.
    unawaited(StoryLineService.to.loadAssetCounts(
      category: SvgAssetCategory.painting,
      force: true,
    ));
  }

  Future<void> _openDrawing(SavedDrawing drawing) async {
    final action = await Navigator.of(context).push<SavedDrawingAction>(
      FadeSlideRoute<SavedDrawingAction>(
        builder: (_) => SavedDrawingViewer(drawing: drawing),
      ),
    );
    if (!mounted) return;
    if (action == SavedDrawingAction.deleted) {
      setState(() {
        final list = _drawings;
        if (list != null) {
          _drawings = list.where((d) => d.id != drawing.id).toList();
        }
      });
      _load();
    } else if (action == SavedDrawingAction.repaint) {
      final ok = await _controller.repaintFromUrl(drawing);
      if (!ok || !mounted) return;
      await Navigator.of(context).push(
        FadeSlideRoute<void>(
          builder: (_) => PaintingCanvasScreen(controller: _controller),
        ),
      );
      if (mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageSurface(context),
      appBar: GradientAppBar(
        titleWidget: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Painting'),
          ],
        ),
        actions: const [NotificationBell()],
      ),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    _caption(context, 'Your drawings'),
                    const SizedBox(height: AppSpacing.sm),
                    _drawingsSection(context),
                    const SizedBox(height: AppSpacing.xl),
                    StoryShelf(
                      title: 'For you',
                      category: SvgAssetCategory.painting,
                      showCount: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _drawingsSection(BuildContext context) {
    final drawings = _drawings;
    return SizedBox(
      height: 180,
      child: _loading && drawings == null
          ? const _DrawingsSkeleton()
          : _error && (drawings == null || drawings.isEmpty)
              ? _Message(
                  icon: Icons.cloud_off_rounded,
                  text: "Couldn't load — tap to retry",
                  onTap: _load,
                )
              : drawings == null || drawings.isEmpty
                  ? _Message(
                      icon: Icons.brush_outlined,
                      text: 'No saved drawings yet — finish one to see it here.',
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemCount: drawings.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (context, i) => _DrawingThumb(
                        drawing: drawings[i],
                        onTap: () => _openDrawing(drawings[i]),
                      ),
      ),
    );
  }
}

class _DrawingsSkeleton extends StatelessWidget {
  const _DrawingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      children: const [
        SizedBox(width: 130, child: ShimmerBox(height: double.infinity, radius: 16)),
        SizedBox(width: AppSpacing.md),
        SizedBox(width: 130, child: ShimmerBox(height: double.infinity, radius: 16)),
        SizedBox(width: AppSpacing.md),
        SizedBox(width: 130, child: ShimmerBox(height: double.infinity, radius: 16)),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: scheme.onSurfaceVariant, size: 26),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
    if (onTap == null) return Center(child: content);
    return Center(child: GestureDetector(onTap: onTap, child: content));
  }
}

/// A horizontal saved-drawing thumbnail: a white card with the artwork + name.
/// Scales on tap.
class _DrawingThumb extends StatelessWidget {
  const _DrawingThumb({required this.drawing, required this.onTap});

  final SavedDrawing drawing;
  final VoidCallback onTap;

  static const double width = 130;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cardSurface(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.network(
                drawing.imageUrl,
                fit: BoxFit.cover,
                cacheWidth: 400,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                  scheme.onSurfaceVariant)),
                        ),
                      ),
                errorBuilder: (context, _, _) => Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                drawing.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
