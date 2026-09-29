import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';

/// Dialogues, feuilles et toasts — port de `Dialog`/`Sheet`/toasts du
/// prototype (`primitives.tsx`, `components.css`).
///
/// - Dialog : focus initial, fermeture Escape/back, clic hors zone, radius xl 20.
/// - Sheet  : alignée bas d'écran, largeur max 580 (`.lk-sheet > *`).
/// - Toast  : apparaît EN HAUT, non bloquant, auto-dismiss — jamais un modal
///   pour une confirmation (design-system.md : ne jamais interrompre une tâche).

Future<R?> showLkDialog<R>({
  required BuildContext context,
  required Widget title,
  Widget? content,
  List<Widget> actions = const [],
  bool dismissible = true,
}) {
  return showGeneralDialog<R>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: LkPalette.of(context).overlay,
    transitionDuration: AppMotion.normal,
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(
          CurvedAnimation(parent: animation, curve: AppMotion.easeOut),
        ),
        child: child,
      ),
    ),
    pageBuilder: (dialogContext, _, __) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Material(
            color: LkPalette.of(dialogContext).surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle(
                    style:
                        Theme.of(
                          dialogContext,
                        ).textTheme.headlineSmall!,
                    child: title,
                  ),
                  if (content != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Flexible(child: content),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final (i, action) in actions.indexed) ...[
                          if (i > 0) const SizedBox(width: AppSpacing.sm),
                          action,
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Sheet bottom-aligned (`.lk-sheet`) — max 580 de large, poignée, back-safe.
Future<R?> showLkSheet<R>({
  required BuildContext context,
  required Widget child,
  bool dismissible = true,
}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    barrierColor: LkPalette.of(context).overlay,
    backgroundColor: LkPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
    ),
    useSafeArea: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: child,
      ),
    ),
  );
}

// ——— Toasts unifiés (haut, non bloquants) ———

enum LkToastTone { neutral, success, warning, danger, info }

/// Affiche un toast EN HAUT de l'écran via l'Overlay : jamais il ne masque la
/// caisse ni n'intercepte les gestes (IgnorePointer sur le fond, le bandeau
/// lui-même est touchable pour « Annuler »). Auto-dismiss après [duration].
void showLkToast(
  BuildContext context,
  String message, {
  LkToastTone tone = LkToastTone.neutral,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 3200),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final p = LkPalette.of(context);
  final (Color bg, Color fg) = switch (tone) {
    LkToastTone.neutral => (p.text, p.canvas),
    LkToastTone.success => (p.successBg, p.successFg),
    LkToastTone.warning => (p.warningBg, p.warningFg),
    LkToastTone.danger => (p.dangerBg, p.dangerFg),
    LkToastTone.info => (p.infoBg, p.infoFg),
  };

  late final OverlayEntry entry;
  Timer? timer;
  entry = OverlayEntry(
    builder: (toastContext) => _LkToastView(
      background: bg,
      foreground: fg,
      icon: icon,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              timer?.cancel();
              entry.remove();
              onAction();
            },
      onDismiss: () {
        timer?.cancel();
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
  timer = Timer(duration, () {
    if (entry.mounted) entry.remove();
  });
}

class _LkToastView extends StatelessWidget {
  const _LkToastView({
    required this.background,
    required this.foreground,
    required this.message,
    required this.onDismiss,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final Color background;
  final Color foreground;
  final String message;
  final VoidCallback onDismiss;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // Non bloquant : le reste de l'écran reçoit les gestes normalement.
      child: SafeArea(
        bottom: false,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.normal,
          curve: AppMotion.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * -AppSpacing.lg),
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  boxShadow: AppColors.cardShadow(dark: true),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        label: message,
                        child: Text(
                          message,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    if (actionLabel != null && onAction != null)
                      TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(foregroundColor: foreground),
                        child: Text(actionLabel!),
                      ),
                    IconButton(
                      onPressed: onDismiss,
                      tooltip: 'Fermer',
                      icon: Icon(Icons.close, size: 18, color: foreground),
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retour haptique léger de confirmation — design-system.md §6.
void confirmHaptic() => HapticFeedback.mediumImpact();
