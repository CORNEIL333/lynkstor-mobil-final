import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_strings.dart';

/// Distingue toujours une suggestion modèle d’une donnée Drift.
class KumbaAiBadge extends StatelessWidget {
  const KumbaAiBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.lynkViolet,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
      ),
      child: Text(
        S.tr('Généré par IA', 'AI generated'),
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class KumbaAiFrame extends StatelessWidget {
  const KumbaAiFrame({super.key, required this.child, this.radius});

  final Widget child;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? AppSpacing.radiusLg;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lynkViolet,
        borderRadius: BorderRadius.circular(r),
      ),
      padding: const EdgeInsets.all(1.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.isDark(context)
              ? AppColors.darkCard
              : AppColors.creamCard,
          borderRadius: BorderRadius.circular(r - 1),
        ),
        child: child,
      ),
    );
  }
}
