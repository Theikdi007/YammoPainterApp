import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/notification_item.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_dimens.dart';
import '../theme/app_gradients.dart';
import '../widgets/common/common.dart';

/// The in-app notification inbox. Lists the signed-in user's notifications
/// (newest first), read back from Supabase `notifications` via
/// [NotificationService]. The app-bar bell marks them seen on open (clearing its
/// badge); pull down to refresh.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = NotificationService.to;
    return Scaffold(
      appBar: const GradientAppBar(
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Notifications'),
          ],
        ),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: AuthService.to.isConfigured
              ? RefreshIndicator(
                  onRefresh: service.refresh,
                  child: Obx(() => _body(context, service)),
                )
              : const _Message(
                  icon: Icons.cloud_off,
                  title: 'Notifications are disabled',
                  subtitle:
                      'Add your Supabase keys to .env and restart to enable '
                      'the inbox.',
                ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, NotificationService service) {
    if (service.loading.value && service.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (service.error.value && service.items.isEmpty) {
      return _Message(
        icon: Icons.cloud_off,
        title: "Couldn't load notifications",
        subtitle: 'Pull down to try again.',
        // In debug, show the raw error (e.g. a missing table) so it's fixable.
        detail: kDebugMode && service.errorDetail.value.isNotEmpty
            ? service.errorDetail.value
            : null,
      );
    }
    if (service.items.isEmpty) {
      return const _Message(
        icon: Icons.notifications_off_outlined,
        title: 'No notifications yet',
        subtitle: 'New messages will show up here.',
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: service.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => _NotificationCard(item: service.items[i]),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppGradients.button,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.notifications_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _timeAgo(item.sentAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered icon + message used for the empty / error / disabled states. Stays
/// vertically scrollable so pull-to-refresh works even with no content.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Optional raw diagnostic line (debug only), shown small and monospace.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 56, color: scheme.onSurfaceVariant),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      detail!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "time since" label (e.g. `now`, `5m`, `3h`, `2d`, `4w`).
String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo';
  return '${(diff.inDays / 365).floor()}y';
}
