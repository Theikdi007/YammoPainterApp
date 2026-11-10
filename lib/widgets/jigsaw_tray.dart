import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/jigsaw_controller.dart';
import '../models/puzzle_piece.dart';
import 'jigsaw_piece_view.dart';

/// Scrollable bottom tray of remaining pieces. Each piece is a
/// [LongPressDraggable] — a quick horizontal swipe scrolls the tray, a short
/// press-and-hold picks a piece up to drag onto the board.
class JigsawTray extends StatelessWidget {
  const JigsawTray({super.key, required this.controller});

  final JigsawController controller;

  static const double height = 132;
  static const double itemBox = 92;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 2),
              child: Row(
                children: [
                  Obx(
                    () => Text(
                      '${controller.unplacedCount} pieces left',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Obx(
                    () => FilterChip(
                      label: const Text('Edges'),
                      avatar: Icon(
                        Icons.border_outer_rounded,
                        size: 18,
                        color: controller.edgesOnly.value
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                      selected: controller.edgesOnly.value,
                      onSelected: (_) => controller.toggleEdges(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Obx(() {
                final tray = controller.trayPieces;
                if (tray.isEmpty) {
                  return Center(
                    child: Text(
                      controller.unplacedCount == 0
                          ? 'All pieces placed!'
                          : 'Turn off Edges to see the rest',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: tray.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) =>
                      _TrayItem(controller: controller, piece: tray[i]),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrayItem extends StatelessWidget {
  const _TrayItem({required this.controller, required this.piece});

  final JigsawController controller;
  final PuzzlePiece piece;

  @override
  Widget build(BuildContext context) {
    final card = _Card(
      scheme: Theme.of(context).colorScheme,
      child: FittedBox(
        child: JigsawPieceWidget(controller: controller, piece: piece),
      ),
    );

    return LongPressDraggable<PuzzlePiece>(
      data: piece,
      delay: const Duration(milliseconds: 120),
      // Anchor the feedback so the pointer sits at the piece's centre.
      dragAnchorStrategy: (draggable, context, position) {
        final s = controller.currentScale;
        return Offset(piece.size.width * s / 2, piece.size.height * s / 2);
      },
      onDragStarted: () => controller.startDrag(piece),
      onDragEnd: (_) => controller.endDrag(),
      feedback: _FeedbackPiece(controller: controller, piece: piece),
      childWhenDragging: Opacity(opacity: 0.25, child: card),
      child: card,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.scheme, required this.child});
  final ColorScheme scheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: JigsawTray.itemBox,
        height: JigsawTray.itemBox,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: child,
      ),
    );
  }
}

/// The piece that follows the finger — scaled to the current board zoom so it
/// matches the size it will become once dropped. Rebuilds with the zoom.
class _FeedbackPiece extends StatelessWidget {
  const _FeedbackPiece({required this.controller, required this.piece});

  final JigsawController controller;
  final PuzzlePiece piece;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: controller.transformationController,
        builder: (context, _) {
          final s = controller.currentScale;
          return SizedBox(
            width: piece.size.width * s,
            height: piece.size.height * s,
            child: FittedBox(
              child: JigsawPieceWidget(
                controller: controller,
                piece: piece,
                lift: true,
              ),
            ),
          );
        },
      ),
    );
  }
}
