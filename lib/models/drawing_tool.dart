/// Which gesture-driven action the user is performing.
///
/// `brush` and `eraser` consume pan gestures and produce a [Stroke]; `move`
/// also consumes pan gestures but drags an existing element; `bucket` and
/// `eyedropper` consume single-tap gestures (handled in the controller's
/// `handleTap`).
enum DrawingTool { brush, eraser, bucket, eyedropper, move }

/// Visual variants of the brush tool. The painter maps each style onto a
/// `Paint` configuration (cap, alpha, mask filter) — see `_paintFor` in
/// `lib/widgets/painter.dart`.
enum BrushStyle { round, soft, marker, pencil }

/// How the canvas treats an active picture (template).
///
/// `color` is the coloring-book behavior: brush strokes are clipped to the
/// picture's regions and the line art is drawn dark on top. `draw` is the
/// free-draw / tracing behavior: strokes aren't clipped, and when a picture is
/// present it renders faintly *underneath* the strokes as a tracing guide.
///
/// Free-draw (no template) is always conceptually `draw`. The painter only
/// distinguishes the two when a template is set — see `lib/widgets/painter.dart`.
enum PaintMode { draw, color }
