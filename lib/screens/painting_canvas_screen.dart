import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/drawing_controller.dart';
import '../models/drawing_template.dart';
import '../models/drawing_tool.dart';
import '../models/stroke.dart';
import '../theme/app_dimens.dart';
import '../widgets/feedback_prompter.dart';
import '../widgets/painter.dart';
import 'saved_drawing_screen.dart';

/// Soft light-gray used for the page background and the floating control panels.
const Color _kPanelGray = Color(0xFFE8E9ED);

/// The painting **canvas** — pushed from the Painting home once an activity
/// (Free Draw, a picture, or an uploaded SVG) has been chosen. Owns no state:
/// it renders [DrawingController] and forwards gestures to it.
///
/// Layout (chrome-free — a [Stack] of floating panels over a full-screen
/// canvas, all on a soft gray wash):
/// - **Canvas** — fills the screen behind everything.
/// - **Top** — a floating [_TopRail]: Back and the tools (Brush — which reveals
///   its styles and stroke-thickness presets beneath — Eraser, Fill, Pick).
/// - **Bottom centre** — a floating [_BottomControls] pill: Undo, the
///   current-color swatch (tap to pick), and Redo.
///
/// Zoom is pinch-only; Clear and Share are intentionally omitted.
class PaintingCanvasScreen extends StatelessWidget {
  const PaintingCanvasScreen({super.key, required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _handleHome(controller);
      },
      child: Scaffold(
        backgroundColor: _kPanelGray,
        body: Stack(
          children: [
            // Canvas fills the entire screen, edge to edge (no card chrome).
            Positioned.fill(child: _Canvas(controller: controller)),
            // Floating controls, kept clear of the status bar / home indicator.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Stack(
                  children: [
                    // Tools, pinned to the top.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _TopRail(controller: controller),
                    ),
                    // Undo · Color · Redo, floating at the bottom centre.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: AppSpacing.md,
                      child: Center(
                          child: _BottomControls(controller: controller)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leaving the canvas via Home or the system back button. With a blank canvas it
/// just pops; once the user has painted, it asks whether to save first — Save
/// uploads to Supabase and then leaves, Don't save leaves immediately, Cancel
/// stays.
Future<void> _handleHome(DrawingController controller) async {
  if (!controller.hasArtwork) {
    if (Get.context != null && Get.context!.mounted) {
      Navigator.of(Get.context!).pop();
    }
    return;
  }
  final choice = await Get.dialog<String>(
    Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
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
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.save_rounded,
                        color: scheme.primary,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Save your drawing?',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Keep your painting before leaving?',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () => Get.back<String>(result: 'save'),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () => Get.back<String>(result: 'discard'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: scheme.error,
                      side: BorderSide(
                        color: scheme.error.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text("Don't save"),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: () => Get.back<String>(result: 'cancel'),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  switch (choice) {
    case 'discard':
      if (Get.context != null && Get.context!.mounted) {
        Navigator.of(Get.context!).pop();
      }
    case 'save':
      await _saveThenLeave(controller);
    default: // 'cancel' or dismissed — stay on the canvas.
      break;
  }
}

/// Saves the canvas to the cloud and, on success, leaves. On failure it keeps
/// the user on the canvas (with an explanatory snackbar) so their work isn't
/// silently lost.
Future<void> _saveThenLeave(DrawingController controller) async {
  final wasEdit = controller.isEditingSaved;
  Get.dialog<void>(
    const Center(child: CircularProgressIndicator()),
    barrierDismissible: false,
  );
  final result = await controller.saveCurrentDrawing();
  if (Get.isDialogOpen ?? false) Get.back<void>(); // close the spinner
  // Let the spinner finish popping before we pop the canvas, so the two
  // navigations don't collide.
  await Future<void>.delayed(Duration.zero);

  if (result.url != null) {
    if (Get.context != null && Get.context!.mounted) {
      Navigator.of(Get.context!).pop(); // success → leave the canvas
    }
    Get.snackbar(
      wasEdit ? 'Updated' : 'Saved',
      wasEdit
          ? 'Your changes were saved to this drawing.'
          : 'Your artwork was added to your gallery.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
    // A real cloud save is a good moment to ask how it's going (capped).
    unawaited(FeedbackPrompter.maybePrompt(trigger: 'drawing_saved'));
    return;
  }
  // Render or cloud save failed — stay put so nothing is lost.
  Get.snackbar(
    'Couldn\'t save',
    result.error ?? 'Could not save your drawing. Please try again.',
    snackPosition: SnackPosition.BOTTOM,
    duration: const Duration(seconds: 4),
  );
}

/// Renders + saves the current drawing (uploading to the cloud when signed in),
/// then opens [SavedDrawingScreen] with the result. A modal spinner covers the
/// save; a snackbar reports whether it reached the cloud or fell back to a
/// local-only share.
Future<void> _handleSave(DrawingController controller) async {
  // Captured before the save: a repaint keeps editing the same row, so the flag
  // stays true afterwards — read it now to title the confirmation correctly.
  final wasEdit = controller.isEditingSaved;
  Get.dialog<void>(
    const Center(child: CircularProgressIndicator()),
    barrierDismissible: false,
  );
  final result = await controller.saveCurrentDrawing();
  if (Get.isDialogOpen ?? false) Get.back<void>();

  final png = result.png;
  if (png == null) {
    Get.snackbar(
      'Save failed',
      result.error ?? 'Could not render the canvas.',
      snackPosition: SnackPosition.BOTTOM,
    );
    return;
  }
  if (result.url != null) {
    Get.snackbar(
      wasEdit ? 'Updated' : 'Saved',
      wasEdit
          ? 'Your changes were saved to this drawing.'
          : 'Your artwork was saved to your gallery.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  } else {
    Get.snackbar(
      'Not saved to cloud',
      result.error ?? 'Sign in to save — you can still share your artwork.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }
  final currentName = controller.isEditingSaved
      ? (controller.editingTargetName ?? 'Your Artwork')
      : (controller.selectedTemplate.value?.name ?? 'Free draw');
  await Get.to<void>(
    () => SavedDrawingScreen(
      imageBytes: png,
      imageUrl: result.url,
      name: currentName,
      editingTarget: controller.editingTarget,
      // Closing the result screen returns to the Library so the just-saved
      // artwork is in view: refresh the drawings row, then pop the result +
      // canvas off the stack.
      onClose: () {
        controller.onDrawingSaved?.call();
        Get.until((route) => route.isFirst);
      },
    ),
  );
  // Once they're done admiring the result, gently ask how it's going (capped,
  // and only after a save that actually reached the cloud).
  if (result.url != null) {
    unawaited(FeedbackPrompter.maybePrompt(trigger: 'drawing_saved'));
  }
}

/// Shared surface for the floating control rails: a rounded, bordered surface
/// card with a soft drop shadow so it reads as floating over the wash.
class _RailCard extends StatelessWidget {
  const _RailCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kPanelGray,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.sm),
        child: child,
      ),
    );
  }
}

/// The Undo · Color · Redo control pill that floats at the bottom centre over
/// the canvas. The middle swatch shows the current color and opens the picker.
class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return _RailCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailIconButton(
            icon: Icons.undo,
            tooltip: 'Undo',
            onTap: controller.undo,
          ),
          _ColorButton(controller: controller),
          _RailIconButton(
            icon: Icons.redo,
            tooltip: 'Redo',
            onTap: controller.redo,
          ),
        ],
      ),
    );
  }
}

/// The current-color swatch pinned between Undo and Redo: a ring-framed circle
/// showing the most recently chosen color. Tapping it opens the color picker.
class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.md);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: 'Color — tap to change',
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: () => controller.openColorPicker(context),
            borderRadius: radius,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surface,
                    border: Border.all(color: scheme.outlineVariant),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Obx(
                    () => Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: controller.selectedColor.value,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top rail: Back at the far left and the tools (Brush, Eraser, Fill, Pick).
/// When the brush or eraser is active, its styles and stroke-thickness presets
/// appear in a second row beneath. Zoom is pinch-only.
class _TopRail extends StatelessWidget {
  const _TopRail({required this.controller});

  final DrawingController controller;

  /// Stroke-thickness presets surfaced as dots when the brush/eraser is active —
  /// replaces the old numeric slider.
  static const List<double> _strokePresets = <double>[2, 6, 12, 20, 32];

  @override
  Widget build(BuildContext context) {
    return _RailCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Obx(() {
        final tool = controller.tool.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _RailIconButton(
                  icon: Icons.home_rounded,
                  tooltip: 'Home',
                  onTap: () => _handleHome(controller),
                ),
                // Tools, optically centred on the rail (balanced against the
                // leading Home button by the trailing spacer below).
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RailIconButton(
                          icon: Icons.brush,
                          tooltip: 'Brush',
                          selected: tool == DrawingTool.brush,
                          onTap: () => controller.selectTool(DrawingTool.brush),
                        ),
                        _RailIconButton(
                          iconBuilder: (color, sz) =>
                              _EraserIcon(color: color, size: sz),
                          tooltip: 'Eraser',
                          selected: tool == DrawingTool.eraser,
                          onTap: () => controller.selectTool(DrawingTool.eraser),
                        ),
                        _RailIconButton(
                          icon: Icons.format_color_fill,
                          tooltip: 'Fill',
                          selected: tool == DrawingTool.bucket,
                          onTap: () => controller.selectTool(DrawingTool.bucket),
                        ),
                        _RailIconButton(
                          icon: Icons.colorize,
                          tooltip: 'Pick',
                          selected: tool == DrawingTool.eyedropper,
                          onTap: () =>
                              controller.selectTool(DrawingTool.eyedropper),
                        ),
                        // Duplicate the long-pressed selection — free-draw only
                        // (hidden when coloring a picture/template); disabled
                        // until something is selected.
                        Obx(
                          () => controller.isFreeDraw
                              ? _RailIconButton(
                                  icon:
                                      Icons.control_point_duplicate_rounded,
                                  tooltip: 'Duplicate selection',
                                  onTap: controller.hasSelection
                                      ? controller.duplicateSelected
                                      : null,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
                // Save — mirrors the leading Home button's width so the tool
                // cluster stays centred. Saves to the cloud then opens the
                // result screen.
                _RailIconButton(
                  icon: Icons.save_rounded,
                  tooltip: 'Save',
                  onTap: () => _handleSave(controller),
                ),
              ],
            ),
            // Thickness presets for the brush.
            if (tool == DrawingTool.brush &&
                controller.currentStroke.value == null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _ThicknessGroupHorizontal(
                  controller: controller,
                  presets: _strokePresets,
                ),
              ),
            // The eraser shares the stroke width, so reveal just the dots.
            if (tool == DrawingTool.eraser &&
                controller.currentStroke.value == null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _ThicknessGroupHorizontal(
                  controller: controller,
                  presets: _strokePresets,
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// A horizontal group of stroke-thickness dots. Selecting one sets the shared
/// stroke width; the dot nearest the current width is highlighted.
class _ThicknessGroupHorizontal extends StatelessWidget {
  const _ThicknessGroupHorizontal({
    required this.controller,
    required this.presets,
  });

  final DrawingController controller;
  final List<double> presets;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final width in presets)
          Obx(
            () => _ThicknessButton(
              size: width,
              selected:
                  _closestPreset(controller.strokeWidth.value, presets) == width,
              onTap: () => controller.setStrokeWidth(width),
            ),
          ),
      ],
    );
  }
}

/// A single rail entry: a square, rounded, optionally-selected icon button. A
/// null [onTap] renders it disabled (dimmed and non-interactive).
class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    this.icon,
    this.iconBuilder,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  }) : assert(
         icon != null || iconBuilder != null,
         'Provide either an icon or an iconBuilder',
       );

  static const double _iconSize = 22;
  static const double _dim = 42;

  final IconData? icon;

  /// Custom glyph builder for icons Material doesn't ship in this SDK (e.g. the
  /// eraser). Receives the resolved foreground [Color] and the icon size.
  final Widget Function(Color color, double size)? iconBuilder;

  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final fg = selected
        ? scheme.onPrimary
        : enabled
        ? scheme.onSurfaceVariant
        : scheme.onSurfaceVariant.withValues(alpha: 0.38);
    final radius = BorderRadius.circular(AppRadius.md);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: SizedBox(
              width: _dim,
              height: _dim,
              child: Center(
                child: iconBuilder != null
                    ? iconBuilder!(fg, _iconSize)
                    : Icon(icon, size: _iconSize, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hand-drawn eraser glyph — Material doesn't ship `ink_eraser` in this SDK.
/// A tilted rounded block whose worn front end is filled, with a band line.
class _EraserIcon extends StatelessWidget {
  const _EraserIcon({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _EraserIconPainter(color),
    );
  }
}

class _EraserIconPainter extends CustomPainter {
  _EraserIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.09
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.52); // ≈ -30°

    final w = size.width * 0.92;
    final h = size.height * 0.46;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.3));

    // Front (worn) ~40% solid, the rest outlined, a band line between them.
    final bandX = rect.left + w * 0.4;
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(Rect.fromLTRB(rect.left, rect.top, bandX, rect.bottom), fill);
    canvas.restore();
    canvas.drawRRect(rrect, stroke);
    canvas.drawLine(Offset(bandX, rect.top), Offset(bandX, rect.bottom), stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EraserIconPainter old) => old.color != color;
}

/// A stroke-thickness preset shown as a centered dot whose diameter scales with
/// the width it sets.
class _ThicknessButton extends StatelessWidget {
  const _ThicknessButton({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = (size * 0.7).clamp(4.0, 22.0).toDouble();
    final radius = BorderRadius.circular(AppRadius.md);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The preset in [presets] closest to [value] — used to highlight the active
/// thickness dot even after a custom width arrives from elsewhere.
double _closestPreset(double value, List<double> presets) {
  var best = presets.first;
  var bestDelta = (value - best).abs();
  for (final p in presets) {
    final delta = (value - p).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = p;
    }
  }
  return best;
}

/// Drawing surface. Uses a raw [Listener] (not [GestureDetector]) so we don't
/// claim the gesture arena — that lets the surrounding [InteractiveViewer]'s
/// scale recognizer win two-finger pinches even after we've started tracking
/// a one-finger draw. When a second pointer arrives we abort the in-flight
/// stroke so a pinch-zoom doesn't leave a stray scribble behind.
class _Canvas extends StatefulWidget {
  const _Canvas({required this.controller});

  final DrawingController controller;

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> {
  /// Pointers currently down on the canvas. Used to detect multi-touch.
  final Set<int> _activePointers = <int>{};

  /// The pointer we're treating as the drawing finger (the first one down
  /// while no others were active). Null if multi-touch or no touch.
  int? _drawingPointer;

  /// Where the drawing pointer first touched down. Held until the pointer
  /// either crosses the slop threshold (becomes a stroke) or lifts (becomes
  /// a tap).
  Offset? _downPosition;

  /// True once we've passed the slop and called [DrawingController.handlePanStart].
  bool _strokeStarted = false;

  /// True while this gesture is dragging the selected element (not painting).
  bool _movingSelected = false;

  /// True once a long-press has fired for this gesture (selected an element or
  /// cleared the selection) — the rest of the gesture then neither paints nor
  /// places a tap dot.
  bool _longPressHandled = false;

  Timer? _longPressTimer;
  static const Duration _longPressDuration = Duration(milliseconds: 350);

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  bool _inBounds(Offset p, Size size) =>
      p.dx >= 0 && p.dy >= 0 && p.dx <= size.width && p.dy <= size.height;

  void _resetGesture() {
    _drawingPointer = null;
    _downPosition = null;
    _strokeStarted = false;
    _movingSelected = false;
    _longPressHandled = false;
  }

  void _handlePointerDown(PointerDownEvent event, Size size) {
    _activePointers.add(event.pointer);

    if (_activePointers.length > 1) {
      // Second finger arrived — abandon any in-flight gesture and let
      // InteractiveViewer's pinch take over.
      _cancelLongPressTimer();
      if (_movingSelected) {
        widget.controller.endMoveSelected();
      } else if (_strokeStarted) {
        widget.controller.cancelStroke();
      }
      _resetGesture();
      return;
    }

    if (!_inBounds(event.localPosition, size)) return;
    widget.controller.canvasSize = size;
    _drawingPointer = event.pointer;
    _downPosition = event.localPosition;
    _strokeStarted = false;
    _movingSelected = false;
    _longPressHandled = false;

    // Selection / move are free-draw-only (disabled when coloring a picture or
    // template). A press on the already-selected element drags it.
    if (widget.controller.isFreeDraw &&
        widget.controller.selectedContains(event.localPosition, size)) {
      _movingSelected = true;
      widget.controller.beginMoveSelected(event.localPosition, size);
      return;
    }

    // Long-press for selection/move (brush/eraser only — bucket/eyedropper
    // are tap-tools that would be silently swallowed by the long-press timer).
    if (widget.controller.isFreeDraw) {
      final tool = widget.controller.tool.value;
      if (tool == DrawingTool.brush || tool == DrawingTool.eraser) {
        _longPressTimer = Timer(_longPressDuration, () {
          if (_drawingPointer != event.pointer || _strokeStarted) return;
          final pos = _downPosition;
          if (pos == null) return;
          _longPressHandled = true;
          final found = widget.controller.selectAt(pos, size);
          HapticFeedback.selectionClick();
          if (found) {
            _movingSelected = true;
            widget.controller.beginMoveSelected(pos, size);
          }
        });
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event, Size size) {
    if (event.pointer != _drawingPointer || _activePointers.length > 1) return;
    final start = _downPosition;
    if (start == null) return;

    if (_movingSelected) {
      widget.controller.updateMoveSelected(event.localPosition, size);
      return;
    }
    // Long-press already resolved this gesture (e.g. tapped empty space) — don't
    // start painting from the residual movement.
    if (_longPressHandled) return;

    if (!_strokeStarted) {
      if ((event.localPosition - start).distance < kTouchSlop) return;
      _cancelLongPressTimer(); // moved → it's a draw, not a long-press
      widget.controller.handlePanStart(
        DragStartDetails(
          globalPosition: event.position - event.delta,
          localPosition: start,
        ),
        size,
      );
      _strokeStarted = true;
    }

    if (!_inBounds(event.localPosition, size)) return;
    widget.controller.handlePanUpdate(
      DragUpdateDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        delta: event.delta,
      ),
      size,
    );
  }

  void _handlePointerEnd(
    PointerEvent event,
    Size size, {
    required bool cancelled,
  }) {
    _activePointers.remove(event.pointer);
    if (event.pointer != _drawingPointer) return;
    _cancelLongPressTimer();
    final start = _downPosition;
    if (_movingSelected) {
      widget.controller.endMoveSelected();
    } else if (cancelled) {
      if (_strokeStarted) widget.controller.cancelStroke();
    } else if (_strokeStarted) {
      widget.controller.handlePanEnd(DragEndDetails());
    } else if (!_longPressHandled && start != null && _inBounds(start, size)) {
      widget.controller.handleTap(start, size); // tap → dot
    }
    _resetGesture();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        // After the first paint, capture a raster baseline used by
        // [_maybeRegionClip] to keep brush strokes inside the lines.
        // Works for both:
        //   a) outline-only coloring pages (template set, no vector regions)
        //   b) repaint mode (backgroundImage set, no template)
        // No-ops once captured; retries until the frame has dark content.
        if (widget.controller.selectedTemplate.value != null ||
            widget.controller.backgroundImage.value != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.controller.ensureColoringBaseline(size);
          });
        }

        return InteractiveViewer(
          transformationController: widget.controller.transformationController,
          panEnabled: false,
          scaleEnabled: true,
          minScale: 1.0,
          maxScale: 8.0,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                RepaintBoundary(
                  key: widget.controller.repaintBoundaryKey,
                  child: ClipRect(
                    child: Container(
                      color: Colors.white,
                      width: size.width,
                      height: size.height,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) => _handlePointerDown(e, size),
                        onPointerMove: (e) => _handlePointerMove(e, size),
                        onPointerUp: (e) =>
                            _handlePointerEnd(e, size, cancelled: false),
                        onPointerCancel: (e) =>
                            _handlePointerEnd(e, size, cancelled: true),
                        child: Obx(
                          () => CustomPaint(
                            painter: Painter(
                              actions: widget.controller.actions.toList(),
                              currentStroke:
                                  widget.controller.currentStroke.value,
                              template:
                                  widget.controller.selectedTemplate.value,
                              paintMode: widget.controller.paintMode.value,
                              backgroundImage:
                                  widget.controller.backgroundImage.value,
                              selectionRect:
                                  widget.controller.selectionRect(size),
                            ),
                            size: size,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Brush indicator — shows a preview of the current brush
                // size and color at the touch point while drawing.
                Obx(
                  () => _BrushIndicator(
                    stroke: widget.controller.currentStroke.value,
                    size: size,
                    template: widget.controller.selectedTemplate.value,
                    strokeWidth: widget.controller.strokeWidth.value,
                    color: widget.controller.selectedColor.value,
                    tool: widget.controller.tool.value,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A small circular overlay showing the current brush tip (size + color) at the
/// last point of the in-flight stroke. Only visible while actively drawing with
/// the brush tool.
class _BrushIndicator extends StatelessWidget {
  const _BrushIndicator({
    required this.stroke,
    required this.size,
    required this.template,
    required this.strokeWidth,
    required this.color,
    required this.tool,
  });

  final Stroke? stroke;
  final Size size;
  final DrawingTemplate? template;
  final double strokeWidth;
  final Color color;
  final DrawingTool tool;

  @override
  Widget build(BuildContext context) {
    if (stroke == null ||
        stroke!.points.isEmpty ||
        tool != DrawingTool.brush) {
      return const SizedBox.shrink();
    }

    Offset pos = stroke!.points.last;
    if (stroke!.isPictureSpace) {
      final fit = template?.fitTransform(size);
      if (fit != null) {
        pos = Offset(
          pos.dx * fit.scale + fit.offset.dx,
          pos.dy * fit.scale + fit.offset.dy,
        );
      }
    }

    final radius = (strokeWidth / 2).clamp(7.0, 50.0);

    return Positioned(
      left: pos.dx - radius,
      top: pos.dy - radius,
      child: IgnorePointer(
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.25),
            border: Border.all(color: color, width: 2),
          ),
        ),
      ),
    );
  }
}

