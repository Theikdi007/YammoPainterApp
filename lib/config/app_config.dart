/// Centralized runtime configuration for backend services (Supabase, FCM).
///
/// Values are read at **compile time** from `--dart-define` entries so no
/// secrets live in source. Supply them with a dotenv-style file:
///
/// ```bash
/// flutter run --dart-define-from-file=.env
/// flutter build apk --dart-define-from-file=.env
/// ```
///
/// See `.env.example` for the expected keys. Until real values are provided
/// every getter falls back to an empty string and [isSupabaseConfigured] /
/// [isFcmConfigured] return false — the app must guard backend calls behind
/// those flags so it still builds and runs with no backend attached.
///
/// This is the scaffold for the planned Auth / Community / Notifications /
/// Rewards layers; the services that consume it are not built yet.
abstract final class AppConfig {
  // --- Supabase --------------------------------------------------------------
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Supabase Storage bucket holding portal-managed SVG presets/templates.
  static const String svgBucket = String.fromEnvironment(
    'SUPABASE_SVG_BUCKET',
    defaultValue: 'svg_assets',
  );

  /// Storage bucket community post images upload to.
  static const String postsBucket = String.fromEnvironment(
    'SUPABASE_POSTS_BUCKET',
    defaultValue: 'user_posts',
  );

  /// Storage bucket the user's saved / colored drawings upload to.
  static const String savedDrawingsBucket = String.fromEnvironment(
    'SUPABASE_SAVED_BUCKET',
    defaultValue: 'saved_drawings',
  );

  // --- Google Sign-In --------------------------------------------------------
  /// OAuth **web/server** client ID from Google Cloud. Passed to google_sign_in
  /// as `serverClientId` so the ID token it returns is minted for this audience
  /// and Supabase can verify it. Required on every platform for Gmail login.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// OAuth **iOS** client ID. Used as google_sign_in's `clientId` on iOS (and
  /// web); Android derives its client from the SHA-1/package registration so it
  /// must stay null there.
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  // --- Firebase Cloud Messaging ---------------------------------------------
  static const String fcmSenderId = String.fromEnvironment('FCM_SENDER_ID');

  // --- Deep linking ----------------------------------------------------------
  /// Scheme used for share/deeplink URLs (e.g. `arcreative://post/123`).
  static const String deepLinkScheme = String.fromEnvironment(
    'DEEP_LINK_SCHEME',
    defaultValue: 'arcreative',
  );

  // --- Guards ----------------------------------------------------------------
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Whether the Gmail (Google) sign-in button should be offered. Requires both
  /// a configured Supabase backend and a Google web client ID.
  static bool get isGoogleSignInConfigured =>
      isSupabaseConfigured && googleWebClientId.isNotEmpty;

  static bool get isFcmConfigured => fcmSenderId.isNotEmpty;
}
