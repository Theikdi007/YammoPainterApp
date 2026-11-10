import 'package:flutter/material.dart';

/// Brightness-aware surface helpers for the light, card-forward look: a flat
/// light-gray page behind white cards (light mode), and an elevated container
/// on the base surface (dark mode).
///
/// Use [pageSurface] for a screen's background and [cardSurface] for cards, so
/// cards always read as a distinct layer on top of the page.
Color pageSurface(BuildContext context) {
  final s = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.dark
      ? s.surface
      : s.surfaceContainer;
}

Color cardSurface(BuildContext context) {
  final s = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.dark
      ? s.surfaceContainerHighest
      : Colors.white;
}
