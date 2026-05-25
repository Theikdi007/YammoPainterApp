import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart'
    show BytesLoader, PictureInfo, SvgStringLoader, vg;
import 'package:http/http.dart' as http;

import '../coloring_page.dart';
import '../coloring_page_manifest.dart';
import 'svg_importer.dart';
import 'svg_path_parser.dart';

/// Pure conversion: turns the raw path-data strings inside [manifest] into
/// dart:ui [Path] objects. No I/O. Throws [ColoringParseException] on the
/// first malformed region or outline path.
Future<ColoringPage> loadFromManifest(
  ColoringPageManifest manifest, {
  PictureInfo? pictureInfo,
}) async {
  final regions = manifest.regions.map(parsePath).toList(growable: false);
  final outline = manifest.outline.map(parsePath).toList(growable: false);
  final regionFills = manifest.regionFills
      .map((s) => s == null ? null : parseSvgColor(s))
      .toList(growable: false);
  return ColoringPage(
    viewBox: manifest.viewBox,
    regions: regions,
    regionFills: regionFills,
    outline: outline,
    pictureInfo: pictureInfo,
    name: manifest.name,
  );
}

/// Loads a coloring page from a Flutter asset. Dispatches on extension:
/// `.json` is decoded as a [ColoringPageManifest]; `.svg` is run through
/// [importRawSvg]. Anything else: try JSON first, fall back to SVG.
///
/// SVG assets are also pre-rendered through `flutter_svg` so the visual
/// layer is pixel-faithful to the source — heuristics-based path
/// classification is approximate by design.
Future<ColoringPage> loadFromAssetBundle(String assetPath) async {
  final body = await rootBundle.loadString(assetPath);
  final manifest = await _decode(assetPath, body, contentType: null);
  PictureInfo? pictureInfo;
  if (assetPath.toLowerCase().endsWith('.svg')) {
    pictureInfo = await _tryLoadSvgPicture(SvgStringLoader(body), assetPath);
  }
  return loadFromManifest(manifest, pictureInfo: pictureInfo);
}

/// Loads a coloring page from raw SVG content already in memory — used by
/// the Upload tile in the template picker for user-supplied files.
///
/// Same pipeline as [loadFromAssetBundle]: importer → manifest → page,
/// plus a `flutter_svg` pre-render so the visual layer is pixel-faithful.
Future<ColoringPage> loadFromSvgString(
  String svgContent, {
  String sourceLabel = 'uploaded.svg',
}) async {
  final manifest = await importRawSvg(svgContent);
  final pictureInfo = await _tryLoadSvgPicture(
    SvgStringLoader(svgContent),
    sourceLabel,
  );
  return loadFromManifest(manifest, pictureInfo: pictureInfo);
}

Future<PictureInfo?> _tryLoadSvgPicture(
  BytesLoader loader,
  String source,
) async {
  try {
    return await vg.loadPicture(loader, null);
  } catch (e) {
    // Picture rendering is best-effort; the path-based outline fallback in
    // ColoringPageTemplate kicks in when this fails.
    // ignore: avoid_print
    print('flutter_svg: failed to render "$source": $e');
    return null;
  }
}

/// HTTP GET. Dispatches on `Content-Type` first, then URL extension.
/// Throws [ColoringParseException] for non-2xx responses. If [client] is
/// omitted a one-shot client is created and closed; pass a [http.Client]
/// (or `MockClient` in tests) when you want to control the transport.
Future<ColoringPage> loadFromUrl(String url, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final response = await c.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ColoringParseException(
        'GET $url returned HTTP ${response.statusCode}',
      );
    }
    final manifest = await _decode(
      url,
      response.body,
      contentType: response.headers['content-type'],
    );
    return loadFromManifest(manifest);
  } finally {
    if (client == null) c.close();
  }
}

Future<ColoringPageManifest> _decode(
  String pathOrUrl,
  String body, {
  required String? contentType,
}) async {
  if (contentType != null) {
    if (contentType.contains('json')) return _decodeJson(body);
    if (contentType.contains('svg')) return importRawSvg(body);
  }
  final lower = pathOrUrl.toLowerCase();
  if (lower.endsWith('.json')) return _decodeJson(body);
  if (lower.endsWith('.svg')) return importRawSvg(body);
  // Unknown — try JSON then SVG.
  try {
    return _decodeJson(body);
  } on ColoringParseException {
    return importRawSvg(body);
  } on FormatException {
    return importRawSvg(body);
  }
}

ColoringPageManifest _decodeJson(String body) {
  final decoded = json.decode(body);
  if (decoded is! Map<String, dynamic>) {
    throw ColoringParseException(
      'Expected a JSON object at the top level of the manifest',
    );
  }
  return ColoringPageManifest.fromJson(decoded);
}
