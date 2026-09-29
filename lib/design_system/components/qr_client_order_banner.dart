import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';

/// QrClientOrderBanner — port de `src/design-system/QrClientOrderBanner.tsx`.
///
/// Alerte NON bloquante sur l'écran Vente : une commande QR client
/// n'interrompt JAMAIS une vente en cours. Auto-dismiss après 8 s, rôle
/// live-region "polite", actions « Voir » et fermer.
class QrClientOrderBanner extends StatefulWidget {
  const QrClientOrderBanner({
    super.key,
    required this.count,
    required this.onSee,
    this.onDismiss,
    this.autoDismissAfter = const Duration(seconds: 8),
  });

  /// Nombre de nouvelles commandes en attente (> 0 pour afficher).
  final int count;
  final VoidCallback onSee;
  final VoidCallback? onDismiss;
  final Duration autoDismissAfter;

  @override
  State<QrClientOrderBanner> createState() => _QrClientOrderBannerState();
}

class _QrClientOrderBannerState extends State<QrClientOrderBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(QrClientOrderBanner old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.count > 0 && widget.autoDismissAfter > Duration.zero) {
      _timer = Timer(widget.autoDismissAfter, _dismiss);
    }
  }

  void _dismiss() {
    _timer?.cancel();
    widget.onDismiss?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 0) return const SizedBox.shrink();
    final p = LkPalette.of(context);
    return Semantics(
      liveRegion: true,
      label:
          'Commande QR client détectée. ${widget.count} nouvelles commandes en attente.',
      child: TweenAnimationBuilder<double>(
        key: ValueKey(widget.count),
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.slow,
        curve: AppMotion.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * -AppSpacing.md),
            child: child,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            0,
          ),
          child: Material(
            color: p.infoBg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.qr_code_scanner, size: 22, color: p.infoFg),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commande QR client détectée',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: p.infoFg,
                          ),
                        ),
                        Text(
                          widget.count == 1
                              ? '1 nouvelle commande en attente'
                              : '${widget.count} nouvelles commandes en attente',
                          style: TextStyle(
                            fontSize: 12,
                            color: p.infoFg.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onSee,
                    style: TextButton.styleFrom(foregroundColor: p.link),
                    child: const Text('Voir'),
                  ),
                  IconButton(
                    onPressed: _dismiss,
                    tooltip: 'Fermer',
                    iconSize: 18,
                    color: p.textSecondary,
                    icon: const Icon(Icons.close),
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
    );
  }
}
