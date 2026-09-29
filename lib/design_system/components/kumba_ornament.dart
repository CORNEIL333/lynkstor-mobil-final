import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Puits d’icône — surface teintée, rayon concentrique, jamais une photo.
class KumbaIconWell extends StatelessWidget {
  const KumbaIconWell({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
    this.iconSize = 18,
    this.filled = false,
    this.radius,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool filled;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? (size * 0.32);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
          color: color.withValues(alpha: filled ? 0.0 : 0.16),
        ),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: filled ? Colors.white : color,
      ),
    );
  }
}

/// Cercles superposés + glyphe Phosphor — ornement de carte d’action.
class KumbaSceneOrnament extends StatelessWidget {
  const KumbaSceneOrnament({
    super.key,
    required this.icon,
    this.size = 128,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              right: size * 0.02,
              bottom: size * 0.04,
              child: _orb(size * 0.72, Colors.white.withValues(alpha: 0.10)),
            ),
            Positioned(
              right: size * 0.28,
              bottom: size * 0.28,
              child: _orb(size * 0.38, Colors.white.withValues(alpha: 0.12)),
            ),
            Positioned(
              right: size * 0.08,
              top: size * 0.12,
              child: _orb(size * 0.22, Colors.white.withValues(alpha: 0.16)),
            ),
            Icon(
              icon,
              size: size * 0.46,
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orb(double d, Color color) {
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Mini sparkline peinte — KPI, pas une image.
class KumbaSparkline extends StatelessWidget {
  const KumbaSparkline({
    super.key,
    required this.color,
    this.width = 64,
    this.height = 28,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(color: color),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.9,
        size.width * 0.45,
        size.height * 0.45,
      )
      ..quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.08,
        size.width,
        size.height * 0.22,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    final p = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.9,
        size.width * 0.45,
        size.height * 0.45,
      )
      ..quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.08,
        size.width,
        size.height * 0.22,
      );
    canvas.drawPath(path, p);
    canvas.drawCircle(
      Offset(size.width, size.height * 0.22),
      2.4,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.color != color;
}

/// Cercle CTA interne — bouton dans le bouton.
class KumbaCtaDisk extends StatelessWidget {
  const KumbaCtaDisk({
    super.key,
    required this.icon,
    this.size = 36,
    this.filled = true,
    this.foreground,
    this.background,
  });

  final IconData icon;
  final double size;
  final bool filled;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ??
            (filled
                ? Colors.white
                : Colors.white.withValues(alpha: 0.18)),
        shape: BoxShape.circle,
        border: filled
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Icon(
        icon,
        size: size * 0.46,
        color: foreground ?? (filled ? AppColors.fab : Colors.white),
      ),
    );
  }
}
