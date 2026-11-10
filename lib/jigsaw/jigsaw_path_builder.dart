import 'dart:math' as math;
import 'dart:ui';

/// Geometry for authentic, interlocking jigsaw pieces.
///
/// The key invariant that makes pieces tile with *no gaps and no overlaps*:
/// the boundary between two adjacent cells is generated **exactly once**
/// (in absolute board coordinates) and then consumed by both neighbours —
/// one walks it [appendForward], the other [appendReverse]. Because both
/// reference the identical curve, a tab on one piece is, by construction, the
/// matching blank on the other. The random tab direction per shared edge only
/// affects which way the knob bulges; tiling is guaranteed regardless.

/// One cubic Bézier segment: two control points and the end anchor. The start
/// anchor is implicit (the previous segment's end, or the edge's [JigsawEdge.start]).
class JigsawSeg {
  const JigsawSeg(this.c1, this.c2, this.p);
  final Offset c1;
  final Offset c2;
  final Offset p;
}

/// A single piece edge expressed as a chain of cubic segments in absolute
/// board coordinates.
class JigsawEdge {
  const JigsawEdge(this.start, this.segs);

  final Offset start;
  final List<JigsawSeg> segs;

  Offset get end => segs.last.p;

  /// Appends the edge to [path] walking from [start] to [end]. The caller must
  /// already be at [start] (via moveTo or a previous edge ending here).
  void appendForward(Path path) {
    for (final s in segs) {
      path.cubicTo(s.c1.dx, s.c1.dy, s.c2.dx, s.c2.dy, s.p.dx, s.p.dy);
    }
  }

  /// Appends the edge to [path] walking from [end] back to [start]. Reversing a
  /// cubic swaps its control points and steps the anchors backwards, so the
  /// rendered curve is geometrically identical to [appendForward] — just
  /// traversed the other way. The caller must already be at [end].
  void appendReverse(Path path) {
    for (var i = segs.length - 1; i >= 0; i--) {
      final anchor = i == 0 ? start : segs[i - 1].p;
      final s = segs[i];
      path.cubicTo(s.c2.dx, s.c2.dy, s.c1.dx, s.c1.dy, anchor.dx, anchor.dy);
    }
  }
}

/// Builds one edge from [start] to [end].
///
/// [tab] is `0` for a flat border edge, or `+1` / `-1` for an interior edge —
/// the sign chooses which side the knob bulges toward. The knob is a classic
/// narrow-necked jigsaw head whose control points overhang the neck so the
/// pieces physically lock.
JigsawEdge buildEdge(Offset start, Offset end, int tab) {
  final len = (end - start).distance;
  if (len == 0) return JigsawEdge(start, const [JigsawSeg(Offset.zero, Offset.zero, Offset.zero)]);

  final t = (end - start) / len; // unit tangent (along the edge)
  final n = Offset(-t.dy, t.dx); // unit normal (perpendicular)

  // Map a normalized point (a = fraction along, b = fraction perpendicular)
  // to absolute coordinates. `b` is scaled by the tab sign so the knob flips.
  Offset pt(double a, double b) =>
      start + t * (a * len) + n * (b * len * tab.toDouble());

  if (tab == 0) {
    // A straight line, expressed as a single (degenerate) cubic so border and
    // interior edges share the same append machinery.
    return JigsawEdge(start, [
      JigsawSeg(start + t * (0.33 * len), start + t * (0.66 * len), end),
    ]);
  }

  // Symmetric knob: shoulders at 0.40 / 0.60, head spanning ~0.30..0.70 with an
  // apex around 0.27 — wider than the neck so adjacent pieces interlock.
  return JigsawEdge(start, [
    JigsawSeg(pt(0.13, 0), pt(0.27, 0), pt(0.40, 0)), // run-in to the left shoulder
    JigsawSeg(pt(0.30, 0), pt(0.30, 0.20), pt(0.42, 0.20)), // up the left neck
    JigsawSeg(pt(0.48, 0.27), pt(0.52, 0.27), pt(0.58, 0.20)), // over the rounded head
    JigsawSeg(pt(0.70, 0.20), pt(0.70, 0), pt(0.60, 0)), // down the right neck
    JigsawSeg(pt(0.73, 0), pt(0.87, 0), end), // run-out to the right shoulder
  ]);
}

/// The generated geometry for one piece, in board coordinates.
class PieceSpec {
  PieceSpec({
    required this.row,
    required this.col,
    required this.path,
    required this.bounds,
  });

  final int row;
  final int col;

  /// Closed silhouette including tab overhangs, in board space.
  final Path path;

  /// `path.getBounds()`, cached.
  final Rect bounds;
}

/// Slices a [size]-sized board into a [rows] × [cols] grid of interlocking
/// pieces. [rng] drives the per-edge tab direction.
List<PieceSpec> buildPieces({
  required Size size,
  required int rows,
  required int cols,
  required math.Random rng,
}) {
  final cellW = size.width / cols;
  final cellH = size.height / rows;

  // Interior horizontal edges: hEdge[r][c] is the seam *below* row r,
  // built left → right.
  final hEdge = List.generate(
    rows - 1,
    (r) => List.generate(cols, (c) {
      final y = (r + 1) * cellH;
      final sign = rng.nextBool() ? 1 : -1;
      return buildEdge(Offset(c * cellW, y), Offset((c + 1) * cellW, y), sign);
    }),
  );

  // Interior vertical edges: vEdge[r][c] is the seam to the *right* of col c,
  // built top → bottom.
  final vEdge = List.generate(
    rows,
    (r) => List.generate(cols - 1, (c) {
      final x = (c + 1) * cellW;
      final sign = rng.nextBool() ? 1 : -1;
      return buildEdge(Offset(x, r * cellH), Offset(x, (r + 1) * cellH), sign);
    }),
  );

  final pieces = <PieceSpec>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final tl = Offset(c * cellW, r * cellH);
      final tr = Offset((c + 1) * cellW, r * cellH);
      final br = Offset((c + 1) * cellW, (r + 1) * cellH);
      final bl = Offset(c * cellW, (r + 1) * cellH);

      final path = Path()..moveTo(tl.dx, tl.dy);

      // Walk clockwise: top (→), right (↓), bottom (←), left (↑). For shared
      // edges, the piece "below"/"right" walks forward; the piece
      // "above"/"left" walks the same seam in reverse.
      if (r == 0) {
        path.lineTo(tr.dx, tr.dy);
      } else {
        hEdge[r - 1][c].appendForward(path); // top = seam above, L→R
      }

      if (c == cols - 1) {
        path.lineTo(br.dx, br.dy);
      } else {
        vEdge[r][c].appendForward(path); // right = seam right, T→B
      }

      if (r == rows - 1) {
        path.lineTo(bl.dx, bl.dy);
      } else {
        hEdge[r][c].appendReverse(path); // bottom = seam below, R→L
      }

      if (c == 0) {
        path.lineTo(tl.dx, tl.dy);
      } else {
        vEdge[r][c - 1].appendReverse(path); // left = seam left, B→T
      }

      path.close();
      pieces.add(
        PieceSpec(row: r, col: c, path: path, bounds: path.getBounds()),
      );
    }
  }
  return pieces;
}
