import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_gradients.dart';

/// A standard [AppBar] painted with the brand hero gradient.
///
/// The gradient lives in [AppBar.flexibleSpace] (so it covers the status-bar
/// area too). It must be a [Container] — `flexibleSpace` hands its child loose
/// constraints, and a bare `DecoratedBox` would collapse to zero height and
/// show nothing; `Container` expands to fill instead.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradientAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.gradient = AppGradients.hero,
    this.centerTitle = false,
    this.bottom,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final Gradient gradient;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // Force the gradient through — transparent fills + no M3 surface tint so
      // nothing washes the brand colors out.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      title: titleWidget ?? (title != null ? Text(title!) : null),
      titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      bottom: bottom,
      flexibleSpace: Container(
        decoration: BoxDecoration(gradient: gradient),
      ),
    );
  }
}
