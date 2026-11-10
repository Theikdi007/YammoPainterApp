import 'dart:ui';

import 'package:get/get.dart';

/// One jigsaw piece. Geometry is fixed at generation time. While a piece is in
/// the tray it isn't positioned; once dropped on its home it becomes [placed]
/// and is rendered on the board at [boardPosition].
class PuzzlePiece {
  PuzzlePiece({
    required this.id,
    required this.row,
    required this.col,
    required this.localPath,
    required this.size,
    required this.imageOffset,
    required this.boardPosition,
    required this.boardCenter,
    required this.isEdge,
  });

  final int id;
  final int row;
  final int col;

  /// Silhouette in piece-local space (origin at the widget's top-left, shadow
  /// padding already baked in).
  final Path localPath;

  /// Widget size — piece bounds plus shadow padding on every side.
  final Size size;

  /// Local-space translation applied before drawing the full board image, so
  /// only this piece's slice shows through the clip.
  final Offset imageOffset;

  /// Board-space top-left of the piece widget when locked in place.
  final Offset boardPosition;

  /// Board-space centre of this piece's home — used for the drop snap test.
  final Offset boardCenter;

  /// True for border/corner pieces (a flat outer edge). Drives the tray's
  /// "Edges" filter.
  final bool isEdge;

  /// True once correctly dropped; placed pieces are locked on the board.
  final RxBool placed = false.obs;
}
