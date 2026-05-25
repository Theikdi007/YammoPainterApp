import 'package:flutter/material.dart';

import 'drawing_tool.dart';

/// Sealed-style base for everything the painter renders into the user-paint
/// layer (strokes and bucket fills). Stored in time order in the
/// controller's `actions` list — the painter walks them in order so an
/// eraser only erases what was painted *before* it. Anything fill or
/// stroke placed afterwards stays visible.
abstract class DrawAction {
  const DrawAction();
}

/// One painted stroke (brush or eraser).
///
/// When [isPictureSpace] is true, [points] and [width] are in the active
/// template's natural coordinate system (the SVG viewBox) so they survive
/// canvas resizes — `Painter` converts back to canvas-space at draw time
/// using the current `BoxFit.contain` transform. `false` is free-draw mode
/// (no template; canvas-space).
class Stroke extends DrawAction {
  Stroke({
    required this.tool,
    required this.style,
    required this.color,
    required this.width,
    required this.points,
    required this.isPictureSpace,
  });

  final DrawingTool tool;
  final BrushStyle style;
  final Color color;
  final double width;
  final List<Offset> points;
  final bool isPictureSpace;
}

/// One bucket-fill action: paint [color] inside [region]. Stored in
/// picture-space and transformed at draw time, just like strokes.
class BucketFill extends DrawAction {
  BucketFill({
    required this.region,
    required this.color,
    required this.isPictureSpace,
  });

  final Path region;
  final Color color;
  final bool isPictureSpace;
}
