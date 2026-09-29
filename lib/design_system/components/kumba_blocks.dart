import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_strings.dart';
import 'kumba_pressable.dart';

/// Color-block metric — cartes saturées type Adidas / furniture.
class KumbaColorBlock extends StatelessWidget {
  const KumbaColorBlock({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.onTap,
    this.foreground,
    this.caption,
    this.wide = false,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? foreground;
  final String? caption;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final ink = foreground ?? AppColors.secondary;
    final child = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, wide ? 20 : 16, 16, wide ? 18 : 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.42),
            blurRadius: 22,
            offset: const Offset(0, 10),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: ink),
                ),
              const Spacer(),
            ],
          ),
          SizedBox(height: wide ? 22 : 16),
          Text(
            S.auto(label),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: ink.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: ink,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              S.auto(caption!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ink.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return KumbaPressable(onTap: onTap, child: child);
  }
}

/// Dual action — Send (ice) / Receive (navy) du file-transfer.
class KumbaDualAction extends StatelessWidget {
  const KumbaDualAction({
    super.key,
    required this.primaryLabel,
    required this.primaryCaption,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryCaption,
    required this.onSecondary,
    this.primaryIcon = Icons.point_of_sale_rounded,
    this.secondaryIcon = Icons.south_west_rounded,
  });

  final String primaryLabel;
  final String primaryCaption;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final String secondaryCaption;
  final VoidCallback onSecondary;
  final IconData primaryIcon;
  final IconData secondaryIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _tile(
          context,
          label: primaryLabel,
          caption: primaryCaption,
          icon: primaryIcon,
          onTap: onPrimary,
          color: AppColors.fab,
          foreground: Colors.white,
        ),
        const SizedBox(height: 10),
        _tile(
          context,
          label: secondaryLabel,
          caption: secondaryCaption,
          icon: secondaryIcon,
          onTap: onSecondary,
          color: AppColors.secondary,
          foreground: Colors.white,
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context, {
    required String label,
    required String caption,
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    required Color foreground,
  }) {
    return KumbaPressable(
      scale: AppMotion.pressScaleStrong,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.16),
              blurRadius: 20,
              offset: const Offset(0, 10),
              spreadRadius: -8,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.auto(label),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    S.auto(caption),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: foreground.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compteur qui tick jusqu’à la valeur (montants dashboard).
class KumbaNumberTicker extends StatelessWidget {
  const KumbaNumberTicker({
    super.key,
    required this.value,
    required this.builder,
    this.duration = AppMotion.ticker,
  });

  final double value;
  final String Function(double value) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return Text(builder(value));
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: AppMotion.easeOut,
      builder: (context, v, _) => Text(builder(v)),
    );
  }
}

/// KPI pastel — une teinte par famille, jamais un aplat sombre.
class KumbaTintKpi extends StatelessWidget {
  const KumbaTintKpi({
    super.key,
    required this.label,
    required this.value,
    required this.bg,
    required this.accent,
    this.caption,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final Color bg;
  final Color accent;
  final String? caption;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: double.infinity,
      height: 118,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: accent.withValues(alpha: 0.16)),
                  ),
                  child: Icon(icon, size: 14, color: accent),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  S.auto(label),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              S.auto(caption!),
              style: const TextStyle(
                color: AppColors.inkFaint,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return KumbaPressable(onTap: onTap, child: child);
  }
}
