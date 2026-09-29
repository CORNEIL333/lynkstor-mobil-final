import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/user_error_message.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../design_system/components/davex_pressable.dart';
import '../../l10n/app_strings.dart';

// ─── Splash recréé depuis la maquette (OnboardingFlow, App.tsx L545–579) ────
//
// Décision d'audit : RECRÉER. L'ancien `splash_screen.dart` (SplashScreen)
// n'est PAS patché : il reste sur disque mais est déréférencé du router.
//
// LOGIQUE RÉUTILISÉE TELLE QUELLE (justification : c'est le boot réel —
// ouverture SQLCipher, démarrage sync, bootstrap session, analytics,
// sauvegarde auto — enlever une seule de ces étapes casserait l'app) :
// séquence `_boot()` identique à l'original, erreur + retry, `session
// .bootstrap()` qui déclenche le redirect GoRouter (le router, pas cet
// écran, décide de la destination : onboarding / lock / accueil).
//
// Mapping maquette → unité par unité :
// - fond dégradé slate-900 → indigo-950 → slate-900 + deux halos colorés ;
// - carte logo blanche arrondie (pop d'entrée) + titre « Lynkstor » + pill
//   « Compagnon de Commerce™ » + sous-titre ;
// - badge vert lumineux « 100 % Fonctionnel Hors Ligne & Cloud Sync »
//   (affirmation VRAIE : l'app est offline-first + sync — même message que
//   l'ancien splash « Offline-first ») ;
// - « Touchez l'écran pour démarrer ».
//
// Écarts maquette↔réel documentés (jamais tranchés en silence) :
// - la maquette enchaîne splash → login après 1,6 s de caméra : ici le
//   splash EST le boot (base + sync + session). Un timer pur cosmétique
//   enverrait vers l'onboarding avant que la session soit lue → faux
//   succès. Le toucher n'est actif qu'UNE FOIS le boot terminé (sinon le
//   redirect router part seul) ;
// - barre d'état iOS dessinée (9:41, wifi, batterie) : chrome du frame
//   démo web, pas une UI d'app → non reproduite (HIG : la vraie status bar
//   système est déjà rendue).

/// Dégradé maquette (`from-slate-900 via-indigo-950 to-slate-900`).
const List<Color> _splashColors = [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)];

class DavexSplashScreen extends ConsumerStatefulWidget {
  const DavexSplashScreen({super.key});

  @override
  ConsumerState<DavexSplashScreen> createState() => _DavexSplashScreenState();
}

class _DavexSplashScreenState extends ConsumerState<DavexSplashScreen> {
  String _status = '…';
  String? _bootError;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Boot après le premier frame pour ne pas muter l'arbre pendant le mount.
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    if (!mounted) return;
    setState(() {
      _status = S.tr('Démarrage…', 'Starting…');
      _bootError = null;
      _ready = false;
    });

    try {
      if (!mounted) return;
      setState(
        () => _status = S.tr(
          'Ouverture de la base…',
          'Opening database…',
        ),
      );
      final db = ref.read(databaseProvider);
      await db.customSelect('SELECT 1').get();

      if (!mounted) return;
      setState(() => _status = S.tr('Sync cloud…', 'Cloud sync…'));
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
        // La sync ne doit jamais bloquer le démarrage.
      }

      if (!mounted) return;
      setState(() => _status = S.tr('Session…', 'Session…'));
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
      // Boot terminé : le router redirige déjà ; le toucher n'est qu'un
      // raccourci cosmétique vers la même destination (jamais un saut
      // avant lecture de session).
      if (!mounted) return;
      setState(() {
        _ready = true;
        _status = S.tr(
          'Touchez l\'écran pour démarrer',
          'Tap the screen to start',
        );
      });
    } catch (error, stack) {
      AppLogger.e('Application bootstrap failed', error, stack);
      if (!mounted) return;
      setState(() {
        _bootError = userFacingErrorMessage(
          error,
          fallback: S.tr(
            'L\'application n\'a pas pu ouvrir ses données locales. Réessayez.',
            'The application could not open its local data. Try again.',
          ),
        );
        _status = S.tr('Erreur — réessayer', 'Error — retry');
      });
    }
  }

  void _onTap() {
    if (_bootError != null) {
      _boot();
      return;
    }
    // Le redirect GoRouter suit la session ; ce tap ne fait que ré-essayer
    // un bootstrap déjà terminé si le frame de transition a été perdu.
    if (_ready) _boot();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: DavexPressable(
        onTap: _onTap,
        semanticLabel: S.tr('Démarrer', 'Start'),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _splashColors,
            ),
          ),
          child: Stack(
            children: [
              // Halos « blur-3xl » de la maquette → dégradés radiaux (pas de
              // BackdropFilter : coût GPU et artefacts en test widget).
              Positioned(
                top: -80,
                left: -80,
                child: _orb(const Color(0x336366F1)),
              ),
              Positioned(
                bottom: -80,
                right: -80,
                child: _orb(const Color(0x33A855F7)),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sésame de langue conservé (RÉUTILISER : FR/EN réel).
                      Align(
                        alignment: Alignment.centerRight,
                        child: _LanguageChip(onChanged: () => setState(() {})),
                      ),
                      const Spacer(),
                      // Carte logo (`.w-28 h-28 rounded-3xl bg-white/95`).
                      Center(
                        child: Container(
                          width: 112,
                          height: 112,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 42,
                                spreadRadius: -6,
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
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppConfig.appName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x336366F1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0x4D818CF8),
                            ),
                          ),
                          child: Text(
                            S.tr(
                              'Compagnon de Commerce™',
                              'Commerce Companion™',
                            ).toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFA5B4FC),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          S.tr(
                            'La gestion simple, prédictive et intelligente de votre boutique.',
                            'Simple, predictive and intelligent management for your shop.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12.5,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Badge offline-first (affirmation vraie du projet).
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF12B76A).withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF12B76A).withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.wifi_off_rounded,
                                size: 14,
                                color: Color(0xFF4ADE80),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                S.tr(
                                  '100 % fonctionnel hors ligne & Cloud Sync',
                                  '100% offline & cloud sync',
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_bootError == null)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _ready
                              ? Text(
                                  _status,
                                  key: const ValueKey('ready'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : Padding(
                                  key: const ValueKey('busy'),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: const Color(
                                        0xFFA5B4FC,
                                      ).withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                        )
                      else
                        Column(
                          children: [
                            Text(
                              _bootError!,
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFFDA4AF),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              S.tr(
                                'Touchez pour réessayer',
                                'Tap to retry',
                              ),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 18),
                      Text(
                        'v${AppConfig.version} · Offline-first',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 10.5,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orb(Color color) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// Sélecteur de langue compact (réutilisé de l'onboarding existant — FR/EN
/// réel via localeControllerProvider).
class _LanguageChip extends ConsumerWidget {
  const _LanguageChip({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: S.tr('Changer la langue', 'Change language'),
      onSelected: (language) {
        ref.read(localeControllerProvider.notifier).setLanguage(language);
        onChanged();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'fr',
          child: Row(
            children: [
              if (!S.isEnglish) const Icon(Icons.check_rounded, size: 18),
              if (!S.isEnglish) const SizedBox(width: 8),
              const Text('Français'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'en',
          child: Row(
            children: [
              if (S.isEnglish) const Icon(Icons.check_rounded, size: 18),
              if (S.isEnglish) const SizedBox(width: 8),
              const Text('English'),
            ],
          ),
        ),
      ],
      child: Semantics(
        button: true,
        label: S.tr('Changer la langue', 'Change language'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.language_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 5),
              Text(
                S.isEnglish ? 'EN' : 'FR',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
