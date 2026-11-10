import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'screens/ar_home_screen.dart';
import 'screens/auth/account_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/jigsaw_puzzle_screen.dart';
import 'screens/library_screen.dart';
import 'services/auth_service.dart';
import 'services/feedback_service.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';  
import 'services/saved_drawing_service.dart';
import 'services/story_line_service.dart';
import 'services/svg_asset_service.dart';
import 'theme/app_theme.dart';
import 'widgets/common/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pin the app to portrait. The drawing canvas stores every stroke in absolute
  // canvas pixels and the toolbars are laid out for a portrait width, so a
  // landscape↔portrait rotation would offset the artwork and leave the canvas
  // unable to fill the screen. Locking here means that breakage can never occur.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Bring up the backend (no-op when SUPABASE_* env is absent) before anything
  // reads auth state, then register the auth service for the whole app.
  await AuthService.ensureInitialized();
  Get.put(AuthService(), permanent: true);
  Get.put(SvgAssetService(), permanent: true);
  Get.put(StoryLineService(), permanent: true);
  Get.put(SavedDrawingService(), permanent: true);
  // In-app notification inbox (reads the Supabase `notifications` table). Its
  // onInit follows the signed-in user and tracks the unread bell badge.
  Get.put(NotificationService(), permanent: true);
  // User feedback (Account form + contextual sentiment prompt).
  Get.put(FeedbackService(), permanent: true);
  // Boot Firebase and register the background/terminated message handler before
  // the first frame — both are fast and the background isolate needs the
  // handler registered up front.
  await _initFirebaseMessaging();
  // Boot AdMob (test mode — safe to run even if AdMob isn't fully configured).
  try {
    await MobileAds.instance.initialize();
  } catch (e) {
    debugPrint('AdMob init skipped: $e');
  }

  runApp(const DrawPainterApp());
  // Register the push service AFTER the UI is up, and don't await it. Its init()
  // shows the iOS notification permission prompt and waits several seconds for
  // the APNs device token; doing that before runApp left the screen blank until
  // it finished. Fire-and-forget keeps the first frame instant. Token sync for
  // an already-signed-in user happens inside init(), and the auth service's
  // own calls into the push service are guarded by Get.isRegistered, so the
  // slightly later registration is safe.
  unawaited(_registerPushService());
}

/// Brings up Firebase and installs the background/terminated message handler.
/// Both are quick and must precede runApp: the background isolate looks up the
/// handler the moment a notification wakes the app from terminated. Any failure
/// (most commonly: the native Firebase config files aren't present yet) is
/// swallowed so the app stays usable without push.
Future<void> _initFirebaseMessaging() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase init failed; push notifications unavailable: $e');
  }
}

/// Registers [PushNotificationService] (permission, token sync, topic
/// subscriptions) off the startup critical path. Failure-safe so a missing
/// Firebase config or a denied permission never affects the rest of the app.
Future<void> _registerPushService() async {
  try {
    await Get.putAsync(() => PushNotificationService().init(), permanent: true);
  } catch (e) {
    debugPrint('PushNotificationService registration failed: $e');
  }
}

class DrawPainterApp extends StatelessWidget {
  const DrawPainterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Panda Paint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

/// Decides between the login flow and the app shell based on auth state.
///
/// When no backend is configured ([AuthService.isConfigured] is false) the gate
/// falls straight through to [HomeScreen] so the app stays fully usable in
/// development; once `.env` carries real Supabase keys it enforces login.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.to;
    if (!auth.isConfigured) return const HomeScreen();
    return Obx(
      () => auth.isSignedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Painting is the primary, default tab.
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              // IndexedStack keeps every child mounted, so each tab's state (the
              // in-progress drawing, puzzle progress, scroll position) survives
              // tab switches. Their GetX controllers are persistent too.
              children: const [
                LibraryScreen(),
                // AR Drawing is now a photo chooser; picking one pushes the
                // full-screen camera surface, which owns the camera for its own
                // lifetime.
                ArHomeScreen(),
                JigsawPuzzleScreen(),
                AccountScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          AppBottomNavItem(
            icon: Icons.brush_outlined,
            selectedIcon: Icons.brush,
            label: 'Painting',
          ),
          AppBottomNavItem(
            icon: Icons.view_in_ar_outlined,
            selectedIcon: Icons.view_in_ar,
            label: 'AR Drawing',
          ),
          AppBottomNavItem(
            icon: Icons.extension_outlined,
            selectedIcon: Icons.extension,
            label: 'Puzzle',
          ),
          AppBottomNavItem(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}


