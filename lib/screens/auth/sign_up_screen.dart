import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/common/common.dart';
import 'auth_validators.dart';

/// Email/password registration. Pushed on top of the login screen. On success
/// it pops back to the gate: if a session was created the gate is already
/// showing the app shell; if email confirmation is pending we tell the user.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _loading = true);
    try {
      final result = await AuthService.to.signUpWithEmail(
        email: _email.text,
        password: _password.text,
        fullName: _fullName.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (result.needsEmailConfirmation) {
        Get.snackbar(
          'Almost there',
          'Check ${_email.text.trim()} to confirm your account, then log in.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5),
          margin: const EdgeInsets.all(AppSpacing.lg),
        );
      }
      // When a session is created the AuthGate swaps in the app shell on its own.
    } catch (e) {
      Get.snackbar(
        'Sign-up failed',
        authErrorMessage(e),
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(AppSpacing.lg),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GradientAppBar(
        titleWidget: const Text('Create account'),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Join AR Creative',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Use your email to get started',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AuthTextField(
                          controller: _fullName,
                          label: 'Full name',
                          icon: Icons.person_outline,
                          keyboardType: TextInputType.name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          enabled: !_loading,
                          validator: validateFullName,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AuthTextField(
                          controller: _email,
                          label: 'Email',
                          icon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          enabled: !_loading,
                          validator: validateEmail,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AuthTextField(
                          controller: _password,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscure: true,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          enabled: !_loading,
                          validator: validateNewPassword,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AuthTextField(
                          controller: _confirm,
                          label: 'Confirm password',
                          icon: Icons.lock_outline,
                          obscure: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          enabled: !_loading,
                          validator: validateConfirmPassword(
                            () => _password.text,
                          ),
                          onSubmitted: (_) => _signUp(),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        GradientButton(
                          label: 'Create account',
                          icon: Icons.person_add_alt_1,
                          loading: _loading,
                          onPressed: _loading ? null : _signUp,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
