import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'push_notification_service.dart';

/// Maps an auth error into a concise, user-facing message for snackbars.
/// Supabase's [AuthException] (bad credentials, weak password, etc.) already
/// carries a readable `message`; anything else collapses to a generic line.
String authErrorMessage(Object error) {
  if (error is AuthUnavailable) return error.message;
  if (error is AuthException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// Thrown when a sign-in path is invoked while no Supabase backend is wired up
/// (empty `SUPABASE_*` env). The UI surfaces [message] as a hint to fill `.env`.
class AuthUnavailable implements Exception {
  const AuthUnavailable([
    this.message =
        'Sign-in is unavailable: the backend is not configured. '
        'Add your Supabase keys to .env and restart.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Result of an email/password sign-up. When Supabase has email confirmations
/// enabled the call succeeds but returns no [Session]; the UI then tells the
/// user to confirm via email instead of dropping them straight into the app.
class SignUpResult {
  const SignUpResult({required this.needsEmailConfirmation});

  final bool needsEmailConfirmation;
}

/// Single owner of authentication state. Brokers every sign-in path
/// (email/password and Google) through Supabase Auth and exposes the current
/// [user] reactively for the [AuthGate] and account screen.
///
/// The app may run with **no backend configured** — in that case
/// [isConfigured] is false, [Supabase.initialize] is skipped, and every
/// sign-in call throws [AuthUnavailable]. Initialization happens once, before
/// `runApp`, via [ensureInitialized].
class AuthService extends GetxService {
  static AuthService get to => Get.find();

  /// Reactive snapshot of the signed-in user; null when signed out or when no
  /// backend is configured. Drives the [AuthGate].
  final Rxn<User> user = Rxn<User>();

  StreamSubscription<AuthState>? _authSub;

  bool get isConfigured => AppConfig.isSupabaseConfigured;

  bool get isSignedIn => user.value != null;

  /// Whether to show the "Continue with Google" button.
  bool get canUseGoogle => AppConfig.isGoogleSignInConfigured;

  SupabaseClient get _client => Supabase.instance.client;

  /// Initializes Supabase if (and only if) it is configured. Safe to call when
  /// it isn't — it just returns, leaving the app backend-less but runnable.
  static Future<void> ensureInitialized() async {
    if (!AppConfig.isSupabaseConfigured) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // `publishableKey` accepts both the legacy anon JWT and the newer
      // sb_publishable_* key, so the SUPABASE_ANON_KEY env value works either way.
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  @override
  void onInit() {
    super.onInit();
    if (!isConfigured) return;
    user.value = _client.auth.currentUser;
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      final session = state.session;
      // On a fresh login or an app restart with a stored session, gate the
      // account through an enabled-check before exposing the user. Other events
      // (sign-out, token refresh, user update) just mirror the session.
      if (session != null &&
          (state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.initialSession)) {
        unawaited(_onAuthenticated(session.user));
      } else {
        user.value = session?.user;
      }
    });
  }

  @override
  void onClose() {
    _authSub?.cancel();
    super.onClose();
  }

  // --- Email / password ------------------------------------------------------

  /// Signs in with an existing email/password account. Throws [AuthException]
  /// (from supabase) on bad credentials — the UI shows its `message`.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _assertConfigured();
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Registers a new email/password account. If email confirmation is required
  /// the returned [SignUpResult.needsEmailConfirmation] is true and no session
  /// is created yet.
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    _assertConfigured();
    final name = fullName?.trim();
    final res = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      // Stored on the auth user's metadata; _syncPortalUser reads `full_name`
      // from here to populate portal_users.full_name on login.
      data: (name != null && name.isNotEmpty) ? {'full_name': name} : null,
    );
    return SignUpResult(needsEmailConfirmation: res.session == null);
  }

  // --- Google ("Sign in with Gmail") ----------------------------------------

  /// Runs the native Google account picker and exchanges the resulting ID token
  /// for a Supabase session. Returns false if the user dismissed the picker
  /// (not an error); throws on any real failure.
  Future<bool> signInWithGoogle() async {
    _assertConfigured();

    final googleSignIn = GoogleSignIn(
      serverClientId: AppConfig.googleWebClientId,
      clientId: _googleClientId,
    );

    final account = await googleSignIn.signIn();
    if (account == null) return false; // user cancelled the picker

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AuthException(
        'Google sign-in did not return an ID token. Check that '
        'GOOGLE_WEB_CLIENT_ID is the Web client ID.',
      );
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
    return true;
  }

  // --- Sign out --------------------------------------------------------------

  /// Clears both the Supabase session and any cached Google account so the next
  /// Gmail login re-prompts for the account. No-op when unconfigured.
  Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Best effort — the user may have signed in with email, not Google.
    }
    // Remove this device's push token first, while the session still identifies
    // the user, so a signed-out phone stops receiving their notifications.
    if (Get.isRegistered<PushNotificationService>()) {
      await PushNotificationService.to.removeCurrentDeviceToken();
    }
    await _client.auth.signOut();
  }

  // --- Login gate + profile mirror -------------------------------------------

  /// Runs once per login / session restore. Disabled accounts
  /// (`portal_users.is_active = false`) are signed straight back out with a
  /// notice; enabled accounts are exposed via [user] and mirrored into
  /// `portal_users`.
  Future<void> _onAuthenticated(User authUser) async {
    if (await _isAccountActive(authUser.id) == false) {
      await signOut(); // emits signedOut -> [user] stays null, AuthGate -> login
      Get.snackbar(
        'Account disabled',
        'This account has been disabled. Please contact support.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    user.value = authUser;
    unawaited(_syncPortalUser(authUser));
    // Tie this device's push token to the freshly-authenticated user. Guarded
    // because the push service may not be registered (Firebase unconfigured).
    if (Get.isRegistered<PushNotificationService>()) {
      unawaited(PushNotificationService.to.syncToken());
    }
  }

  /// Reads the account's `is_active` flag. Returns null when there is no row yet
  /// (first login) or the read fails — both treated as "allow" so a transient
  /// error never locks out a legitimate user. Only an explicit `false` blocks.
  Future<bool?> _isAccountActive(String id) async {
    try {
      final row = await _client
          .from('portal_users')
          .select('is_active')
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : row['is_active'] as bool?;
    } catch (e) {
      debugPrint('portal_users is_active check failed: $e');
      return null;
    }
  }

  /// Upserts the signed-in auth user into the `portal_users` table on every
  /// login. Keyed on `id` (= auth uid) so repeat logins update the row in place
  /// instead of duplicating; `role`, `is_active`, and `created_at` keep their
  /// database defaults. Best-effort — a failure here (e.g. RLS not yet granting
  /// insert/update) is logged but never blocks sign-in. Requires the policies in
  /// `supabase/portal_users_rls.sql`.
  Future<void> _syncPortalUser(User authUser) async {
    try {
      final meta = authUser.userMetadata ?? const <String, dynamic>{};
      final fullName = (meta['full_name'] ?? meta['name']) as String?;
      await _client.from('portal_users').upsert({
        'id': authUser.id,
        if (authUser.email != null) 'email': authUser.email,
        if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('portal_users upsert failed: $e');
    }
  }

  // --- Internals -------------------------------------------------------------

  /// iOS (and web) need google_sign_in's `clientId`; Android must leave it null
  /// and rely on the SHA-1/package registration instead.
  String? get _googleClientId {
    final ios = AppConfig.googleIosClientId;
    if (kIsWeb) {
      return AppConfig.googleWebClientId.isEmpty
          ? null
          : AppConfig.googleWebClientId;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS && ios.isNotEmpty) {
      return ios;
    }
    return null;
  }

  void _assertConfigured() {
    if (!isConfigured) throw const AuthUnavailable();
  }
}
