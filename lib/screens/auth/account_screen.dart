import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_gradients.dart';
import '../../widgets/common/common.dart';
import '../feedback_screen.dart';
import '../notifications_screen.dart';

/// Profile / settings tab. A profile header, a card of account actions
/// (notifications, feedback, rating), and a de-emphasized sign-out. When no
/// backend is configured it explains that accounts are disabled.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await AuthService.to.signOut();
      // The AuthGate reacts to the cleared session and shows the login screen.
    } catch (e) {
      Get.snackbar(
        'Sign-out failed',
        authErrorMessage(e),
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(AppSpacing.lg),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _openNotifications() {
    NotificationService.to.markAllRead();
    NotificationService.to.refresh();
    Get.to<void>(() => const NotificationsScreen());
  }

  void _openFeedback() => Get.to<void>(() => const FeedbackScreen());

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.to;
    return Scaffold(
      appBar: const GradientAppBar(title: 'Profile'),
      body: GradientBackground(
        child: SafeArea(
          child: auth.isConfigured
              ? _content(context, auth)
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: const _BackendDisabledNotice(),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AuthService auth) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      child: ResponsiveContainer(
        maxWidth: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() => _ProfileHeader(user: auth.user.value)),
            const SizedBox(height: AppSpacing.xxl),
            _AccountMenu(
              onNotifications: _openNotifications,
              onFeedback: _openFeedback,
            ),
            const SizedBox(height: AppSpacing.xl),
            _SignOutButton(loading: _signingOut, onPressed: _signOut),
            const SizedBox(height: AppSpacing.xl),
            const _Footer(),
          ],
        ),
      ),
    );
  }
}

/// Big gradient avatar + email + provider chip.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final User? user;

  String get _email => user?.email ?? 'Signed in';

  String get _providerLabel {
    switch (user?.appMetadata['provider']?.toString()) {
      case 'google':
        return 'Google account';
      case 'email':
        return 'Email account';
      default:
        return 'Signed in';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = _email.isNotEmpty ? _email[0].toUpperCase() : '?';
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppGradients.button,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          _email,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 15, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                _providerLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Card grouping the account actions.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.onNotifications,
    required this.onFeedback,
  });

  final VoidCallback onNotifications;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _MenuTile(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'Messages and updates',
            onTap: onNotifications,
            trailing: Obx(() {
              final n = NotificationService.to.unreadCount.value;
              return n > 0
                  ? _CountBadge(count: n)
                  : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant);
            }),
          ),
          const _MenuDivider(),
          _MenuTile(
            icon: Icons.feedback_rounded,
            title: 'Send feedback',
            subtitle: 'Report a bug or share an idea',
            onTap: onFeedback,
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 20, color: scheme.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing ??
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 68),
      child: Divider(
        height: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      constraints: const BoxConstraints(minWidth: 22),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout_rounded, size: 20),
        label: const Text('Sign out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.error,
          side: BorderSide(color: scheme.error.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          'AR Creative',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Made with 💜',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BackendDisabledNotice extends StatelessWidget {
  const _BackendDisabledNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Sign-in is disabled',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Add your Supabase keys to .env and restart to enable accounts.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
