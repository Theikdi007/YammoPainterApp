import 'dart:ui';

import 'package:path_drawing/path_drawing.dart' as pd;

import '../coloring_page.dart';

/// Parses one SVG path-data string into a dart:ui [Path].
///
/// Wraps `path_drawing.parseSvgPathData` so failures surface as
/// [ColoringParseException] with the offending input attached, instead of
/// the package's own (untyped, unhelpfully nested) errors.
///
/// Per the SVG spec, path data must begin with a moveto (`M` or `m`); we
/// reject inputs that don't, since `path_drawing` is lenient and would
/// otherwise return an empty Path for some malformed inputs.
Path parsePath(String svgPathData) {
  final trimmed = svgPathData.trim();
  if (trimmed.isEmpty) {
    throw ColoringParseException(
      'SVG path data is empty',
      offendingPath: svgPathData,
    );
  }
  final first = trimmed.codeUnitAt(0);
  if (first != 0x4D /* M */ && first != 0x6D /* m */) {
    throw ColoringParseException(
      'SVG path data must start with a moveto (M or m)',
      offendingPath: svgPathData,
    );
  }
  try {
    return pd.parseSvgPathData(trimmed);
  } catch (e) {
    throw ColoringParseException(
      'Failed to parse SVG path data',
      offendingPath: svgPathData,
      cause: e,
    );
  }
}
