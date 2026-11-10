import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';

/// A scrim + centered lock icon overlaid on a locked gallery tile (an inactive
/// `svg_assets` row). Drop it as the top child of a [Stack]; it's an
/// [IgnorePointer] so the tile's own tap handler still fires (and shows the
/// "locked" message).
class LockedBadge extends StatelessWidget {
  const LockedBadge({super.key, this.radius = AppRadius.md});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
