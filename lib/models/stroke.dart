import 'dart:ui' as ui;

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
///
/// [clipToRegions] captures, at stroke time, whether this stroke should be
/// confined to the picture's regions (coloring) or flow freely (free-draw /
/// tracing over a guide). Capturing it per-stroke — like [color]/[width] —
/// means flipping the canvas Draw/Color toggle later never re-clips or drops
/// strokes the user already committed.
class Stroke extends DrawAction {
  Stroke({
    required this.tool,
    required this.style,
    required this.color,
    required this.width,
    required this.points,
    required this.isPictureSpace,
    this.clipToRegions = false,
    this.clipPath,
    this.isShape = false,
    this.closed = false,
  });

  final DrawingTool tool;
  final BrushStyle style;
  final Color color;
  final double width;
  final List<Offset> points;
  final bool isPictureSpace;
  final bool clipToRegions;

  /// A precomputed, canvas-space clip the stroke is confined to. Used on
  /// outline-only coloring pages (which have no vector regions): the controller
  /// flood-fills the bounded area under the finger and builds this path so brush
  /// paint stays inside the black lines. Null otherwise (region SVGs clip via
  /// the painter's vector regions; free-draw doesn't clip).
  final Path? clipPath;

  /// When true this stroke was snapped to a clean primitive (line / polygon /
  /// ellipse) by the shape recognizer, so the painter draws an even-width path
  /// through [points] instead of the hand-drawn tapered smoothing. [closed]
  /// connects the last point back to the first (polygons / ellipses).
  final bool isShape;
  final bool closed;
}

/// A flood-fill result for free-draw / tracing, where hand-drawn boundaries
/// have no vector [BucketFill] region to clip against.
///
/// [image] is an RGBA bitmap the size of the canvas at fill time: filled
/// pixels carry the chosen color, everything else is transparent. The painter
/// draws it 1:1 at the origin (free-draw paint is canvas-space and doesn't
/// scale), so the fill stays aligned with the strokes that bounded it.
class RasterFill extends DrawAction {
  RasterFill({
    required this.image,
    required this.size,
    this.offset = Offset.zero,
    this.bounds,
  });

  final ui.Image image;

  /// Canvas size when the fill was captured ( == [image] dimensions).
  final Size size;

  /// Translation applied by the Move tool (the image draws shifted by this).
  final Offset offset;

  /// Tight bounding box of the filled pixels (pre-[offset]), used for Move
  /// hit-testing — the image itself is canvas-sized and mostly transparent.
  final Rect? bounds;
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
