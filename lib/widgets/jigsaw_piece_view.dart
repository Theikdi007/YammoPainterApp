import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/jigsaw_controller.dart';
import '../models/puzzle_piece.dart';

/// Renders a single piece at its natural board-space size. Callers scale it:
/// the board shows it 1:1 inside the zoomable viewer, the tray wraps it in a
/// [FittedBox], and the drag feedback scales it to the current zoom.
class JigsawPieceWidget extends StatelessWidget {
  const JigsawPieceWidget({
    super.key,
    required this.controller,
    required this.piece,
    this.lift = false,
    this.placed = false,
  });

  final JigsawController controller;
  final PuzzlePiece piece;

  /// Raises the shadow (used for the drag feedback).
  final bool lift;
  final bool placed;

  @override
  Widget build(BuildContext context) {
    final image = controller.image.value;
    if (image == null) return SizedBox.fromSize(size: piece.size);
    return SizedBox.fromSize(
      size: piece.size,
      child: CustomPaint(
        painter: _JigsawPiecePainter(
          image: image,
          boardSize: controller.boardSize,
          piece: piece,
          lift: lift,
          placed: placed,
        ),
      ),
    );
  }
}

class _JigsawPiecePainter extends CustomPainter {
  _JigsawPiecePainter({
    required this.image,
    required this.boardSize,
    required this.piece,
    required this.lift,
    required this.placed,
  });

  final ui.Image image;
  final Size boardSize;
  final PuzzlePiece piece;
  final bool lift;
  final bool placed;

  @override
  void paint(Canvas canvas, Size size) {
    final path = piece.localPath;
    final bounds = path.getBounds();

    // 1) Drop shadow — deeper while lifted (being dragged); placed pieces keep
    // a little lift so the assembled puzzle reads as a raised 3D surface.
    final elev = lift ? 12.0 : (placed ? 2.5 : 3.5);
    canvas.drawPath(
      path.shift(Offset(0, elev)),
      Paint()
        ..color = Colors.black.withValues(alpha: lift ? 0.46 : (placed ? 0.24 : 0.30))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lift ? 11 : (placed ? 3 : 5)),
    );

    // 2) The HD image slice, clipped to the silhouette.
    canvas.save();
    canvas.clipPath(path, doAntiAlias: true);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        piece.imageOffset.dx,
        piece.imageOffset.dy,
        boardSize.width,
        boardSize.height,
      ),
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );

    // 3) Glossy top highlight — a soft white sheen fading down the piece gives
    // it a rounded, moulded-plastic 3D feel.
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          bounds.topCenter,
          bounds.bottomCenter,
          [Colors.white.withValues(alpha: 0.28), const Color(0x00FFFFFF)],
          const [0.0, 0.5],
        ),
    );

    // 4) Embossed bevel — top-left highlight + bottom-right inner shadow, now
    // deeper for a more pronounced raised edge.
    canvas.save();
    canvas.translate(-1.6, -1.6);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = Colors.white.withValues(alpha: 0.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
    canvas.restore();
    canvas.save();
    canvas.translate(1.6, 1.6);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = Colors.black.withValues(alpha: 0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
    canvas.restore();
    canvas.restore(); // drop the silhouette clip

    // 5) Crisp boundary so assembled pieces stay legible.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.black.withValues(alpha: 0.26),
    );
  }

  @override
  bool shouldRepaint(_JigsawPiecePainter old) =>
      old.lift != lift ||
      old.placed != placed ||
      old.image != image ||
      old.boardSize != boardSize ||
      old.piece != piece;
}

/// A glowing outline drawn at a piece's home on the board while it's being
/// dragged — green once the drag is over the correct spot.
class JigsawHomeHighlight extends StatelessWidget {
  const JigsawHomeHighlight({
    super.key,
    required this.piece,
    required this.over,
    required this.color,
  });

  final PuzzlePiece piece;
  final bool over;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: piece.size,
      child: CustomPaint(
        painter: _HomeHighlightPainter(
          path: piece.localPath,
          over: over,
          color: color,
        ),
      ),
    );
  }
}

class _HomeHighlightPainter extends CustomPainter {
  _HomeHighlightPainter({
    required this.path,
    required this.over,
    required this.color,
  });

  final Path path;
  final bool over;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = over ? const Color(0xFF35D07F) : color;
    canvas.drawPath(
      path,
      Paint()
        ..color = c.withValues(alpha: over ? 0.22 : 0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = over ? 4 : 2.5
        ..color = c.withValues(alpha: over ? 1.0 : 0.7)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, over ? 5 : 2),
    );
  }

  @override
  bool shouldRepaint(_HomeHighlightPainter old) =>
      old.over != over || old.path != path || old.color != color;
}
