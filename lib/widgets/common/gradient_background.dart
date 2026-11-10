import 'package:flutter/material.dart';

import '../../theme/app_gradients.dart';

/// Fills the screen behind its [child] with the brightness-aware page wash.
/// Drop it as the body's background so content floats over a soft gradient
/// instead of a flat scaffold color.
class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isDark ? AppGradients.pageDark : AppGradients.pageLight,
      ),
      child: child,
    );
  }
}
