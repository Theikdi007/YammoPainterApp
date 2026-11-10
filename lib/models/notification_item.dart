import 'package:flutter/foundation.dart';

/// A single in-app notification row from the Supabase `notifications` table.
///
/// The schema is **portal-owned** and target-based (see
/// `supabase/notifications.sql`): the portal/admin inserts a row with a `target`
/// (`all` / `user` / `group`) and `target_value`, the `send-push` Edge Function
/// fans it out over the matching FCM topic, and the app reads the rows back here
/// to populate the in-app inbox. There is no per-recipient row or read flag —
/// the inbox filters by `target` client-side and tracks "seen" locally.
@immutable
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.sentAt,
  });

  final String id;
  final String title;
  final String body;

  /// When the notification was sent — the portal's timestamp, used for ordering
  /// and the unread watermark. Stored in local time.
  final DateTime sentAt;

  /// Builds an item from a Supabase row, or null when it lacks the id /
  /// timestamp it needs to be usable and orderable.
  static NotificationItem? fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final sentAt = DateTime.tryParse(map['sent_at']?.toString() ?? '');
    if (id == null || id.isEmpty || sentAt == null) return null;

    final title = (map['title'] as String?)?.trim();
    return NotificationItem(
      id: id,
      title: (title != null && title.isNotEmpty) ? title : 'Notification',
      body: (map['body'] as String?)?.trim() ?? '',
      sentAt: sentAt.toLocal(),
    );
  }
}
