import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/saved_drawing.dart';
import '../services/saved_drawing_service.dart';
import '../theme/app_dimens.dart';

/// What the viewer reports to its caller when it closes.
enum SavedDrawingAction { deleted, repaint }

/// Soft light-gray background, matching the painting canvas.
const Color _kPanelGray = Color(0xFFE8E9ED);

/// Full-screen viewer for one saved drawing: polaroid-style artwork preview
/// with Repaint, Share, Delete, and an editable name. Pops with a
/// [SavedDrawingAction] (or `null` on plain close) so the caller can reconcile.
class SavedDrawingViewer extends StatefulWidget {
  const SavedDrawingViewer({super.key, required this.drawing});

  final SavedDrawing drawing;

  @override
  State<SavedDrawingViewer> createState() => _SavedDrawingViewerState();
}

class _SavedDrawingViewerState extends State<SavedDrawingViewer> {
  late String _name;
  final GlobalKey _shareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _name = widget.drawing.name.isNotEmpty
        ? widget.drawing.name
        : 'Your Artwork';
  }

  Future<void> _share() async {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      await SavedDrawingService.to.shareSaved(
        widget.drawing,
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (mounted) {
        Get.snackbar('Share failed', '$e', snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this drawing?'),
        content: const Text('This permanently removes it from your gallery.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SavedDrawingService.to.deleteSaved(widget.drawing);
      if (mounted) Navigator.of(context).pop(SavedDrawingAction.deleted);
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Delete failed',
          '$e',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final newName = await Get.dialog<String>(
      Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Dialog(
            backgroundColor: scheme.surface,
            insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.edit_rounded,
                          color: scheme.primary,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Name your artwork',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 64,
                      decoration: InputDecoration(
                        hintText: 'Enter a name…',
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => Get.back<String>(result: controller.text),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (newName == null || newName.trim().isEmpty || newName.trim() == _name) {
      return;
    }

    final trimmed = newName.trim();
    setState(() => _name = trimmed);

    // Persist to the cloud.
    try {
      await SavedDrawingService.to.rename(widget.drawing.id, trimmed);
      if (mounted) {
        Get.snackbar(
          'Renamed',
          'Saved as "$trimmed"',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (_) {
      // Cloud update failed; local name still updated on screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _kPanelGray,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: close + title + delete.
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.image_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Delete',
                    onPressed: _confirmDelete,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Artwork — rounded card with proper layout.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Image.network(
                            widget.drawing.imageUrl,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                            errorBuilder: (context, error, stack) =>
                                const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 48,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.45),
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.only(
                                left: 14,
                                bottom: 8,
                              ),
                              alignment: Alignment.bottomLeft,
                              child: GestureDetector(
                                onTap: _rename,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.image_rounded,
                                      size: 15,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.edit_rounded,
                                      size: 13,
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Bottom actions: Repaint + Share.
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(SavedDrawingAction.repaint),
                      icon: const Icon(Icons.brush_rounded),
                      label: const Text('Repaint'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: _shareKey,
                      onPressed: _share,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
