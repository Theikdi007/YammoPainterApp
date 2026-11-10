import 'package:flutter/widgets.dart';

/// Centers its [child] and caps it at [maxWidth] so content doesn't sprawl
/// edge-to-edge on tablets, desktop and web. On phones (viewport narrower than
/// [maxWidth]) it's a no-op, so phone layouts are unchanged.
///
/// Defaults suit a reading-width content column; pass a larger [maxWidth] for
/// galleries/grids (so they keep several columns) and a smaller one for forms
/// and single-card screens.
class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
