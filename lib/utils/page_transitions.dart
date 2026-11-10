import 'package:flutter/material.dart';

/// A page route that fades the next screen in while sliding it gently up — used
/// for detail / canvas pushes so navigation feels smoother than the default
/// platform slide.
class FadeSlideRoute<T> extends PageRouteBuilder<T> {
  FadeSlideRoute({required WidgetBuilder builder, super.settings})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final t = Curves.easeOutCubic.transform(animation.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 28),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
        );
}
