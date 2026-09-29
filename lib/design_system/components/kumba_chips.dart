import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_strings.dart';
import 'kumba_pressable.dart';

/// Search pill — Adidas / AI-personalized header.
class KumbaSearchPill extends StatelessWidget {
  const KumbaSearchPill({
    super.key,
    this.hint,
    this.onTap,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.enabled = true,
  });

  final String? hint;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final fill = dark ? Colors.white.withValues(alpha: 0.10) : Colors.white;
    final child = Container(
      height: 48,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.95),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: dark ? 0.28 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -8,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            PhosphorIconsRegular.magnifyingGlass,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: onTap != null
                ? Text(
                    S.auto(hint ?? 'Rechercher…'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                : TextField(
                    controller: controller,
                    enabled: enabled,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: S.auto(hint ?? 'Rechercher…'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    if (onTap == null) return child;
    return KumbaPressable(onTap: onTap, child: child);
  }
}

class KumbaFilterChipData {
  const KumbaFilterChipData({required this.id, required this.label});
  final String id;
  final String label;
}

/// Horizontal filter chips with morphing pill (Adidas / furniture).
class KumbaChipBar extends StatelessWidget {
  const KumbaChipBar({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
  });

  final List<KumbaFilterChipData> items;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final selected = item.id == selectedId;
          return KumbaPressable(
            scale: 0.96,
            onTap: () {
              HapticFeedback.selectionClick();
              onSelected(item.id);
            },
            child: AnimatedContainer(
              duration: AppMotion.chip,
              curve: AppMotion.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary
                    : (AppColors.isDark(context)
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white),
                borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                S.auto(item.label),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Circle chrome (furniture product header).
class KumbaCircleIcon extends StatelessWidget {
  const KumbaCircleIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    return KumbaPressable(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ??
              (filled
                  ? AppColors.primary
                  : (dark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white)),
          boxShadow: [
            BoxShadow(
              color: AppColors.dock.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 20,
          color: foreground ??
              (filled ? Colors.white : AppColors.secondary),
        ),
      ),
    );
  }
}
