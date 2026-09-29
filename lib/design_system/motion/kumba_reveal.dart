import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

/// Pop-in staggered : fade + translateY + scale(0.94→1). Jamais scale(0).
class KumbaReveal extends StatelessWidget {
  const KumbaReveal({
    super.key,
    required this.child,
    this.order = 0,
    this.offset = 16,
  });

  final Widget child;
  final int order;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;

    final start = (order * 0.07).clamp(0.0, 0.48).toDouble();
    final curve = Interval(start, 1, curve: AppMotion.easeOut);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.entrance,
      curve: Curves.linear,
      child: child,
      builder: (context, value, child) {
        final progress = curve.transform(value);
        final scale = AppMotion.enterScale +
            (1 - AppMotion.enterScale) * progress;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, offset * (1 - progress)),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
