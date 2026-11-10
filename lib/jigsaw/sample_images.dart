import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

/// Fetches an image over HTTP and decodes it into a downscaled [ui.Image], used
/// for portal-managed puzzle photos whose bytes live in Supabase Storage. The
/// longest side is capped at [maxSide] px to keep memory in check for large
/// source photos.
Future<ui.Image> loadImageFromUrl(String url, {int maxSide = 1600}) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('GET $url returned HTTP ${response.statusCode}');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
  return _decodeBuffer(buffer, maxSide: maxSide);
}

/// Decodes an already-loaded image [buffer], downscaling so the longest side is
/// at most [maxSide] px. Disposes the buffer.
Future<ui.Image> _decodeBuffer(
  ui.ImmutableBuffer buffer, {
  required int maxSide,
}) async {
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final longest = math.max(descriptor.width, descriptor.height);

  final ui.Codec codec;
  if (longest > maxSide) {
    final scale = maxSide / longest;
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
  } else {
    codec = await descriptor.instantiateCodec();
  }

  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}
