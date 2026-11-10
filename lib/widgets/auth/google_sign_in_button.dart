import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';

/// "Continue with Google" button styled as a neutral social-login surface so it
/// reads distinctly from the gradient primary action. Shows a spinner while the
/// account picker / token exchange is in flight.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.height = 54,
  });

  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !loading;

    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleGlyph(),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A compact stand-in for the Google "G" mark — a white tile with a blue "G".
/// Avoids bundling a brand asset while still reading as Google at a glance.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFDADCE0)),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 15,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }
}
