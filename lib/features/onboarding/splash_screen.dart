import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/user_error_message.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_strings.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String _status = '…';
  String? _bootError;

  @override
  void initState() {
    super.initState();
    // Boot après le premier frame pour ne pas muter l’arbre pendant le mount.
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    if (!mounted) return;
    setState(() {
      _status = S.currentLanguage == 'en' ? 'Starting…' : 'Démarrage…';
      _bootError = null;
    });

    try {
      if (!mounted) return;
      setState(() {
        _status = S.currentLanguage == 'en'
            ? 'Opening database…'
            : 'Ouverture de la base…';
      });
      final db = ref.read(databaseProvider);
      await db.customSelect('SELECT 1').get();

      if (!mounted) return;
      setState(() {
        _status = S.currentLanguage == 'en' ? 'Cloud sync…' : 'Sync cloud…';
      });
      final sync = ref.read(syncEngineProvider);
      final secure = ref.read(secureStorageProvider);
      final endpoint = await secure.getCloudSyncEndpoint();
      final token = await secure.getCloudSyncToken();
      final businessId = await secure.getCurrentBusinessId();
      final deviceId = await secure.getDeviceId();
      try {
        await sync.start(
          endpoint: (endpoint != null && endpoint.isNotEmpty) ? endpoint : null,
          authToken: (token != null && token.isNotEmpty) ? token : null,
          businessId: businessId,
          deviceId: deviceId,
        );
      } catch (_) {
        // La sync ne doit jamais bloquer le démarrage
      }

      if (!mounted) return;
      setState(() {
        _status = S.currentLanguage == 'en' ? 'Session…' : 'Session…';
      });
      // bootstrap → redirect GoRouter (frame suivante). Ne plus setState après.
      await ref.read(sessionProvider.notifier).bootstrap();
      final analytics = ref.read(analyticsServiceProvider);
      unawaited(analytics.track('app.opened'));
      unawaited(analytics.captureSnapshot().then((_) => analytics.flush()));
      final activeBusiness = ref.read(sessionProvider).business;
      if (activeBusiness != null && !activeBusiness.isDemo) {
        unawaited(
          ref
              .read(backupServiceProvider)
              .createAutomaticBackupIfDue(businessId: activeBusiness.id)
              .catchError((Object error, StackTrace stack) {
                AppLogger.w('Automatic backup deferred', error, stack);
                return null;
              }),
        );
      }
    } catch (error, stack) {
      AppLogger.e('Application bootstrap failed', error, stack);
      if (!mounted) return;
      setState(() {
        _bootError = userFacingErrorMessage(
          error,
          fallback: S.currentLanguage == 'en'
              ? 'The application could not open its local data. Try again.'
              : 'L’application n’a pas pu ouvrir ses données locales. Réessayez.',
        );
        _status = S.currentLanguage == 'en'
            ? 'Error — retry'
            : 'Erreur — réessayer';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Aucune animation flutter_animate ici : le splash est démonté dès la
    // fin du bootstrap ; animer pendant le redirect casse l’arbre d’Elements.
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/onboarding_merchant.webp',
            fit: BoxFit.cover,
            alignment: const Alignment(0.08, -0.12),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xF00A5CF6)),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusXl,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                            spreadRadius: -8,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/ic_launcher.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.storefront_rounded,
                          size: 52,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      AppConfig.appName,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.tagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    if (_bootError == null)
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.sahelSand.withValues(alpha: 0.95),
                        ),
                      )
                    else
                      KumbaRetryButton(onRetry: _boot),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    if (_bootError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _bootError!,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'v${AppConfig.version} · Offline-first',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.35),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KumbaRetryButton extends StatelessWidget {
  const KumbaRetryButton({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh, color: AppColors.turquoise),
      label: Text(
        S.retry,
        style: const TextStyle(
          color: AppColors.turquoise,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
