import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Full-screen win overlay: a burst of confetti behind a glassy result card.
class JigsawCelebration extends StatefulWidget {
  const JigsawCelebration({
    super.key,
    required this.moves,
    required this.pieces,
    required this.onPlayAgain,
    required this.onNewImage,
  });

  final int moves;
  final int pieces;
  final VoidCallback onPlayAgain;
  final VoidCallback onNewImage;

  @override
  State<JigsawCelebration> createState() => _JigsawCelebrationState();
}

class _JigsawCelebrationState extends State<JigsawCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..forward();

  late final AnimationController _card = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  late final List<_Confetto> _pieces = _buildConfetti();

  List<_Confetto> _buildConfetti() {
    final rng = math.Random(7);
    const colors = [
      Color(0xFFFF5252),
      Color(0xFFFFD740),
      Color(0xFF69F0AE),
      Color(0xFF40C4FF),
      Color(0xFFE040FB),
      Color(0xFFFF6E40),
    ];
    return List.generate(110, (i) {
      return _Confetto(
        x: rng.nextDouble(),
        delay: rng.nextDouble() * 0.35,
        speed: 0.7 + rng.nextDouble() * 0.6,
        drift: (rng.nextDouble() - 0.5) * 0.4,
        size: 6 + rng.nextDouble() * 8,
        color: colors[i % colors.length],
        rotations: 2 + rng.nextDouble() * 4,
        round: rng.nextBool(),
      );
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    _card.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _confetti,
            builder: (context, _) => CustomPaint(
              painter: _ConfettiPainter(_pieces, _confetti.value),
            ),
          ),
        ),
        Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _card, curve: Curves.elasticOut),
            child: Container(
              width: 320,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.5),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Puzzle Solved!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Stat(label: 'Moves', value: '${widget.moves}'),
                      _Stat(label: 'Pieces', value: '${widget.pieces}'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onPlayAgain,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Play Again'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onNewImage,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('New Image'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Confetto {
  _Confetto({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.size,
    required this.color,
    required this.rotations,
    required this.round,
  });

  final double x; // 0..1 start across the width
  final double delay; // 0..1 fraction of the run before it starts falling
  final double speed; // vertical speed multiplier
  final double drift; // horizontal drift
  final double size;
  final Color color;
  final double rotations;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Confetto> pieces;
  final double t; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in pieces) {
      final local = ((t - c.delay) / (1 - c.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -0.1 + (1.2 * local * c.speed);
      if (y > 1.1) continue;
      final x = (c.x + c.drift * local) * size.width;
      final py = y * size.height;
      final fade = local > 0.85 ? (1 - (local - 0.85) / 0.15) : 1.0;

      canvas.save();
      canvas.translate(x, py);
      canvas.rotate(c.rotations * local * 2 * math.pi);
      final paint = Paint()..color = c.color.withValues(alpha: fade.clamp(0.0, 1.0));
      if (c.round) {
        canvas.drawCircle(Offset.zero, c.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: c.size, height: c.size * 0.6),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
