import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_strings.dart';
import '../motion/lynk_avatar.dart';
import 'kumba_button.dart';

class KumbaLoading extends StatelessWidget {
  const KumbaLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
              backgroundColor: AppColors.primaryFixed,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              S.auto(message!),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class KumbaSkeletonList extends StatelessWidget {
  const KumbaSkeletonList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkCard
        : AppColors.surfaceContainer;
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkBorder
        : AppColors.primaryFixed;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, __) => Container(
          height: 76,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
        ),
      ),
    );
  }
}

class KumbaEmptyState extends StatelessWidget {
  const KumbaEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: S.auto(title),
              child: Container(
                width: 108,
                height: 108,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.lynkVioletSoft,
                  shape: BoxShape.circle,
                ),
                child: LynkAvatar(
                  key: ValueKey(icon),
                  size: 72,
                  mood: LynkMood.sorry,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              S.auto(title),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                S.auto(subtitle!),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              KumbaButton(
                label: actionLabel!,
                onPressed: onAction,
                isExpanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class KumbaErrorState extends StatelessWidget {
  const KumbaErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.lynkVioletSoft,
                shape: BoxShape.circle,
              ),
              child: const LynkAvatar(size: 72, mood: LynkMood.sorry),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              S.auto(message),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              KumbaButton(
                label: S.tr('Réessayer', 'Retry'),
                onPressed: onRetry,
                variant: KumbaButtonVariant.outline,
                isExpanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class KumbaOfflineBanner extends StatelessWidget {
  const KumbaOfflineBanner({super.key, this.pendingCount = 0});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryFixed,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  PhosphorIconsRegular.cloudSlash,
                  size: 15,
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pendingCount > 0
                      ? S.tr(
                          'Hors ligne · $pendingCount en attente',
                          'Offline · $pendingCount pending',
                        )
                      : S.tr('Mode hors ligne', 'Offline mode'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KumbaStatusBadge extends StatelessWidget {
  const KumbaStatusBadge({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
  });

  final String label;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    final bg = backgroundColor ?? c.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
      ),
      child: Text(
        S.auto(label),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
