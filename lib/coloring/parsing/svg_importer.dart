import 'dart:ui';

import 'package:xml/xml.dart';

import '../coloring_page.dart';
import '../coloring_page_manifest.dart';
import 'svg_path_parser.dart';

/// Heuristic SVG → manifest converter.
///
/// Classification priority for each `<path>`:
///   1. Closest ancestor `<g id="regions">`  → region.
///   2. Closest ancestor `<g id="outline">`  → outline.
///   3. Self/ancestor `class` token includes `outline` → outline.
///   4. `fill="none"` (or fill absent) AND `stroke` set to a non-`none` value
///      → outline.
///   5. Otherwise → region.
///
/// Sizing:
///   - Prefers `viewBox="x y w h"` on the root `<svg>`.
///   - Falls back to numeric `width` / `height` attributes (px assumed) when
///     no viewBox is present — common with vectorizer output (e.g. potrace).
///
/// Transforms:
///   - `translate(tx, ty)` — accumulated up the ancestor chain and baked into
///     each path's coordinate data. Multiple `translate(...)` chained
///     in one attribute is supported (sums them).
///   - Other transform functions (`scale`, `rotate`, `matrix`, `skewX`,
///     `skewY`) are NOT supported — the importer throws so you know to
///     flatten them in your SVG editor (Inkscape: Object → Flatten Transforms).
///
/// What this function does NOT do:
/// - Preserve fill/stroke colors (only structural classification).
/// - Resolve `<use>` / `<symbol>` / CSS.
Future<ColoringPageManifest> importRawSvg(String svgContent) async {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(svgContent);
  } catch (e) {
    throw ColoringParseException(
      'SVG content is not well-formed XML',
      cause: e,
    );
  }

  final svgs = doc.findAllElements('svg');
  if (svgs.isEmpty) {
    throw ColoringParseException('No <svg> element found');
  }
  final svg = svgs.first;

  final viewBox = _readViewBox(svg);

  final regions = <String>[];
  final regionFills = <String?>[];
  final outline = <String>[];

  for (final path in svg.findAllElements('path')) {
    final translate = _accumulatedTranslate(path);
    final d = path.getAttribute('d');
    if (d == null || d.trim().isEmpty) continue;
    final shifted = (translate.tx == 0 && translate.ty == 0)
        ? d
        : _applyTranslate(d, translate.tx, translate.ty);
    if (_isOutline(path)) {
      outline.add(shifted);
    } else {
      regions.add(shifted);
      // Preserve the source `fill` so the eyedropper can fall back to it
      // when canvas pixel sampling is unreliable. `null` for paths with no
      // fill or `fill="none"`.
      final fill = path.getAttribute('fill');
      regionFills.add((fill == null || fill == 'none') ? null : fill);
    }
  }

  // Heuristic mode: no explicit <g id="regions"> grouping. Drop any region
  // whose bounding box covers ~the full viewBox — vectorizer output (potrace
  // --color and friends) emits the source's background as a giant filled
  // path that would otherwise capture every stroke landing outside a real
  // character region. Bounded to the first 5 paths because vectorizers emit
  // backgrounds early and parsing thousands of paths is wasteful.
  final hasExplicitRegionsGroup = doc.findAllElements('g').any(
        (g) => g.getAttribute('id') == 'regions',
      );
  if (!hasExplicitRegionsGroup && regions.isNotEmpty) {
    final vbArea = viewBox.width * viewBox.height;
    final scanLimit = regions.length < 5 ? regions.length : 5;
    for (var i = scanLimit - 1; i >= 0; i--) {
      try {
        final bounds = parsePath(regions[i]).getBounds();
        if (bounds.width * bounds.height >= 0.95 * vbArea) {
          regions.removeAt(i);
          regionFills.removeAt(i);
        }
      } catch (_) {
        // Unparseable path — leave it; downstream will surface its own error.
      }
    }
  }

  return ColoringPageManifest(
    viewBox: viewBox,
    regions: regions,
    regionFills: regionFills,
    outline: outline,
    name: svg.getAttribute('data-name'),
  );
}

// ---------------------------------------------------------------------------
// Sizing
// ---------------------------------------------------------------------------

Size _readViewBox(XmlElement svg) {
  final viewBoxAttr = svg.getAttribute('viewBox');
  if (viewBoxAttr != null) {
    final parts = viewBoxAttr.trim().split(RegExp(r'[\s,]+'));
    if (parts.length != 4) {
      throw ColoringParseException(
        'Unexpected viewBox value: "$viewBoxAttr" (expected "x y w h")',
      );
    }
    final w = double.tryParse(parts[2]);
    final h = double.tryParse(parts[3]);
    if (w == null || h == null) {
      throw ColoringParseException(
        'viewBox width/height are not parseable: "$viewBoxAttr"',
      );
    }
    return Size(w, h);
  }
  // Fall back to width/height (px-only).
  final w = _parseLength(svg.getAttribute('width'));
  final h = _parseLength(svg.getAttribute('height'));
  if (w == null || h == null) {
    throw ColoringParseException(
      '<svg> needs either a viewBox or numeric width/height attributes',
    );
  }
  return Size(w, h);
}

double? _parseLength(String? value) {
  if (value == null) return null;
  final trimmed = value.trim().replaceAll(RegExp(r'px$'), '');
  return double.tryParse(trimmed);
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

bool _isOutline(XmlElement path) {
  for (final el in <XmlElement>[path, ...path.ancestors.whereType<XmlElement>()]) {
    final id = el.getAttribute('id');
    if (id == 'regions') return false;
    if (id == 'outline') return true;
  }
  for (final el in <XmlElement>[path, ...path.ancestors.whereType<XmlElement>()]) {
    final cls = el.getAttribute('class');
    if (cls != null && cls.split(RegExp(r'\s+')).contains('outline')) {
      return true;
    }
  }
  // Fill-darkness rule for unstructured SVGs (potrace --color, etc.):
  // dark fills are usually line art (the "black border"); light fills are
  // the colorable interiors. Without this split, a vectorizer dump treats
  // every path as a region and strokes have nothing meaningful to clip to.
  final fill = path.getAttribute('fill');
  if (fill != null && fill != 'none') {
    final lum = _relativeLuminance(fill);
    if (lum != null) return lum < 0.55;
  }
  // Stroke-only path → outline.
  final stroke = path.getAttribute('stroke');
  final hasStroke = stroke != null && stroke != 'none';
  final fillIsNone = fill == null || fill == 'none';
  return fillIsNone && hasStroke;
}

/// BT.709 luminance in [0, 1]. Returns null if [color] can't be parsed —
/// `_isOutline` falls back to the fill/stroke heuristic in that case.
double? _relativeLuminance(String color) {
  final rgb = _parseRgb(color);
  if (rgb == null) return null;
  return (0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b) / 255.0;
}

/// Parses an SVG color string (`#RGB`, `#RRGGBB`, `rgb(...)`, or one of the
/// handful of named colors handled by the importer's heuristic) into a
/// dart:ui [Color]. Returns null when the input doesn't match.
///
/// Public so the page loader can resolve manifest `regionFills` to typed
/// colors without re-implementing the same regex set.
Color? parseSvgColor(String input) {
  final rgb = _parseRgb(input);
  if (rgb == null) return null;
  return Color.fromARGB(0xFF, rgb.r, rgb.g, rgb.b);
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
}

_Rgb? _parseRgb(String input) {
  final s = input.trim().toLowerCase();
  if (s.startsWith('#')) {
    if (s.length == 4) {
      // #RGB → #RRGGBB
      final r = int.tryParse(s[1] * 2, radix: 16);
      final g = int.tryParse(s[2] * 2, radix: 16);
      final b = int.tryParse(s[3] * 2, radix: 16);
      if (r == null || g == null || b == null) return null;
      return _Rgb(r, g, b);
    }
    if (s.length == 7) {
      final r = int.tryParse(s.substring(1, 3), radix: 16);
      final g = int.tryParse(s.substring(3, 5), radix: 16);
      final b = int.tryParse(s.substring(5, 7), radix: 16);
      if (r == null || g == null || b == null) return null;
      return _Rgb(r, g, b);
    }
    return null;
  }
  final rgbMatch = RegExp(r'^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$').firstMatch(s);
  if (rgbMatch != null) {
    return _Rgb(
      int.parse(rgbMatch.group(1)!),
      int.parse(rgbMatch.group(2)!),
      int.parse(rgbMatch.group(3)!),
    );
  }
  // A handful of common named colors. SVG spec has 147 — we add only the
  // ones that move the dark-vs-light decision.
  switch (s) {
    case 'black':
      return const _Rgb(0, 0, 0);
    case 'white':
      return const _Rgb(255, 255, 255);
    case 'gray':
    case 'grey':
      return const _Rgb(128, 128, 128);
    case 'red':
      return const _Rgb(255, 0, 0);
    case 'green':
      return const _Rgb(0, 128, 0);
    case 'blue':
      return const _Rgb(0, 0, 255);
    case 'yellow':
      return const _Rgb(255, 255, 0);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Transform handling — translate-only, accumulated up the ancestor chain.
// ---------------------------------------------------------------------------

class _Translate {
  const _Translate(this.tx, this.ty);
  final double tx;
  final double ty;
}

_Translate _accumulatedTranslate(XmlElement path) {
  var tx = 0.0;
  var ty = 0.0;
  for (final el in <XmlElement>[path, ...path.ancestors.whereType<XmlElement>()]) {
    final t = _parseTranslate(el.getAttribute('transform'), el);
    if (t != null) {
      tx += t.tx;
      ty += t.ty;
    }
  }
  return _Translate(tx, ty);
}

/// Parses a transform attribute that contains ONLY one or more translate(...)
/// calls. Anything else throws so the caller knows to flatten in their editor.
_Translate? _parseTranslate(String? attr, XmlElement el) {
  if (attr == null) return null;
  final trimmed = attr.trim();
  if (trimmed.isEmpty) return null;

  var tx = 0.0;
  var ty = 0.0;
  final fnRe = RegExp(r'(\w+)\s*\(([^)]*)\)');
  var matched = false;
  for (final m in fnRe.allMatches(trimmed)) {
    matched = true;
    final fn = m.group(1)!;
    final args = m
        .group(2)!
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .map(double.parse)
        .toList(growable: false);
    if (fn != 'translate') {
      throw ColoringParseException(
        '<${el.name.local}> uses transform="$attr" — only translate(x[, y]) '
        'is supported. Flatten other transforms in your SVG editor first.',
      );
    }
    if (args.isEmpty || args.length > 2) {
      throw ColoringParseException(
        'translate(...) needs 1 or 2 numbers, got ${args.length}',
      );
    }
    tx += args[0];
    ty += args.length == 2 ? args[1] : 0.0;
  }
  if (!matched) {
    throw ColoringParseException(
      'Unrecognised transform attribute "$attr"',
    );
  }
  return _Translate(tx, ty);
}

// ---------------------------------------------------------------------------
// Path-data shifting
// ---------------------------------------------------------------------------

const Set<String> _commandLetters = <String>{
  'M', 'm', 'L', 'l', 'H', 'h', 'V', 'v',
  'C', 'c', 'S', 's', 'Q', 'q', 'T', 't',
  'A', 'a', 'Z', 'z',
};

int _argsPer(String cmd) {
  switch (cmd.toUpperCase()) {
    case 'M':
    case 'L':
    case 'T':
      return 2;
    case 'H':
    case 'V':
      return 1;
    case 'C':
      return 6;
    case 'S':
    case 'Q':
      return 4;
    case 'A':
      return 7;
    case 'Z':
      return 0;
  }
  throw ColoringParseException('Unknown SVG path command: "$cmd"');
}

class _Tok {
  const _Tok.cmd(this.command) : number = null;
  const _Tok.num(this.number) : command = null;
  final String? command;
  final double? number;
}

final RegExp _tokenRe = RegExp(
  r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?',
);

List<_Tok> _tokenize(String d) {
  final out = <_Tok>[];
  for (final m in _tokenRe.allMatches(d)) {
    final s = m.group(0)!;
    if (s.length == 1 && _commandLetters.contains(s)) {
      out.add(_Tok.cmd(s));
    } else {
      out.add(_Tok.num(double.parse(s)));
    }
  }
  return out;
}

/// Shifts every absolute coordinate in `d` by (tx, ty). Relative commands are
/// left intact. The very first command of the path, if it is a lowercase 'm',
/// has its first coordinate pair treated as absolute per the SVG spec.
String _applyTranslate(String d, double tx, double ty) {
  final tokens = _tokenize(d);
  if (tokens.isEmpty) return d;

  final out = StringBuffer();
  var i = 0;
  var isFirstCommand = true;

  while (i < tokens.length) {
    final tok = tokens[i];
    if (tok.command == null) {
      i++; // stray number — skip
      continue;
    }
    final cmd = tok.command!;
    out.write('$cmd ');
    i++;

    final n = _argsPer(cmd);
    if (n == 0) {
      isFirstCommand = false;
      continue;
    }

    final isAbsolute = cmd == cmd.toUpperCase();
    var firstPair = true;

    while (i + n <= tokens.length && tokens[i].command == null) {
      final args = <double>[
        for (var k = 0; k < n; k++) tokens[i + k].number!,
      ];
      i += n;

      // Spec quirk: if the path begins with lowercase 'm', the FIRST pair is
      // interpreted as absolute. Subsequent pairs in that same group remain
      // relative.
      final treatAsAbsolute =
          isAbsolute || (isFirstCommand && firstPair && cmd == 'm');
      if (treatAsAbsolute) _shiftCoords(cmd, args, tx, ty);

      for (final v in args) {
        out.write('${_fmt(v)} ');
      }
      firstPair = false;
    }

    isFirstCommand = false;
  }
  return out.toString().trimRight();
}

void _shiftCoords(String cmd, List<double> args, double tx, double ty) {
  switch (cmd.toUpperCase()) {
    case 'M':
    case 'L':
    case 'T':
      args[0] += tx;
      args[1] += ty;
    case 'H':
      args[0] += tx;
    case 'V':
      args[0] += ty;
    case 'C':
      args[0] += tx;
      args[1] += ty;
      args[2] += tx;
      args[3] += ty;
      args[4] += tx;
      args[5] += ty;
    case 'S':
    case 'Q':
      args[0] += tx;
      args[1] += ty;
      args[2] += tx;
      args[3] += ty;
    case 'A':
      // rx, ry, rotation, large-arc, sweep are not coordinates.
      args[5] += tx;
      args[6] += ty;
  }
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  // Six decimal places is plenty for path data; trim trailing zeros.
  final fixed = v.toStringAsFixed(6);
  return fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
