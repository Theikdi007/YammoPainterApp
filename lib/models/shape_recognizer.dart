import 'dart:math' as math;
import 'dart:ui';

/// A freehand stroke snapped to a clean primitive.
class RecognizedShape {
  const RecognizedShape(this.points, {required this.closed});

  final List<Offset> points;

  /// Connects the last point back to the first (polygons / ellipses).
  final bool closed;
}

/// Best-effort recognition of a freehand stroke as a straight line, triangle,
/// quadrilateral, or ellipse/circle. Returns `null` when the stroke doesn't
/// clearly match one — the caller then keeps it as freehand.
///
/// Operates in whatever coordinate space [raw] is in: every threshold is
/// relative to the stroke's bounding-box diagonal, so it behaves identically in
/// canvas-space (free-draw) and picture-space (template) strokes.
RecognizedShape? recognizeShape(List<Offset> raw) {
  if (raw.length < 6) return null;

  var minX = raw.first.dx, maxX = raw.first.dx;
  var minY = raw.first.dy, maxY = raw.first.dy;
  for (final p in raw) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final w = maxX - minX;
  final h = maxY - minY;
  final diag = math.sqrt(w * w + h * h);
  if (diag < 24) return null; // a dot / tiny scribble

  final start = raw.first;
  final end = raw.last;
  final closingGap = (end - start).distance;

  var pathLen = 0.0;
  for (var i = 0; i < raw.length - 1; i++) {
    pathLen += (raw[i + 1] - raw[i]).distance;
  }

  // A loop: ends near where it started, with enough length to be a real shape
  // (not a short back-and-forth).
  final isClosed = closingGap < diag * 0.33 && pathLen > diag * 1.2;

  // Open stroke → only a near-straight line qualifies (path barely longer than
  // its chord).
  if (!isClosed) {
    if (closingGap > diag * 0.6 && pathLen / closingGap < 1.15) {
      return RecognizedShape([start, end], closed: false);
    }
    return null;
  }

  // Circle vs polygon: isoperimetric compactness (4π·area / perimeter²) is ~1
  // for a circle, π/4≈0.785 for a perfect square, and lower for triangles or
  // any wobbly perimeter. A clean threshold above the square's value separates
  // round loops from cornered ones.
  final perimeter = pathLen + closingGap;
  final area = _polygonArea(raw);
  final compactness =
      perimeter > 0 ? (4 * math.pi * area) / (perimeter * perimeter) : 0.0;
  if (compactness >= 0.82) {
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    return RecognizedShape(_ellipse(center, w / 2, h / 2), closed: true);
  }

  // Polygon: simplify with a growing tolerance until the dominant corners
  // resolve to a triangle or quad.
  for (final f in const [0.05, 0.08, 0.11, 0.15]) {
    final verts = _rdp(raw, diag * f);
    if (verts.length > 1 && (verts.last - verts.first).distance < diag * 0.18) {
      verts.removeLast();
    }
    if (verts.length == 3) {
      return RecognizedShape(verts, closed: true);
    }
    if (verts.length == 4) {
      // Snap an upright quad to a clean axis-aligned rectangle; keep a rotated
      // quad as-is so diamonds aren't squared off.
      if (_isAxisAligned(verts)) {
        return RecognizedShape([
          Offset(minX, minY),
          Offset(maxX, minY),
          Offset(maxX, maxY),
          Offset(minX, maxY),
        ], closed: true);
      }
      return RecognizedShape(verts, closed: true);
    }
  }
  return null;
}

/// Shoelace area of the (assumed closed) polyline.
double _polygonArea(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a.abs() / 2;
}

/// True when every edge of the closed [v] runs within ~20° of horizontal or
/// vertical — i.e. an upright rectangle rather than a rotated quad.
bool _isAxisAligned(List<Offset> v) {
  for (var i = 0; i < v.length; i++) {
    final a = v[i];
    final b = v[(i + 1) % v.length];
    final angle = math.atan2((b.dy - a.dy).abs(), (b.dx - a.dx).abs()) *
        180 /
        math.pi; // folded into [0, 90]
    if (angle >= 20 && angle <= 70) return false;
  }
  return true;
}

List<Offset> _ellipse(Offset c, double rx, double ry) {
  const segments = 64;
  return [
    for (var i = 0; i < segments; i++)
      Offset(
        c.dx + rx * math.cos((i / segments) * 2 * math.pi),
        c.dy + ry * math.sin((i / segments) * 2 * math.pi),
      ),
  ];
}

/// Ramer–Douglas–Peucker polyline simplification: drops points that lie within
/// [epsilon] of the line between kept neighbors, leaving the dominant corners.
List<Offset> _rdp(List<Offset> pts, double epsilon) {
  if (pts.length < 3) return List<Offset>.of(pts);
  var dmax = 0.0;
  var index = 0;
  final a = pts.first;
  final b = pts.last;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _perpDistance(pts[i], a, b);
    if (d > dmax) {
      dmax = d;
      index = i;
    }
  }
  if (dmax > epsilon) {
    final left = _rdp(pts.sublist(0, index + 1), epsilon);
    final right = _rdp(pts.sublist(index), epsilon);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [a, b];
}

double _perpDistance(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return (p - a).distance;
  final cross = ((p.dx - a.dx) * dy - (p.dy - a.dy) * dx).abs();
  return cross / len;
}
