import 'package:flutter/material.dart';

import '../models/svg_asset.dart';
import '../theme/app_dimens.dart';
import '../theme/app_surfaces.dart';
import 'common/common.dart';

/// A portrait photo card: an image filling the top of a white rounded card
/// (cover for raster photos, contain for SVG line-art on the white plate) with
/// a centred name footer and lock/new overlays. Scales on tap.
///
/// Shared by the story-detail photo grid and the category asset grid (e.g. the
/// Puzzle tab) so both render a portal [SvgAsset] identically.
class AssetTile extends StatelessWidget {
  const AssetTile({super.key, required this.asset, required this.onTap});

  final SvgAsset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Raster photos fill the card like the reference; SVG line-art stays whole
    // (contain) so coloring templates don't get cropped.
    final fit = asset.isSvg ? BoxFit.contain : BoxFit.cover;
    final tile = Pressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cardSurface(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: NetworkAssetImage(asset: asset, fit: fit),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                asset.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!asset.isLocked && !asset.isNew) return tile;
    return Stack(
      children: [
        tile,
        if (asset.isLocked) const LockedBadge(radius: AppRadius.lg),
        if (asset.isNew) const NewBadge(),
      ],
    );
  }
}
