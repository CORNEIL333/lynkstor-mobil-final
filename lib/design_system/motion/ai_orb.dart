import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum AiOrbState {
  idle,
  listening,
  thinking,
  searching,
  generating,
  success,
  warning,
  error,
  offline,
}

/// Animation signature de l'assistant — pulsation + réseau de points, sobre.
class AiOrb extends StatefulWidget {
  const AiOrb({
    super.key,
    this.state = AiOrbState.idle,
    this.size = 64,
    this.enabled = true,
  });

  final AiOrbState state;
  final double size;
  final bool enabled;

  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant AiOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.state) {
      case AiOrbState.success:
        return AppColors.turquoise;
      case AiOrbState.warning:
        return AppColors.warning;
      case AiOrbState.error:
        return AppColors.error;
      case AiOrbState.offline:
        return AppColors.grey500;
      case AiOrbState.thinking:
      case AiOrbState.searching:
      case AiOrbState.generating:
        return AppColors.turquoise;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.enabled ? _controller.value : 0.0;
        final pulse = widget.state == AiOrbState.idle
            ? 0.92 + 0.08 * math.sin(t * math.pi * 2)
            : 0.88 + 0.12 * math.sin(t * math.pi * 4);

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _OrbPainter(
              progress: t,
              pulse: pulse,
              color: _color,
              state: widget.state,
            ),
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.progress,
    required this.pulse,
    required this.color,
    required this.state,
  });

  final double progress;
  final double pulse;
  final Color color;
  final AiOrbState state;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 * pulse;

    final glow = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, r * 1.15, glow);

    final fill = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.55),
          AppColors.indigoDeep.withValues(alpha: 0.9),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r * 0.72, fill);

    final ring = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, r * 0.85, ring);

    // Réseau de points (graine / information)
    final dots = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 6; i++) {
      final a = progress * math.pi * 2 + i * math.pi / 3;
      final dist = r * 0.38;
      final p = Offset(
        center.dx + math.cos(a) * dist,
        center.dy + math.sin(a) * dist,
      );
      canvas.drawCircle(p, 2.2, dots);
      if (i > 0) {
        final prevA = progress * math.pi * 2 + (i - 1) * math.pi / 3;
        final prev = Offset(
          center.dx + math.cos(prevA) * dist,
          center.dy + math.sin(prevA) * dist,
        );
        canvas.drawLine(
          prev,
          p,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.25)
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.pulse != pulse ||
      oldDelegate.color != color ||
      oldDelegate.state != state;
}
