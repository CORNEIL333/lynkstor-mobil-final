import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_strings.dart';
import 'kumba_pressable.dart';

/// Titre de section style iOS (large, tracking serré).
class KumbaSectionTitle extends StatelessWidget {
  const KumbaSectionTitle(
    this.title, {
    super.key,
    this.action,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget? action;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.auto(title),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (action != null) action!,
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(S.auto(actionLabel!)),
            ),
        ],
      ),
    );
  }
}

/// Bouton chrome rond glass (AppBar iOS).
class KumbaChromeButton extends StatelessWidget {
  const KumbaChromeButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.72),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.95),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: dark ? 0.12 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              if (badge != null && badge! > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: AppColors.rose,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

/// Liste groupée inset style iOS Settings.
class KumbaInsetGroup extends StatelessWidget {
  const KumbaInsetGroup({
    super.key,
    required this.children,
    this.header,
    this.footer,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              S.auto(header!).toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: dark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : AppColors.outlineVariant.withValues(alpha: 0.55),
            ),
            boxShadow: dark
                ? null
                : [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                      spreadRadius: -6,
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : AppColors.outlineVariant.withValues(alpha: 0.55),
                  ),
              ],
            ],
          ),
        ),
        if (footer != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              S.auto(footer!),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

/// Ligne d’une inset group.
class KumbaInsetRow extends StatelessWidget {
  const KumbaInsetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.icon,
    this.iconColor,
    this.onTap,
    this.value,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = iconColor ?? AppColors.primary;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: accent),
            )
          else
            const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.auto(title),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (subtitle != null)
                  Text(
                    S.auto(subtitle!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (value != null)
            Text(
              value!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          if (trailing != null) trailing!,
          if (onTap != null && trailing == null && value == null)
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: row,
      ),
    );
  }
}

/// Tuile app-style (icône ronde + label) pour quick actions.
class KumbaAppTile extends StatelessWidget {
  const KumbaAppTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 58.0 : 52.0;
    return KumbaPressable(
      onTap: onTap,
      child: SizedBox(
        width: large ? 76 : 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(large ? 20 : 18),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.38),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                    spreadRadius: -3,
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: AppColors.secondary,
                size: large ? 26 : 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.auto(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wallet-style hero balance card.
class KumbaWalletCard extends StatelessWidget {
  const KumbaWalletCard({
    super.key,
    required this.eyebrow,
    required this.amount,
    this.caption,
    this.onPrimary,
    this.primaryLabel,
    this.onSecondary,
    this.secondaryLabel,
  });

  final String eyebrow;
  final String amount;
  final String? caption;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: AppColors.fab,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A7BC7).withValues(alpha: 0.42),
            blurRadius: 32,
            offset: const Offset(0, 16),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -50,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
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
                    ),
                    child: Text(
                      S.auto(eyebrow),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  height: 1.05,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 8),
                Text(
                  S.auto(caption!),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (onPrimary != null || onSecondary != null) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (onPrimary != null)
                      Expanded(
                        child: _walletBtn(
                          label: primaryLabel ?? 'Vendre',
                          filled: true,
                          onTap: onPrimary!,
                        ),
                      ),
                    if (onPrimary != null && onSecondary != null)
                      const SizedBox(width: 10),
                    if (onSecondary != null)
                      Expanded(
                        child: _walletBtn(
                          label: secondaryLabel ?? 'Détails',
                          filled: false,
                          onTap: onSecondary!,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletBtn({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return KumbaPressable(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Text(
          S.auto(label),
          style: TextStyle(
            color: filled ? AppColors.primaryContainer : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// Bento metric tile (large or compact).
class KumbaBentoMetric extends StatelessWidget {
  const KumbaBentoMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.wide = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final child = Container(
      width: double.infinity,
      padding: EdgeInsets.all(wide ? 18 : 14),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.07)
              : color.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: dark ? 0.12 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          SizedBox(height: wide ? 18 : 14),
          Text(
            S.auto(label),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return KumbaPressable(onTap: onTap, child: child);
  }
}

/// Fond mesh plus marqué (ciel + turquoise).
class KumbaMeshBackground extends StatelessWidget {
  const KumbaMeshBackground({
    super.key,
    required this.child,
    this.performanceMode = false,
  });

  final Widget child;
  final bool performanceMode;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    return ColoredBox(
      color: dark ? AppColors.darkBg : AppColors.pageBg,
      child: child,
    );
  }
}
