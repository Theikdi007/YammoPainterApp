import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'notification_service.dart';

/// Background / terminated message handler.
///
/// Runs in a **separate isolate** with no access to the running app's state, so
/// it must re-initialize Firebase and keep its work minimal. A message that
/// carries a `notification` block is already displayed by the OS; this hook is
/// only for data-only side effects (kept to a log for now).
///
/// Must be a top-level (or static) function and annotated `vm:entry-point` so
/// the Flutter tool retains it for the background isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Push (background): ${message.messageId} ${message.data}');
}

/// The notification channel foreground messages are posted to. Mirrors the
/// `default_notification_channel_id` declared in AndroidManifest.xml so the
/// channel the OS uses for background/terminated FCM notifications and the one
/// we use for foreground re-display are the same (consistent importance/sound).
const AndroidNotificationChannel _kChannel = AndroidNotificationChannel(
  'high_importance_channel',
  'Notifications',
  description: 'General notifications from AR Creative',
  importance: Importance.high,
);

/// Owns push notifications end to end: permission, the device FCM token (saved
/// to Supabase `user_devices` so the backend can target this device), and the
/// three delivery states —
///
/// - **foreground** ([FirebaseMessaging.onMessage]) — FCM does *not* display a
///   notification while the app is open, so we re-post it through
///   [FlutterLocalNotificationsPlugin] (Android) / system presentation (iOS).
/// - **background** — the OS shows the `notification` block; a tap fires
///   [FirebaseMessaging.onMessageOpenedApp]. [firebaseMessagingBackgroundHandler]
///   runs for data side effects.
/// - **terminated** — the OS shows it; tapping launches the app and the message
///   is returned by [FirebaseMessaging.getInitialMessage].
///
/// Initialization is best-effort: if Firebase isn't configured (no native
/// config files) [init] logs and returns, leaving the app fully usable.
class PushNotificationService extends GetxService {
  static PushNotificationService get to => Get.find();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// The most recent FCM token, retained so it can be deleted from Supabase on
  /// sign-out (when we still know which row to remove).
  String? _token;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;

  AuthService get _auth => AuthService.to;
  SupabaseClient get _db => Supabase.instance.client;

  /// Wires up permission, local-notification display, the three message-state
  /// handlers, and the initial token sync. Safe to await from `main`.
  Future<PushNotificationService> init() async {
    try {
      await _initLocalNotifications();
      await _requestPermission();
      // iOS shows foreground banners itself when asked; on Android we re-post.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _onMessageSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      _onOpenedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);

      // On Apple platforms every FCM API (topic subscribe, token fetch) throws
      // `apns-token-not-set` until APNs hands over the device token — which
      // never arrives on the Simulator. Gate the FCM work on it so an
      // un-provisioned build stays fully usable instead of logging failures.
      if (await _apnsReady()) {
        // Listen on the broadcast topic so the portal's "All" notifications
        // arrive without the backend having to track this device's token.
        await _subscribeToBroadcastTopic();
        await _syncToken();
        _tokenRefreshSub =
            FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
      } else {
        debugPrint(
          'APNs token unavailable (iOS Simulator, or push not provisioned) — '
          'skipping topic subscription and FCM token fetch. Use a physical '
          'device.',
        );
      }

      // App launched from terminated by tapping a notification.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _onNotificationOpened(initial);
    } catch (e) {
      debugPrint('PushNotificationService.init failed: $e');
    }
    return this;
  }

  @override
  void onClose() {
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
    _onOpenedSub?.cancel();
    super.onClose();
  }

  // --- Token lifecycle -------------------------------------------------------

  /// Fetches the current token and stores it. Called at startup and after a
  /// fresh login (via [AuthService]) so the signed-in user's devices stay
  /// current.
  Future<void> syncToken() => _syncToken();

  Future<void> _syncToken() async {
    try {
      // Apple gates getToken() on the APNs device token (see _apnsReady); skip
      // cleanly when it isn't available rather than throwing apns-token-not-set.
      if (!await _apnsReady()) {
        debugPrint(
          'APNs token unavailable (iOS Simulator, or push not provisioned) — '
          'skipping FCM token fetch. Use a physical device.',
        );
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('getToken failed: $e');
    }
  }

  /// Cached APNs device token (Apple only) so the several FCM calls that need
  /// it don't each re-poll once it has been resolved successfully.
  String? _apnsToken;

  /// Whether FCM APIs can be used right now. On Apple platforms every FCM call
  /// (`getToken`, `subscribeToTopic`) throws `apns-token-not-set` until APNs
  /// hands the app its device token; it arrives a moment after registration and
  /// never on the Simulator. Resolves it once, caching a success so later calls
  /// are instant. Web and Android don't gate on APNs, so they're always ready.
  Future<bool> _apnsReady() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isMacOS)) return true;
    _apnsToken ??= await _waitForApnsToken();
    return _apnsToken != null;
  }

  /// Polls for the APNs device token (Apple only), which the OS delivers a
  /// short moment after registration. Returns null if it never arrives within
  /// the window — the expected case on the Simulator.
  Future<String?> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null) return apns;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  /// Upserts [token] for the signed-in user. No-op when there's no backend or
  /// nobody is signed in — the token is still cached so a later login can save
  /// it. Keyed on the (unique) token so a re-registration updates in place.
  Future<void> _saveToken(String token) async {
    _token = token;
    if (!_auth.isConfigured || !_auth.isSignedIn) return;
    final user = _auth.user.value;
    if (user == null) return;
    try {
      await _db.from('user_devices').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'platform': _platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (e) {
      debugPrint('user_devices upsert failed: $e');
    }
    // Also listen on this user's private topic so the portal can target them
    // individually (target = user, target_value = the user id).
    await _subscribeToUserTopic(user.id);
  }

  /// Removes this device's token row. Called on sign-out so a signed-out phone
  /// stops receiving the previous user's notifications.
  Future<void> removeCurrentDeviceToken() async {
    // Stop targeting this user before the session is torn down (user is still
    // known here — sign-out clears it only afterwards).
    final userId = _auth.user.value?.id;
    if (userId != null) await _unsubscribeFromUserTopic(userId);

    final token = _token;
    if (token == null || !_auth.isConfigured) return;
    try {
      await _db.from('user_devices').delete().eq('fcm_token', token);
    } catch (e) {
      debugPrint('user_devices delete failed: $e');
    }
  }

  // --- Topic subscriptions ---------------------------------------------------

  /// FCM topic name for a single user, sanitized to FCM's allowed character set
  /// (`[a-zA-Z0-9-_.~%]`). The edge function builds the same name from
  /// `target_value`, so both sides must sanitize identically.
  String _userTopic(String userId) =>
      'user_${userId.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.~%]'), '_')}';

  /// Broadcast topic every install listens on (portal target = all). Topic APIs
  /// aren't supported on web, so this is a no-op there.
  Future<void> _subscribeToBroadcastTopic() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic('all');
    } catch (e) {
      debugPrint('subscribeToTopic(all) failed: $e');
    }
  }

  Future<void> _subscribeToUserTopic(String userId) async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic(_userTopic(userId));
    } catch (e) {
      debugPrint('subscribeToTopic(user) failed: $e');
    }
  }

  Future<void> _unsubscribeFromUserTopic(String userId) async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(_userTopic(userId));
    } catch (e) {
      debugPrint('unsubscribeFromTopic(user) failed: $e');
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    return Platform.isIOS ? 'ios' : 'android';
  }

  // --- Permission + local notifications -------------------------------------

  Future<void> _requestPermission() async {
    // Covers iOS and the Android 13+ POST_NOTIFICATIONS runtime prompt.
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Firebase requests the iOS permission, so don't double-prompt here.
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          _handleData(jsonDecode(payload) as Map<String, dynamic>);
        } catch (_) {/* malformed payload — ignore */}
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_kChannel);
  }

  // --- Message handlers ------------------------------------------------------

  /// Foreground: FCM hands us the message but shows nothing. iOS displays it via
  /// the presentation options set in [init]; on Android we post a local
  /// notification so the user actually sees it.
  void _onForegroundMessage(RemoteMessage message) {
    // A new notification arrived while the app is open — keep the in-app inbox
    // and its unread bell badge current.
    _refreshInbox();
    final notification = message.notification;
    if (notification == null) return;
    if (!kIsWeb && Platform.isAndroid) {
      _local.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannel.id,
            _kChannel.name,
            channelDescription: _kChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  /// A tap on a background/terminated notification routed the user back in.
  void _onNotificationOpened(RemoteMessage message) =>
      _handleData(message.data);

  /// Single place to act on a message's `data` payload (deep-link routing).
  /// Extend this to navigate on a `route`/`type` field; today it just logs so
  /// every state has one consistent entry point.
  void _handleData(Map<String, dynamic> data) {
    debugPrint('Push opened with data: $data');
    // Opening from a tapped notification: refresh the inbox so it's current.
    _refreshInbox();
    // TODO: route on data['type'] / data['route'] once notification
    // destinations (a post, a reward, an inbox) are defined.
  }

  /// Pulls a fresh inbox snapshot if the inbox service is registered. Decoupled
  /// (guarded lookup) so push delivery never depends on the inbox existing.
  void _refreshInbox() {
    if (Get.isRegistered<NotificationService>()) {
      unawaited(NotificationService.to.refresh());
    }
  }
}
