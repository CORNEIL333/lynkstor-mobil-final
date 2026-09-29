import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum LynkMood {
  idle,
  greeting,
  thinking,
  listening,
  replying,
  alert,
  sorry,
  celebrate,
  offline,
}

/// Mascotte Lynk — sphère peinte (CustomPainter), jamais une photo ni un SVG.
/// Idle : respiration + clignement. Greeting : légère inclinaison + main.
/// Figé si reduce-motion / mode perf.
class LynkAvatar extends StatefulWidget {
  const LynkAvatar({
    super.key,
    this.mood = LynkMood.idle,
    this.size = 64,
    this.accent,
    this.enabled = true,
    this.showOnline = false,
  });

  final LynkMood mood;
  final double size;
  final Color? accent;
  final bool enabled;
  final bool showOnline;

  @override
  State<LynkAvatar> createState() => _LynkAvatarState();
}

class _LynkAvatarState extends State<LynkAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant LynkAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduce = !widget.enabled;
    if (reduce) {
      _c.stop();
      _c.value = 0;
      return;
    }
    switch (widget.mood) {
      case LynkMood.thinking:
      case LynkMood.listening:
        _c.duration = const Duration(milliseconds: 800);
        _c.repeat();
      case LynkMood.celebrate:
        _c.duration = const Duration(milliseconds: 600);
        _c.repeat();
      case LynkMood.greeting:
        _c.duration = const Duration(milliseconds: 1800);
        _c.repeat();
      default:
        _c.duration = const Duration(milliseconds: 2400);
        _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce =
        !widget.enabled ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final child = AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _LynkPainter(
            t: reduce ? 0 : _c.value,
            mood: widget.mood,
            accent: widget.accent ?? AppColors.lynkStar,
            showOnline: widget.showOnline,
          ),
        );
      },
    );
    return Semantics(
      label: 'Lynk',
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(child: child),
      ),
    );
  }
}

class _LynkPainter extends CustomPainter {
  _LynkPainter({
    required this.t,
    required this.mood,
    required this.accent,
    required this.showOnline,
  });

  final double t;
  final LynkMood mood;
  final Color accent;
  final bool showOnline;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final breath = 1 + 0.028 * math.sin(t * math.pi * 2);
    final bounce = mood == LynkMood.celebrate
        ? 0.05 * math.sin(t * math.pi * 2)
        : 0.0;
    final tilt = mood == LynkMood.greeting
        ? 0.10 * math.sin(t * math.pi * 2)
        : 0.0;

    canvas.save();
    canvas.translate(c.dx, c.dy - s * bounce);
    canvas.rotate(tilt);
    canvas.scale(breath);

    final r = s * 0.40;

    if (mood == LynkMood.greeting) {
      _waveHand(canvas, r, s);
    }

    // Soft contact shadow — grounds the sphere.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r * 0.92),
        width: r * 1.15,
        height: r * 0.22,
      ),
      Paint()
        ..color = const Color(0xFF0B3A8C).withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    final bodyRect = Rect.fromCircle(center: Offset.zero, radius: r);
    final body = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.32, -0.42),
        radius: 1.05,
        colors: [
          Color(0xFF7EC8FF),
          Color(0xFF2F8FF5),
          Color(0xFF1570E8),
          Color(0xFF0B4CC8),
        ],
        stops: [0.0, 0.38, 0.78, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(Offset.zero, r, body);

    // Equator shade — volume without a photo.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.18, 0.55),
          radius: 0.95,
          colors: [
            Colors.transparent,
            const Color(0xFF0839A8).withValues(alpha: 0.22),
          ],
        ).createShader(bodyRect),
    );

    // Specular primary.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.28, -r * 0.34),
        width: r * 0.52,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
    // Specular pin.
    canvas.drawCircle(
      Offset(-r * 0.18, -r * 0.42),
      r * 0.07,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );

    // Hairline rim.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018,
    );

    final cheek = Paint()..color = accent.withValues(alpha: 0.88);
    canvas.drawCircle(Offset(r * 0.36, r * 0.16), r * 0.10, cheek);

    final eyeWhite = Paint()..color = const Color(0xFFFBFCFE);
    final pupil = Paint()..color = const Color(0xFF121826);
    final blink = (mood == LynkMood.idle || mood == LynkMood.greeting) &&
            (t * 12 % 12) > 11.55
        ? 0.18
        : 1.0;
    final look = mood == LynkMood.thinking
        ? 0.10 * math.sin(t * math.pi * 4)
        : 0.0;
    final eyeH = r * 0.20 * blink;
    _eye(
      canvas,
      Offset(-r * 0.22 + look * r, -r * 0.08),
      r * 0.15,
      eyeH,
      eyeWhite,
      pupil,
    );
    _eye(
      canvas,
      Offset(r * 0.18 + look * r, -r * 0.10),
      r * 0.17,
      eyeH,
      eyeWhite,
      pupil,
    );

    final mouth = Paint()
      ..color = const Color(0xFFFBF7F2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.032
      ..strokeCap = StrokeCap.round;
    final path = Path();
    switch (mood) {
      case LynkMood.sorry:
        path.moveTo(-r * 0.16, r * 0.32);
        path.quadraticBezierTo(0, r * 0.18, r * 0.16, r * 0.32);
      case LynkMood.alert:
        path.addOval(
          Rect.fromCircle(center: Offset(0, r * 0.28), radius: r * 0.07),
        );
        mouth.style = PaintingStyle.fill;
      case LynkMood.greeting:
      case LynkMood.celebrate:
        path.moveTo(-r * 0.16, r * 0.22);
        path.quadraticBezierTo(0, r * 0.40, r * 0.16, r * 0.22);
      default:
        path.moveTo(-r * 0.16, r * 0.24);
        path.quadraticBezierTo(0, r * 0.36, r * 0.16, r * 0.24);
    }
    canvas.drawPath(path, mouth);

    if (mood == LynkMood.listening) {
      final ring = Paint()
        ..color = AppColors.aiCyan.withValues(
          alpha: 0.28 + 0.18 * math.sin(t * math.pi * 2),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.026;
      canvas.drawCircle(
        Offset.zero,
        r * (1.10 + 0.06 * math.sin(t * math.pi * 2)),
        ring,
      );
    }
    if (mood == LynkMood.thinking) {
      final halo = Paint()
        ..color = AppColors.aiGlow.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawCircle(Offset.zero, r * 1.06, halo);
    }
    if (mood == LynkMood.offline) {
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()..color = Colors.white.withValues(alpha: 0.38),
      );
    }

    if (showOnline && mood != LynkMood.offline) {
      final badgeC = Offset(r * 0.64, r * 0.62);
      canvas.drawCircle(badgeC, r * 0.20, Paint()..color = Colors.white);
      canvas.drawCircle(
        badgeC,
        r * 0.13,
        Paint()..color = AppColors.lynkOnline,
      );
    }

    canvas.restore();
  }

  void _waveHand(Canvas canvas, double r, double s) {
    final wave = 0.42 * math.sin(t * math.pi * 2);
    canvas.save();
    canvas.translate(r * 0.78, -r * 0.12);
    canvas.rotate(-0.55 + wave);
    final arm = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7EC8FF), Color(0xFF1570E8)],
      ).createShader(Rect.fromLTWH(-r * 0.10, 0, r * 0.20, r * 0.42));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, r * 0.16),
          width: r * 0.18,
          height: r * 0.42,
        ),
        Radius.circular(r * 0.10),
      ),
      arm,
    );
    canvas.drawCircle(
      Offset(0, -r * 0.08),
      r * 0.16,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFA8DCFF), Color(0xFF2F8FF5)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.16)),
    );
    canvas.drawCircle(
      Offset(-r * 0.05, -r * 0.12),
      r * 0.045,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
    canvas.restore();
  }

  void _eye(
    Canvas canvas,
    Offset o,
    double w,
    double h,
    Paint white,
    Paint pupil,
  ) {
    canvas.drawOval(
      Rect.fromCenter(center: o, width: w * 2, height: h * 2),
      white,
    );
    canvas.drawCircle(o.translate(0, h * 0.12), w * 0.42, pupil);
  }

  @override
  bool shouldRepaint(covariant _LynkPainter old) =>
      old.t != t ||
      old.mood != mood ||
      old.accent != accent ||
      old.showOnline != showOnline;
}

/// Halo lent derrière les surfaces IA.
class AiAurora extends StatelessWidget {
  const AiAurora({super.key, this.performance = false});

  final bool performance;

  @override
  Widget build(BuildContext context) {
    if (performance ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1A0E5A8C), Color(0x00000000)],
          ),
        ),
      );
    }
    return const _AuroraLoop();
  }
}

class _AuroraLoop extends StatefulWidget {
  const _AuroraLoop();

  @override
  State<_AuroraLoop> createState() => _AuroraLoopState();
}

class _AuroraLoopState extends State<_AuroraLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.6 + t * 0.4, -1),
              end: Alignment(0.6 - t * 0.4, 1),
              colors: [
                AppColors.ocean.withValues(alpha: 0.10),
                AppColors.aiViolet.withValues(alpha: 0.07),
                AppColors.sky.withValues(alpha: 0.06),
                Colors.transparent,
              ],
            ),
          ),
        );
      },
    );
  }
}
