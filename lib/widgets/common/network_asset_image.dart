import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/svg_asset.dart';

/// Renders a portal [SvgAsset] (or a raw image [url]) by auto-detecting SVG vs
/// raster, so the galleries show **both** vector templates and PNG/JPG photos.
///
/// SVGs render through `flutter_svg`; everything else uses the raster [Image]
/// decoder. Both branches show a spinner while loading and a fallback icon on
/// error, so a bad URL or an unexpected format never leaves a blank tile —
/// the symptom that motivated this widget (raster photos fed to an SVG
/// renderer render nothing).
///
/// URLs are resolved through [SvgAsset.resolvedUrl]: absolute URLs pass through;
/// Storage object *paths* are turned into full public URLs.
class NetworkAssetImage extends StatelessWidget {
  const NetworkAssetImage({
    super.key,
    this.asset,
    this.url,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorIcon = Icons.broken_image_outlined,
    this.errorIconColor,
  });

  /// The portal asset to render. When set, [url] is derived from
  /// [SvgAsset.resolvedUrl] and SVG-vs-raster is decided by [SvgAsset.isSvg].
  final SvgAsset? asset;

  /// An explicit URL that overrides [asset]'s. SVG is assumed when it ends in
  /// `.svg` (ignoring any `?query`).
  final String? url;

  final BoxFit fit;

  /// Shown while the image loads (and as the SVG placeholder). Defaults to a
  /// small spinner.
  final WidgetBuilder? placeholder;

  /// Icon shown when the image can't be decoded/fetched.
  final IconData errorIcon;
  final Color? errorIconColor;

  @override
  Widget build(BuildContext context) {
    final resolved = url ?? asset?.resolvedUrl ?? '';
    if (resolved.isEmpty) return _fallback(context);
    final svg = asset?.isSvg ??
        resolved.toLowerCase().split('?').first.endsWith('.svg');
    if (svg) {
      return SvgPicture.network(
        resolved,
        fit: fit,
        placeholderBuilder: placeholder ?? (_) => _fallback(context, loading: true),
      );
    }
    return Image.network(
      resolved,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return placeholder?.call(context) ?? _fallback(context, loading: true);
      },
      errorBuilder: (context, _, _) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context, {bool loading = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(scheme.onSurfaceVariant),
              ),
            )
          : Icon(
              errorIcon,
              size: 30,
              color: errorIconColor ?? scheme.onSurfaceVariant,
            ),
    );
  }
}
