import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_strings.dart';

/// Barrière de config runtime (audit S8), posée dans `MaterialApp.builder`.
///
/// Rend [child] tel quel tant que la config est en cours / absente / sans
/// restriction (offline-first non bloquant). Interpose un plein écran **non
/// dismissible** uniquement si le serveur impose :
///   * une **maintenance**, ou
///   * une **mise à jour obligatoire** (version installée < minSupportedVersion).
/// Le bouton « Réessayer » invalide le provider pour re-fetch sans redémarrer.
class RuntimeGate extends ConsumerWidget {
  const RuntimeGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(runtimeConfigProvider);
    // En attente / erreur → on n'entrave jamais l'usage (défaut sûr).
    final data = config.valueOrNull;
    if (data == null) return child;

    if (data.maintenance) {
      return _BlockingScreen(
        icon: Icons.engineering_rounded,
        color: AppColors.amber,
        title: S.tr('Maintenance en cours', 'Under maintenance'),
        message: data.announcement?.isNotEmpty == true
            ? data.announcement!
            : S.tr(
                'Lynkstor est temporairement indisponible pour maintenance. '
                'Vos données sont safe et se synchroniseront au retour.',
                'Lynkstor is temporarily down for maintenance. '
                'Your data is safe and will sync on return.',
              ),
        onRetry: () => ref.invalidate(runtimeConfigProvider),
      );
    }

    if (data.updateRequiredFor(AppConfig.version)) {
      return _BlockingScreen(
        icon: Icons.system_update_rounded,
        color: AppColors.error,
        title: S.tr('Mise à jour requise', 'Update required'),
        message: data.updateMessage.isNotEmpty
            ? data.updateMessage
            : S.tr(
                'Cette version (${AppConfig.version}) est obsolète. '
                'Mettez à jour Lynkstor (v${data.minSupportedVersion}+) '
                'pour continuer à vendre en toute sécurité.',
                'This version (${AppConfig.version}) is outdated. '
                'Please update Lynkstor (v${data.minSupportedVersion}+) '
                'to keep selling safely.',
              ),
        onRetry: () => ref.invalidate(runtimeConfigProvider),
      );
    }

    return child;
  }
}

class _BlockingScreen extends StatelessWidget {
  const _BlockingScreen({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 44, color: color),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(S.tr('Réessayer', 'Retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
