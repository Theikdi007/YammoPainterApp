import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/notifications_screen.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';

/// App-bar action: a bell that opens the [NotificationsScreen] and carries an
/// unread-count badge fed by [NotificationService]. Renders nothing when no
/// backend is configured (there's no inbox to open), so it isn't a dead button.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AuthService.to.isConfigured) return const SizedBox.shrink();
    final service = NotificationService.to;
    return IconButton(
      tooltip: 'Notifications',
      icon: Obx(() => _BellIcon(count: service.unreadCount.value)),
      onPressed: () {
        // Clear the badge as the inbox opens, then pull a fresh list behind it.
        service.markAllRead();
        service.refresh();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const NotificationsScreen(),
          ),
        );
      },
    );
  }
}

class _BellIcon extends StatelessWidget {
  const _BellIcon({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    const bell = Icon(Icons.notifications_rounded, color: Colors.white);
    if (count <= 0) return bell;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        bell,
        Positioned(
          right: -5,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
