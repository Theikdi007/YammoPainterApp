import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/jigsaw_controller.dart';
import '../models/puzzle_piece.dart';
import '../theme/app_dimens.dart';
import '../widgets/feedback_prompter.dart';
import '../widgets/jigsaw_celebration.dart';
import '../widgets/jigsaw_piece_view.dart';
import '../widgets/jigsaw_tray.dart';

/// Soft light-gray used for the floating control rails — mirrors the painting
/// canvas chrome so the two play surfaces feel like one app.
const Color _kPanelGray = Color(0xFFE8E9ED);

/// The dedicated full-screen puzzle play surface. Chrome-free like the painting
/// canvas: a zoom/pan board you drop pieces onto, a scrollable tray below, and
/// floating rail cards (Back · view options · Reset) over the board.
class JigsawPlayScreen extends StatefulWidget {
  const JigsawPlayScreen({super.key, required this.controller});

  final JigsawController controller;

  @override
  State<JigsawPlayScreen> createState() => _JigsawPlayScreenState();
}

class _JigsawPlayScreenState extends State<JigsawPlayScreen> {
  final GlobalKey _boardKey = GlobalKey();
  bool _requested = false;
  Worker? _solvedWorker;

  JigsawController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    // After a win (and a beat for the confetti), gently ask how it's going.
    // Frequency-capped inside FeedbackPrompter, so it rarely actually shows.
    _solvedWorker = ever<bool>(c.solved, (solved) {
      if (!solved) return;
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted || !c.solved.value) return;
        FeedbackPrompter.maybePrompt(trigger: 'puzzle_solved');
      });
    });
  }

  @override
  void dispose() {
    _solvedWorker?.dispose();
    // Leaving the play screen stops the clock (a fresh game restarts it).
    c.pause();
    super.dispose();
  }

  /// Maps a drop to board space (zoom-corrected) and asks whether it lands on
  /// the piece's home.
  bool _isNear(DragTargetDetails<PuzzlePiece> d) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final s = c.currentScale;
    final piece = d.data;
    final centre =
        d.offset + Offset(piece.size.width * s / 2, piece.size.height * s / 2);
    return c.isNearHome(piece, box.globalToLocal(centre));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _showSaveDialog(context);
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final area =
                            Size(constraints.maxWidth, constraints.maxHeight);
                        if (!c.ready.value && !_requested) {
                          _requested = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) c.generate(area);
                          });
                        }
                        return _boardArea(context);
                      },
                    ),
                  ),
                  JigsawTray(controller: c),
                ],
              ),
            ),
            Obx(
              () => c.solved.value
                  ? Positioned.fill(
                      child: JigsawCelebration(
                        moves: c.moves.value,
                        pieces: c.totalPieces,
                        onPlayAgain: c.restart,
                        onNewImage: () => Navigator.of(context).pop(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardArea(BuildContext context) {
    return Stack(
      children: [
        Obx(
          () => Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: kBackgrounds[c.backgroundIndex.value].colors,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Obx(
            () => c.ready.value
                ? DragTarget<PuzzlePiece>(
                    // Always accept the drop so onAccept fires wherever the
                    // piece lands; we decide snapping from the actual drop
                    // position (robust against final-move timing).
                    onWillAcceptWithDetails: (_) => true,
                    onMove: (d) => c.setOverHome(_isNear(d)),
                    onLeave: (_) => c.setOverHome(false),
                    onAcceptWithDetails: (d) {
                      if (_isNear(d)) c.place(d.data);
                      c.endDrag();
                    },
                    builder: (context, _, _) => InteractiveViewer(
                      transformationController: c.transformationController,
                      minScale: 1,
                      maxScale: 3.5,
                      boundaryMargin: const EdgeInsets.all(120),
                      child: Center(
                        child: _BoardContent(key: _boardKey, controller: c),
                      ),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        Positioned(
          left: AppSpacing.sm,
          right: AppSpacing.sm,
          top: AppSpacing.sm,
          child: _TopRail(
            controller: c,
            onBack: () => _showSaveDialog(context),
            onBackground: () => _showBackgroundSheet(context),
            onReset: c.restart,
          ),
        ),
        Positioned(
          left: AppSpacing.md,
          top: 72,
          child: _Hud(controller: c),
        ),
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.lg,
          child: _ZoomButtons(controller: c),
        ),
      ],
    );
  }

  void _showSaveDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.extension_rounded, size: 22, color: scheme.primary),
            const SizedBox(width: 10),
            Text('Leave puzzle?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
        content: Obx(
          () => Text(
            'You\'ve placed ${c.placedCount.value} of ${c.totalPieces} pieces '
            '(${c.elapsedLabel} elapsed). Your progress will be lost if you leave.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () {
              c.pause();
              Navigator.of(ctx).pop();
              // Pop directly — the screen's PopScope (canPop:false) would block
              // maybePop and just re-open this dialog.
              Navigator.of(context).pop();
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showBackgroundSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Background',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (var i = 0; i < kBackgrounds.length; i++)
                    Obx(
                      () => GestureDetector(
                        onTap: () {
                          c.setBackground(i);
                          Navigator.of(ctx).pop();
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: kBackgrounds[i].colors,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: c.backgroundIndex.value == i
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.outlineVariant,
                                  width: c.backgroundIndex.value == i ? 3 : 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              kBackgrounds[i].name,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
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

/// The floating top rail, mirroring the painting canvas chrome: Back on the far
/// left, the view options centred, and a single Reset on the far right.
class _TopRail extends StatelessWidget {
  const _TopRail({
    required this.controller,
    required this.onBack,
    required this.onBackground,
    required this.onReset,
  });

  final JigsawController controller;
  final VoidCallback onBack;
  final VoidCallback onBackground;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return _RailCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          _RailIconButton(
            icon: Icons.home_rounded,
            tooltip: 'Home',
            onTap: onBack,
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Obx(
                    () => _RailIconButton(
                      icon: controller.hintOn.value
                          ? Icons.lightbulb_rounded
                          : Icons.lightbulb_outline_rounded,
                      tooltip: controller.hintOn.value
                          ? 'Hide picture guide'
                          : 'Show picture guide',
                      selected: controller.hintOn.value,
                      onTap: controller.toggleHint,
                    ),
                  ),
                  Obx(
                    () => _RailIconButton(
                      icon: controller.homeMarkerOn.value
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      tooltip: controller.homeMarkerOn.value
                          ? 'Hide piece marker'
                          : 'Show piece marker',
                      selected: controller.homeMarkerOn.value,
                      onTap: controller.toggleHomeMarker,
                    ),
                  ),
                  _RailIconButton(
                    icon: Icons.palette_outlined,
                    tooltip: 'Background',
                    onTap: onBackground,
                  ),
                ],
              ),
            ),
          ),
          _RailIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Reset',
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}

/// Shared surface for the floating control rails: a rounded, bordered panel
/// with a soft drop shadow so it reads as floating over the board.
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
            color: Colors.black.withValues(alpha: 0.18),
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

/// A single rail entry: a square, rounded, optionally-selected icon button.
class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
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
              width: 42,
              height: 42,
              child: Center(child: Icon(icon, size: 22, color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({super.key, required this.controller});

  final JigsawController controller;

  /// Thickness of the raised 3D frame drawn around the board well.
  static const double _rim = 14;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.fromSize(
      size: controller.boardSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Raised beveled rim drawn just outside the board so the assembled
          // picture sits in a 3D frame; pieces still fill the board 1:1.
          Positioned(
            left: -_rim,
            top: -_rim,
            right: -_rim,
            bottom: -_rim,
            child: const _BoardRim(),
          ),
          Positioned.fill(child: _Frame(controller: controller)),
          // Placed pieces (positioned relative to the board content origin).
          Obx(
            () => Stack(
              clipBehavior: Clip.none,
              children: [
                for (final p in controller.pieces)
                  if (p.placed.value)
                    Positioned(
                      key: ValueKey(p.id),
                      left: p.boardPosition.dx,
                      top: p.boardPosition.dy,
                      child: _PoppedPiece(
                        child: JigsawPieceWidget(
                          controller: controller,
                          piece: p,
                          placed: true,
                        ),
                      ),
                    ),
              ],
            ),
          ),
          // Home marker for the piece being dragged.
          Obx(() {
            final d = controller.draggingPiece.value;
            if (d == null || !controller.homeMarkerOn.value) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: d.boardPosition.dx,
              top: d.boardPosition.dy,
              child: JigsawHomeHighlight(
                piece: d,
                over: controller.overHome.value,
                color: scheme.primary,
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// The raised, beveled 3D frame surrounding the board — a light top-left to
/// dark bottom-right gradient plus a deep drop shadow so the puzzle looks like
/// it sits in a physical tray.
class _BoardRim extends StatelessWidget {
  const _BoardRim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFAFAFC), Color(0xFFCBCDD6), Color(0xFF8E909C)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
    );
  }
}

/// Plays a one-shot "snap into place" pop the first time a placed piece
/// appears on the board. Already-placed pieces keep their stable [ValueKey] so
/// they don't re-animate when the board rebuilds.
class _PoppedPiece extends StatelessWidget {
  const _PoppedPiece({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, t, child) =>
          Transform.scale(scale: 0.86 + 0.14 * t, child: child),
      child: child,
    );
  }
}

/// The recessed board "well": a sunken surface (the picture ghost lives here)
/// with an inner vignette so it reads as carved into the 3D frame.
class _Frame extends StatelessWidget {
  const _Frame({required this.controller});

  final JigsawController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final img = controller.image.value;
      final hint = controller.hintOn.value;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (img != null)
                Opacity(
                  opacity: hint ? 0.42 : 0.12,
                  child: RawImage(image: img, fit: BoxFit.fill),
                ),
              // Inner vignette — fakes the recessed-well shadow at the edges.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.95,
                    colors: [Color(0x00000000), Color(0x33000000)],
                    stops: [0.7, 1.0],
                  ),
                ),
              ),
              Obx(
                () => controller.placedCount.value == 0 && !hint
                    ? Center(
                        child: Text(
                          'Drag pieces here',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Compact progress pill (no timer): how many pieces are placed, a progress
/// bar, and the move count.
class _Hud extends StatelessWidget {
  const _Hud({required this.controller});

  final JigsawController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _RailCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Obx(
        () => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              '${controller.placedCount.value}/${controller.totalPieces}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: controller.totalPieces == 0
                      ? 0
                      : controller.placedCount.value / controller.totalPieces,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.touch_app_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              '${controller.moves.value}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.controller});

  final JigsawController controller;

  @override
  Widget build(BuildContext context) {
    return _RailCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailIconButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            onTap: () => controller.zoomBy(1.4),
          ),
          _RailIconButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onTap: () => controller.zoomBy(1 / 1.4),
          ),
          _RailIconButton(
            icon: Icons.fit_screen_outlined,
            tooltip: 'Fit',
            onTap: controller.resetZoom,
          ),
        ],
      ),
    );
  }
}
