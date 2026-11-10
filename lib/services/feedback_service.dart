import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'auth_service.dart';

/// Feedback topics shown in the form and stored in `feedback.category`.
enum FeedbackCategory {
  bug('bug', 'Problem'),
  suggestion('suggestion', 'Suggestion'),
  praise('praise', 'Compliment'),
  other('other', 'Something else');

  const FeedbackCategory(this.value, this.label);

  final String value;
  final String label;
}

/// One-tap sentiment captured by the contextual prompt (maps to an emoji).
enum FeedbackSentiment {
  happy('happy'),
  neutral('neutral'),
  sad('sad');

  const FeedbackSentiment(this.value);

  final String value;
}

/// Writes user feedback to the Supabase `feedback` table and owns the
/// frequency-cap state for the contextual "how's it going?" prompt
/// ([[notification-inbox]] uses the same local-file persistence trick).
///
/// Registered `permanent: true` in `main()`. Submitting requires a configured
/// backend and a signed-in user (RLS `feedback_insert_own`); with no backend
/// [submit] is a no-op so the app still runs offline.
class FeedbackService extends GetxService {
  static FeedbackService get to => Get.find();

  AuthService get _auth => AuthService.to;
  SupabaseClient get _db => Supabase.instance.client;
  bool get _configured => AppConfig.isSupabaseConfigured;

  /// Show the gate after this many positive actions (1 = the first save / solved
  /// puzzle / AR trace), and at most once per [_promptCooldown] — unless the
  /// user has already engaged, then never again.
  static const int _promptAfterActions = 1;
  static const Duration _promptCooldown = Duration(days: 7);

  Map<String, dynamic> _prompt = <String, dynamic>{};
  bool _promptLoaded = false;

  @override
  void onInit() {
    super.onInit();
    unawaited(_loadPrompt());
  }

  /// Inserts a feedback row. Returns true on success; false (no-op) with no
  /// backend or nobody signed in. Submitting also suppresses the contextual
  /// prompt for good — the user has spoken.
  Future<bool> submit({
    required FeedbackCategory category,
    required String message,
    FeedbackSentiment? sentiment,
  }) async {
    if (!_configured || !_auth.isSignedIn) return false;
    final user = _auth.user.value;
    if (user == null) return false;
    try {
      await _db.from('feedback').insert({
        'user_id': user.id,
        'category': category.value,
        'sentiment': sentiment?.value,
        'message': message.trim(),
        'platform': _platform,
      });
      await suppressPrompt();
      return true;
    } catch (e) {
      debugPrint('FeedbackService.submit failed: $e');
      return false;
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  // --- Contextual prompt frequency cap --------------------------------------

  /// Records one "positive moment" (a save, a solved puzzle) and returns whether
  /// the sentiment prompt should be shown now. Honors the suppress flag, the
  /// minimum action count, and the cooldown between prompts.
  Future<bool> registerSuccessAndShouldPrompt() async {
    if (!_configured || !_auth.isSignedIn) return false;
    await _loadPrompt();
    if (_prompt['suppressed'] == true) return false;

    final count = ((_prompt['count'] as num?)?.toInt() ?? 0) + 1;
    _prompt['count'] = count;

    final last = DateTime.tryParse(_prompt['lastPrompt']?.toString() ?? '');
    final cooledDown =
        last == null || DateTime.now().difference(last) >= _promptCooldown;
    final show = count >= _promptAfterActions && cooledDown;
    if (show) {
      _prompt['lastPrompt'] = DateTime.now().toUtc().toIso8601String();
    }
    await _savePrompt();
    return show;
  }

  /// Stops the contextual prompt permanently (after the user engages or rates).
  Future<void> suppressPrompt() async {
    await _loadPrompt();
    _prompt['suppressed'] = true;
    await _savePrompt();
  }

  // --- Local persistence (a tiny JSON file, like the notifications watermark) -

  Future<File?> _promptFile() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/feedback_prompt.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPrompt() async {
    if (_promptLoaded) return;
    _promptLoaded = true;
    try {
      final file = await _promptFile();
      if (file == null || !file.existsSync()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) _prompt = decoded;
    } catch (_) {
      // Corrupt/missing — start fresh.
    }
  }

  Future<void> _savePrompt() async {
    try {
      final file = await _promptFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode(_prompt));
    } catch (_) {
      // Best-effort; a lost flag just risks one extra prompt.
    }
  }
}
