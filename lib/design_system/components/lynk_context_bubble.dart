import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/ai_assistant/lynk_quick_sheet.dart';
import '../motion/lynk_avatar.dart';
import 'kumba_ai_badge.dart';
import 'kumba_pressable.dart';

/// Bulle contextuelle Lynk (anomalie métier).
class LynkContextBubble extends StatelessWidget {
  const LynkContextBubble({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    return Material(
      color: dark ? AppColors.darkCard : Colors.white,
      elevation: 8,
      shadowColor: AppColors.lynkViolet.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            const LynkAvatar(size: 40, mood: LynkMood.alert),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const KumbaAiBadge(compact: true),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 8),
                    KumbaPressable(
                      onTap: onAction ?? () => showLynkQuickSheet(context),
                      child: Text(
                        actionLabel!,
                        style: const TextStyle(
                          color: AppColors.lynkViolet,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
