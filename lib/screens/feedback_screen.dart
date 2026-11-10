import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/auth_service.dart';
import '../services/feedback_service.dart';
import '../theme/app_dimens.dart';
import '../widgets/common/common.dart';

/// The feedback form. Opened from Account -> "Send feedback" (no prefill) and
/// from the contextual sentiment prompt (prefilled topic + sentiment). Submits a
/// row to the Supabase `feedback` table via [FeedbackService].
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    super.key,
    this.initialCategory,
    this.sentiment,
  });

  /// Pre-selected topic (e.g. the gate routes "not great" -> a bug report).
  final FeedbackCategory? initialCategory;

  /// Carried through from the gate prompt so the row records how they felt.
  final FeedbackSentiment? sentiment;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late FeedbackCategory _category =
      widget.initialCategory ?? FeedbackCategory.suggestion;
  final TextEditingController _message = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      Get.snackbar(
        'Add a message',
        'Tell us a little about it first.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    setState(() => _submitting = true);
    final ok = await FeedbackService.to.submit(
      category: _category,
      message: text,
      sentiment: widget.sentiment,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Get.back<void>();
      Get.snackbar(
        'Thanks! 🙌',
        'Your feedback helps us make the app better.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    } else {
      Get.snackbar(
        "Couldn't send",
        AuthService.to.isConfigured
            ? 'Please try again in a moment.'
            : 'Sign in to send feedback.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const GradientAppBar(title: 'Send feedback'),
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ResponsiveContainer(
              maxWidth: 560,
              child: GlassCard(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "We'd love your thoughts",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Bugs, ideas, or just hello — it all helps.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Topic',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final c in FeedbackCategory.values)
                          ChoiceChip(
                            label: Text(c.label),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: _message,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Your message',
                        hintText: "What's on your mind?",
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    GradientButton(
                      label: 'Send feedback',
                      icon: Icons.send_rounded,
                      loading: _submitting,
                      onPressed: _submitting ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
