import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/notification_item.dart';
import 'auth_service.dart';

/// Reads the signed-in user's in-app notification inbox from the Supabase
/// `notifications` table and tracks an unread count for the app-bar bell badge.
///
/// Registered `permanent: true` in `main()`. The push side ([[push-notifications
/// -fcm]] / `PushNotificationService`) *delivers* notifications; this service is
/// the *inbox* — it lets the user re-read past notifications and surfaces how
/// many are new.
///
/// Reads require a configured backend and a signed-in user (RLS
/// `notifications_select_own`). With no backend it stays empty so the app still
/// runs offline.
///
/// **Unread tracking** is local: the table has no per-row read flag, so we
/// persist a per-user "last seen" watermark (the newest notification timestamp
/// at the moment the inbox was opened) to a small JSON file via `path_provider`.
/// The badge counts notifications created after that watermark.
class NotificationService extends GetxService {
  static NotificationService get to => Get.find();

  /// The signed-in user's notifications, newest first. Empty with no backend or
  /// when signed out.
  final RxList<NotificationItem> items = <NotificationItem>[].obs;

  /// True while the first fetch for an empty list is in flight (drives the
  /// inbox's cold-load spinner).
  final RxBool loading = false.obs;

  /// True when the last fetch failed and the list is still empty, so the inbox
  /// can offer a pull-to-retry.
  final RxBool error = false.obs;

  /// Raw message from the last failed fetch (e.g. the Postgrest error). Surfaced
  /// in the inbox only in debug builds to make "Couldn't load" actionable —
  /// commonly "relation public.notifications does not exist" (run
  /// `supabase/notifications.sql`).
  final RxString errorDetail = ''.obs;

  /// Notifications newer than the last time the inbox was opened. Drives the
  /// app-bar bell badge.
  final RxInt unreadCount = 0.obs;

  /// Per-user watermark (`userId` -> ISO-8601 UTC), persisted so the unread
  /// badge survives restarts. Loaded once at startup.
  Map<String, String> _lastSeen = <String, String>{};
  bool _lastSeenLoaded = false;

  AuthService get _auth => AuthService.to;
  SupabaseClient get _db => Supabase.instance.client;
  bool get _configured => AppConfig.isSupabaseConfigured;

  @override
  void onInit() {
    super.onInit();
    // Bootstrap loads the watermark first, then sets up the user listener and
    // fetches the inbox. The watermark MUST be loaded before the `ever` callback
    // fires (which it does immediately when the user is signed in), otherwise
    // refresh() races ahead and computes every notification as unread.
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _loadLastSeen();
    // Register the user listener AFTER the watermark is loaded so the
    // immediate callback (for the current signed-in user) sees the persisted
    // watermark instead of an empty map.
    ever<User?>(_auth.user, (user) {
      if (user == null) {
        items.clear();
        unreadCount.value = 0;
      } else {
        unawaited(refresh());
      }
    });
    if (_auth.isSignedIn) await refresh();
  }

  /// Fetches the latest notifications for the signed-in user (newest first) and
  /// recomputes the unread badge. No-op with no backend / nobody signed in.
  Future<void> refresh() async {
    if (!_configured || !_auth.isSignedIn) {
      items.clear();
      unreadCount.value = 0;
      return;
    }
    loading.value = items.isEmpty; // spinner only on a cold list
    try {
      // The portal table is target-based and readable by any signed-in user
      // (RLS `using (true)`), so filter to what this user should see: broadcasts
      // (`target = all`) plus notifications addressed to them
      // (`target = user` and `target_value = my id`). `status = sent` drops
      // failed/scheduled rows.
      final uid = _auth.user.value!.id;
      final rows = await _db
          .from('notifications')
          .select('id, title, body, sent_at')
          .eq('status', 'sent')
          .or('target.eq.all,and(target.eq.user,target_value.eq.$uid)')
          .order('sent_at', ascending: false)
          .limit(100);
      items.assignAll(
        rows
            .map(NotificationItem.fromMap)
            .whereType<NotificationItem>()
            .toList(growable: false),
      );
      error.value = false;
      errorDetail.value = '';
      _recomputeUnread();
    } catch (e) {
      debugPrint('NotificationService.refresh failed: $e');
      error.value = true;
      errorDetail.value = e.toString();
    } finally {
      loading.value = false;
    }
  }

  /// Marks everything currently in the inbox as seen, clearing the badge. Called
  /// when the inbox is opened. Persists the watermark so it sticks across
  /// restarts.
  Future<void> markAllRead() async {
    final userId = _auth.user.value?.id;
    if (userId == null) return;
    // Watermark at the newest notification (or now, if the list hasn't loaded),
    // so a notification that arrives later still counts as unread.
    final newest = items.isNotEmpty ? items.first.sentAt : DateTime.now();
    _lastSeen[userId] = newest.toUtc().toIso8601String();
    unreadCount.value = 0;
    await _saveLastSeen();
  }

  void _recomputeUnread() {
    final userId = _auth.user.value?.id;
    if (userId == null) {
      unreadCount.value = 0;
      return;
    }
    final seen = DateTime.tryParse(_lastSeen[userId] ?? '');
    if (seen == null) {
      unreadCount.value = items.length; // never opened — all are unread
      return;
    }
    unreadCount.value =
        items.where((n) => n.sentAt.toUtc().isAfter(seen)).length;
  }

  // --- Last-seen persistence -------------------------------------------------

  Future<File?> _seenFile() async {
    if (kIsWeb) return null; // no documents dir on web — badge stays in-memory
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/notifications_seen.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadLastSeen() async {
    if (_lastSeenLoaded) return;
    _lastSeenLoaded = true;
    try {
      final file = await _seenFile();
      if (file == null || !file.existsSync()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        _lastSeen =
            decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {
      // Corrupt/missing file — start from an empty watermark map.
    }
  }

  Future<void> _saveLastSeen() async {
    try {
      final file = await _seenFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode(_lastSeen));
    } catch (_) {
      // Best-effort: an unwritable file just means the badge may reappear after
      // a restart — not worth surfacing.
    }
  }
}
