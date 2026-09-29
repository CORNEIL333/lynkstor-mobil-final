import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'core/config/app_config.dart';
import 'core/config/runtime_config.dart';
import 'core/l10n/locale_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'l10n/app_strings.dart';
import 'shared/services/analytics_service.dart';
import 'shared/widgets/runtime_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final performanceMode = prefs.getBool('performance_mode') ?? false;
  // Initialise la langue avant le premier frame
  S.currentLanguage = prefs.getString('app_language') == 'en' ? 'en' : 'fr';

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: KumbaApp(performanceMode: performanceMode),
    ),
  );
}

class KumbaApp extends ConsumerStatefulWidget {
  const KumbaApp({super.key, this.performanceMode = false});

  final bool performanceMode;

  @override
  ConsumerState<KumbaApp> createState() => _KumbaAppState();
}

class _KumbaAppState extends ConsumerState<KumbaApp>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // S1 : la politique d'activation vient du SERVEUR (activable à distance,
    // sans rebuild). Le cache synchrone garde UI et verrou de vente alignés.
    // listenManual : requis hors du build (ref.listen dans initState lève une
    // assertion en debug). Comportement identique en release.
    ref.listenManual<AsyncValue<RuntimeConfig>>(runtimeConfigProvider, (_, next) {
      ActivationPolicy.sync(next.valueOrNull?.requireAgentActivationCode);
    });
    ActivationPolicy.sync(
      ref.read(runtimeConfigProvider).valueOrNull?.requireAgentActivationCode,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausedAt = DateTime.now();
      AppAnalytics.track('app.background');
      unawaited(ref.read(analyticsServiceProvider).flush());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(analyticsServiceProvider).flush());
      final paused = _pausedAt;
      _pausedAt = null;
      if (paused == null) return;
      final elapsed = DateTime.now().difference(paused);
      if (elapsed >= AppConfig.lockAfterBackground) {
        final session = ref.read(sessionProvider);
        if (session.isAuthenticated && !session.needsOnboarding) {
          ref.read(sessionProvider.notifier).lock();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Uniquement ce qui doit reconstruire MaterialApp.
    // NE PAS watch(sessionProvider) entier : chaque tick session (abonnement,
    // lock, bootstrap) recréait Theme + Localizations et cassait les
    // dépendances Element (assertion ancestor == this).
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final sessionPerf = ref.watch(
      sessionProvider.select((s) => s.performanceMode),
    );
    final perf = sessionPerf || widget.performanceMode;

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(performanceMode: perf),
      darkTheme: AppTheme.dark(performanceMode: perf),
      themeMode: themeMode,
      routerConfig: router,
      locale: locale,
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) =>
          RuntimeGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
