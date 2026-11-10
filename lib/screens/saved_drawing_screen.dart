import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/saved_drawing.dart';
import '../services/saved_drawing_service.dart';
import '../theme/app_dimens.dart';
import '../widgets/common/responsive_container.dart';

/// Soft light-gray background, matching the painting canvas.
const Color _kPanelGray = Color(0xFFE8E9ED);

/// Shown after a drawing is saved: the finished artwork, an editable name, and a
/// Share button.
///
/// Receives the rendered PNG [imageBytes] (displayed instantly via
/// `Image.memory`) and, when the cloud save succeeded, its [imageUrl].
///
/// When [editingTarget] is provided the name change is persisted to the cloud on
/// save — otherwise the rename is local only.
class SavedDrawingScreen extends StatefulWidget {
  const SavedDrawingScreen({
    super.key,
    required this.imageBytes,
    this.imageUrl,
    this.name = 'Your Artwork',
    this.editingTarget,
    this.onClose,
  });

  final Uint8List imageBytes;
  final String? imageUrl;
  final String name;
  final SavedDrawing? editingTarget;
  final VoidCallback? onClose;

  @override
  State<SavedDrawingScreen> createState() => _SavedDrawingScreenState();
}

class _SavedDrawingScreenState extends State<SavedDrawingScreen> {
  late String _name;

  /// Anchors the iOS / iPad share popover to the Share button.
  final GlobalKey _shareButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _name = widget.name;
  }

  Future<void> _share() async {
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await sharePngBytes(widget.imageBytes, sharePositionOrigin: origin);
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

    // Persist to the cloud when editing a previously saved drawing.
    final target = widget.editingTarget;
    if (target != null) {
      try {
        await SavedDrawingService.to.rename(target.id, trimmed);
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = widget.imageUrl != null;
    return Scaffold(
      backgroundColor: _kPanelGray,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ResponsiveContainer(
            maxWidth: 560,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: close + status.
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Done',
                    onPressed: widget.onClose ?? Get.back<void>,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    saved ? Icons.check_circle_rounded : Icons.image_rounded,
                    color: saved ? Colors.green : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    saved ? 'Saved!' : 'Your artwork',
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Artwork — polaroid-style photo frame.
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.30),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          Image.memory(widget.imageBytes, fit: BoxFit.contain),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.50),
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.only(
                                left: 16,
                                bottom: 10,
                              ),
                              alignment: Alignment.bottomLeft,
                              child: GestureDetector(
                                onTap: _rename,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.image_rounded,
                                      size: 16,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.edit_rounded,
                                      size: 14,
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
              // Share.
              FilledButton.icon(
                key: _shareButtonKey,
                onPressed: _share,
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
