import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_strings.dart';
import 'kumba_pressable.dart';

/// Carte iOS premium — rayon uniforme, ombre teintée, dark-aware.
class KumbaCard extends StatelessWidget {
  const KumbaCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
    this.borderColor,
    this.elevation,
    this.radius,
    this.floating = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double? elevation;
  final double? radius;

  /// Ombre douce + lévitation.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = AppColors.isDark(context);
    final r = radius ?? AppSpacing.radiusLg;
    final elev = elevation ?? (floating ? 1.0 : AppSpacing.elevationNone);
    final shape = BorderRadius.circular(r);
    final fill = color ?? AppColors.card(context).withValues(alpha: 0.98);

    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: shape,
        border: Border.all(
          color:
              borderColor ??
              (floating
                  ? (dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppColors.primary.withValues(alpha: 0.08))
                  : scheme.outlineVariant.withValues(
                      alpha: dark ? 0.35 : 0.45,
                    )),
          width: floating ? 1 : 0.8,
        ),
        boxShadow: elev > 0
            ? [
                BoxShadow(
                  color: dark
                      ? Colors.black.withValues(alpha: 0.35)
                      : AppColors.primaryContainer.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                  spreadRadius: -8,
                ),
                if (!dark)
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.7),
                    blurRadius: 0,
                    offset: const Offset(0, -0.5),
                  ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
        child: child,
      ),
    );

    if (onTap == null) return card;

    return KumbaPressable(onTap: onTap, child: card);
  }
}

/// KPI tile — identité propre avec pastille d’accent ronde.
class KumbaKpiCard extends StatelessWidget {
  const KumbaKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;

    return KumbaCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  S.auto(label),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null)
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(icon, size: 17, color: accent),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              letterSpacing: -0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              S.auto(subtitle!),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Grande carte métrique hero — aplat primaire.
class KumbaHeroMetricCard extends StatelessWidget {
  const KumbaHeroMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.trailing,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.fab,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryContainer.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 14),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            right: 28,
            bottom: -50,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.turquoise.withValues(alpha: 0.28),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusCapsule,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        S.auto(label),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      child: const Icon(
                        PhosphorIconsRegular.chartLineUp,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    S.auto(subtitle!),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
