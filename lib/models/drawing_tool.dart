/// Which gesture-driven action the user is performing.
///
/// `brush` and `eraser` consume pan gestures and produce a [Stroke];
/// `bucket` and `eyedropper` consume single-tap gestures (handled in the
/// controller's `handleTap`).
enum DrawingTool { brush, eraser, bucket, eyedropper }

/// Visual variants of the brush tool. The painter maps each style onto a
/// `Paint` configuration (cap, alpha, mask filter) — see `_paintFor` in
/// `lib/widgets/painter.dart`.
enum BrushStyle { round, soft, marker, pencil }
