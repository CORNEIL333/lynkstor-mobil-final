import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_strings.dart';

enum KumbaButtonVariant {
  primary,
  secondary,
  outline,
  ghost,
  destructive,
  gold, // alias turquoise (rétrocompat)
  ink, // CTA encre type furniture / calorie
}

enum KumbaButtonSize { small, medium, large }

/// Bouton iOS premium — press scale immédiat, rayons uniformes, gradient ciel.
class KumbaButton extends StatefulWidget {
  const KumbaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = KumbaButtonVariant.primary,
    this.size = KumbaButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.isExpanded = true,
    this.haptic = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final KumbaButtonVariant variant;
  final KumbaButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool isExpanded;
  final bool haptic;

  @override
  State<KumbaButton> createState() => _KumbaButtonState();
}

class _KumbaButtonState extends State<KumbaButton> {
  bool _down = false;

  double get _height {
    switch (widget.size) {
      case KumbaButtonSize.small:
        return AppSpacing.buttonHeightSm;
      case KumbaButtonSize.medium:
        return AppSpacing.buttonHeight;
      case KumbaButtonSize.large:
        return 56;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Color bg;
    Color fg;
    Color? border;
    List<BoxShadow>? shadows;

    final dark = AppColors.isDark(context);

    switch (widget.variant) {
      case KumbaButtonVariant.primary:
        bg = AppColors.primary;
        // Utiliser onPrimary du token plutôt que Colors.white hardcodé :
        // garantit que le couple bg/fg reste conforme WCAG AA si la couleur
        // primaire change (ex. : orange → bleu dans un rebranding).
        fg = AppColors.onPrimary;
        shadows = [
          BoxShadow(
            color: AppColors.primaryContainer.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ];
      case KumbaButtonVariant.secondary:
        bg = dark ? AppColors.darkCard : AppColors.surfaceContainerLow;
        fg = dark ? AppColors.darkText : AppColors.secondary;
        border = AppColors.outlineVariant.withValues(alpha: dark ? 0.4 : 1);
      case KumbaButtonVariant.outline:
        bg = AppColors.card(context);
        fg = AppColors.primary;
        border = AppColors.primary.withValues(alpha: dark ? 0.5 : 0.28);
      case KumbaButtonVariant.ghost:
        bg = Colors.transparent;
        fg = dark ? AppColors.darkText : AppColors.primary;
      case KumbaButtonVariant.destructive:
        bg = AppColors.error;
        fg = Colors.white;
        shadows = [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ];
      case KumbaButtonVariant.gold:
        bg = AppColors.turquoise;
        fg = Colors.white;
      case KumbaButtonVariant.ink:
        bg = AppColors.secondary;
        fg = Colors.white;
    }

    if (!enabled) {
      bg = bg.withValues(alpha: 0.4);
      fg = fg.withValues(alpha: 0.6);
      shadows = null;
    }

    final radius = BorderRadius.circular(
      widget.size == KumbaButtonSize.small
          ? AppSpacing.radiusMd
          : AppSpacing.radiusCapsule,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: S.auto(widget.label),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                if (widget.haptic) HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down && !reduce ? AppMotion.pressScale : 1,
          duration: AppMotion.instant,
          curve: AppMotion.easeOut,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            height: _height,
            width: widget.isExpanded ? double.infinity : null,
            padding: EdgeInsets.symmetric(
              horizontal: widget.size == KumbaButtonSize.small ? 14 : 22,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(
                color:
                    border ??
                    (widget.variant == KumbaButtonVariant.primary
                        ? Colors.white.withValues(alpha: 0.28)
                        : Colors.transparent),
                width: border != null ? 1.2 : 1,
              ),
              boxShadow: shadows,
            ),
            child: Center(
              child: widget.isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: fg,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            size: widget.size == KumbaButtonSize.small
                                ? 18
                                : 20,
                            color: fg,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          S.auto(widget.label),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
