import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'common/network_asset_image.dart';
import '../theme/app_dimens.dart';

class ArOverlayImage extends StatefulWidget {
  const ArOverlayImage({
    super.key,
    required this.opacity,
    required this.isLocked,
    required this.onLockToggle,
    this.imagePath,
    this.presetSvgUrl,
  });

  final double opacity;
  final bool isLocked;
  final VoidCallback onLockToggle;
  final String? imagePath;

  /// Public URL of the selected preset SVG (from `svg_assets`). Used when no
  /// gallery/file [imagePath] is chosen.
  final String? presetSvgUrl;

  /// Bundled sample overlay shown when neither a device file nor a portal
  /// preset is provided, so the tracing surface always has something to trace
  /// even before/without portal photos in `svg_assets`.
  static const String defaultAsset = 'assets/ar/default_overlay.svg';

  @override
  State<ArOverlayImage> createState() => _ArOverlayImageState();
}

class _ArOverlayImageState extends State<ArOverlayImage> {
  Offset _position = Offset.zero;
  double _scale = 1.0;
  double _baseScale = 1.0;

  Widget _buildImageContent() {
    final imagePath = widget.imagePath;

    if (imagePath != null && imagePath.isNotEmpty) {
      if (imagePath.endsWith('.svg')) {
        return SvgPicture.file(
          File(imagePath),
          fit: BoxFit.contain,
        );
      }
      return Image.file(
        File(imagePath),
        fit: BoxFit.contain,
      );
    }

    final presetSvgUrl = widget.presetSvgUrl;
    if (presetSvgUrl != null && presetSvgUrl.isNotEmpty) {
      // A portal preset may be SVG *or* a raster photo — render either.
      return NetworkAssetImage(
        url: presetSvgUrl,
        fit: BoxFit.contain,
        placeholder: (_) => const SizedBox.shrink(),
      );
    }

    // No overlay chosen: fall back to the bundled sample so the tracing
    // surface is never blank (e.g. AR Drawing opened with no portal photos yet).
    return SvgPicture.asset(
      ArOverlayImage.defaultAsset,
      fit: BoxFit.contain,
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (widget.isLocked) return;
    _baseScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (widget.isLocked) return;
    setState(() {
      _position += details.focalPointDelta;
      _scale = (_baseScale * details.scale).clamp(0.2, 5.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Keep the lock toggle clear of the floating Home button (top-left) by
    // pinning it top-right, below the status bar.
    final lockTop = media.padding.top + AppSpacing.md;
    // The overlay starts centred and prominent; the user can drag/scale from
    // there. Size it relative to the shorter screen edge so it reads big on
    // phones and tablets alike.
    final overlaySize = media.size.shortestSide * 0.6;
    return Positioned.fill(
      child: GestureDetector(
        onScaleStart: widget.isLocked ? null : _onScaleStart,
        onScaleUpdate: widget.isLocked ? null : _onScaleUpdate,
        child: Stack(
          children: [
            // Centred overlay; _position offsets it from centre as the user drags.
            Center(
              child: Transform.translate(
                offset: _position,
                child: Transform.scale(
                  scale: _scale,
                  child: Opacity(
                    opacity: widget.opacity,
                    child: SizedBox(
                      width: overlaySize,
                      height: overlaySize,
                      child: _buildImageContent(),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: lockTop,
              right: AppSpacing.md,
              child: GestureDetector(
                onTap: widget.onLockToggle,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isLocked ? Icons.lock : Icons.lock_open,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
