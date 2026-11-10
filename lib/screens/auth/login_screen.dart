import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/google_sign_in_button.dart';
import '../../widgets/common/common.dart';
import 'auth_validators.dart';
import 'sign_up_screen.dart';

/// Sign-in entry point: email/password plus "Continue with Google". On success
/// the [AuthService] auth-state stream flips [AuthService.isSignedIn], and the
/// AuthGate swaps this screen out for the app shell — no manual navigation here.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;

  AuthService get _auth => AuthService.to;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _busy => _loading || _googleLoading;

  Future<void> _signIn() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _loading = true);
    try {
      await _auth.signInWithEmail(
        email: _email.text,
        password: _password.text,
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _googleLoading = true);
    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _showError(Object e) {
    Get.snackbar(
      'Sign-in failed',
      authErrorMessage(e),
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(AppSpacing.lg),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _AuthHeader(
                      title: 'Welcome back',
                      subtitle: 'Sign in to keep creating',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    GlassCard(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthTextField(
                              controller: _email,
                              label: 'Email',
                              icon: Icons.mail_outline,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              enabled: !_busy,
                              validator: validateEmail,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AuthTextField(
                              controller: _password,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              obscure: true,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              enabled: !_busy,
                              validator: validatePassword,
                              onSubmitted: (_) => _signIn(),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            GradientButton(
                              label: 'Log in',
                              icon: Icons.login,
                              loading: _loading,
                              onPressed: _busy ? null : _signIn,
                            ),
                            if (_auth.canUseGoogle) ...[
                              const SizedBox(height: AppSpacing.lg),
                              const _OrDivider(),
                              const SizedBox(height: AppSpacing.lg),
                              GoogleSignInButton(
                                loading: _googleLoading,
                                onPressed: _busy ? null : _signInWithGoogle,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SignUpPrompt(
                      enabled: !_busy,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SignUpScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand lockup shown above the auth card: a gradient brush badge + title.
class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Image.asset(
            'assets/icon/newapp_icon.png',
            width: 84,
            height: 84,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// "or" rule between the primary action and the Google button.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: scheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'or',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Divider(color: scheme.outlineVariant)),
      ],
    );
  }
}

class _SignUpPrompt extends StatelessWidget {
  const _SignUpPrompt({required this.onTap, required this.enabled});

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Wrap (not Row) so the prompt + button reflow onto a second line at large
    // text scales instead of overflowing on narrow screens.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          "Don't have an account?",
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        TextButton(
          onPressed: enabled ? onTap : null,
          child: const Text('Sign up'),
        ),
      ],
    );
  }
}
