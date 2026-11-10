import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:in_app_review/in_app_review.dart';

import '../screens/feedback_screen.dart';
import '../services/feedback_service.dart';
import '../theme/app_dimens.dart';

/// Shows a one-tap "how's it going?" prompt at high-satisfaction moments and
/// routes by sentiment:
///   😍 happy   -> native store review (a private thank-you when the store
///                 review isn't available, e.g. an unpublished build/Simulator)
///   😐 neutral -> the feedback form (topic: Suggestion)
///   😞 sad     -> the feedback form (topic: Problem)
///
/// Sending bad sentiment to the form (not the store) keeps complaints private
/// instead of in a 1-star public review. The prompt is frequency-capped by
/// [FeedbackService] so it never nags.
abstract final class FeedbackPrompter {
  /// Call at a positive moment (a save, a solved puzzle). Shows the prompt only
  /// when the service's frequency cap allows it; a no-op otherwise.
  static Future<void> maybePrompt({required String trigger}) async {
    if (!Get.isRegistered<FeedbackService>()) return;
    final show = await FeedbackService.to.registerSuccessAndShouldPrompt();
    if (!show) return;
    await Get.bottomSheet<void>(
      const _SentimentSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}

class _SentimentSheet extends StatelessWidget {
  const _SentimentSheet();

  void _pick(FeedbackSentiment sentiment) {
    Get.back<void>(); // close the sheet first
    switch (sentiment) {
      case FeedbackSentiment.happy:
        // Record the positive sentiment, then ask for a store rating.
        unawaited(FeedbackService.to.submit(
          category: FeedbackCategory.praise,
          message: '',
          sentiment: sentiment,
        ));
        unawaited(_requestStoreReview());
      case FeedbackSentiment.neutral:
        Get.to<void>(() => const FeedbackScreen(
              initialCategory: FeedbackCategory.suggestion,
              sentiment: FeedbackSentiment.neutral,
            ));
      case FeedbackSentiment.sad:
        Get.to<void>(() => const FeedbackScreen(
              initialCategory: FeedbackCategory.bug,
              sentiment: FeedbackSentiment.sad,
            ));
    }
  }

  Future<void> _requestStoreReview() async {
    // Best-effort native review sheet — it only actually shows on a published
    // build (a silent no-op on the Simulator / unpublished apps), so always
    // thank them too, giving the tap a visible result either way.
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) await review.requestReview();
    } catch (_) {
      // Ignore — the thank-you below is the fallback.
    }
    Get.snackbar(
      'Thanks! 💛',
      "So glad you're enjoying it.",
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'How are you enjoying the app?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Face(
                  emoji: '😍',
                  label: 'Love it',
                  onTap: () => _pick(FeedbackSentiment.happy),
                ),
                _Face(
                  emoji: '😐',
                  label: "It's okay",
                  onTap: () => _pick(FeedbackSentiment.neutral),
                ),
                _Face(
                  emoji: '😞',
                  label: 'Not great',
                  onTap: () => _pick(FeedbackSentiment.sad),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
