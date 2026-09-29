import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/config/runtime_config.dart';
import '../../core/config/sector_modules.dart';
import '../../core/errors/user_error_message.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../design_system/components/kumba_ambient_background.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../design_system/motion/lynk_avatar.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/business_service.dart';
import '../../shared/services/cloud_registration_service.dart';

/// Onboarding Lynkstor : création du commerce (panel test sans clé)
/// ou activation cloud si [ActivationPolicy.requireAgentActivationCode] est
/// actif (politique pilotée par la config runtime du serveur).
class OnboardingShell extends ConsumerStatefulWidget {
  const OnboardingShell({super.key});

  @override
  ConsumerState<OnboardingShell> createState() => _OnboardingShellState();
}

class _OnboardingShellState extends ConsumerState<OnboardingShell> {
  ProviderSubscription<AsyncValue<RuntimeConfig>>? _configSub;

  /// 0 = accueil, 1 = code, 2 = identité, 3 = secteur, 4 = sécurité
  int _step = 0;
  bool _loading = false;
  String? _error;
  String? _validatedPlan;
  String? _validatedCode;
  String? _validatedExpiresAt;
  bool _showPassword = false;
  bool _showPin = false;

  final _nameCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _neighborhoodCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordConfirmCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  final _activationCodeCtrl = TextEditingController();
  String _sector = 'boutique';

  static const _sectors = {
    'boutique': 'Boutique générale',
    'superette': 'Supérette',
    'grossiste': 'Grossiste',
    'quincaillerie': 'Quincaillerie',
    'imprimerie': 'Imprimerie',
    'salon': 'Salon',
    'ambulant': 'Commerce ambulant',
    'services': 'Services & réparation',
  };

  /// Lus à chaque build : la config runtime arrive en asynchrone après le
  /// premier frame, et un onboarding déjà ouvert se reconstruit dès qu'un
  /// tick du provider `sessionProvider` le recharge (les getters sont alors
  /// ré-évalués avec la valeur serveur).
  bool get _needsActivationCode =>
      ActivationPolicy.requireAgentActivationCode;
  int get _totalSteps => _needsActivationCode ? 4 : 3;
  bool get _isCodeStep => _needsActivationCode && _step == 1;
  bool get _isIdentityStep => _needsActivationCode ? _step == 2 : _step == 1;
  bool get _isSectorStep => _needsActivationCode ? _step == 3 : _step == 2;
  bool get _isSecurityStep => _needsActivationCode ? _step == 4 : _step == 3;

  @override
  void initState() {
    super.initState();
    // La config runtime (politique d'activation) arrive souvent APRES le
    // premier frame. Sans rebuild dédié, un onboarding déjà ouvert reste sur
    // le flux « panel test » jusqu'au prochain redémarrage : on écoute la
    // bascule et on ré-évalue les étapes immédiatement.
    //
    // `listenManual` (et non `ref.listen`) : celui-ci est utilisable hors
    // phase de build, ce que garantit mal l'initState d'un élément monté
    // pendant un Builder. Il demarre le fetch s'il n'a pas encore eu lieu.
    _configSub = ref.listenManual<AsyncValue<RuntimeConfig>>(
      runtimeConfigProvider,
      (_, __) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _configSub?.close();
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _neighborhoodCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    _activationCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _validateCodeAndContinue() async {
    if (_loading) return;
    // Accepte les formats cloud (KMB-XXXXXXXX) et legacy (KMB-XXXX-XXXX),
    // y compris tirets / underscores générés par le backend.
    final code = _activationCodeCtrl.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (code.length < 6) {
      setState(
        () => _error = S.tr(
          'Saisissez le code remis par votre commercial (ex. KMB-AB12CD34).',
          'Enter the code provided by your agent (e.g. KMB-AB12CD34).',
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final cloud = CloudRegistrationService();
    try {
      final v = await cloud.validateCode(code);
      if (!mounted) return;
      setState(() {
        _validatedPlan = v.planName;
        _validatedCode = code;
        _validatedExpiresAt = v.expiresAt;
        _activationCodeCtrl.text = code;
        _step = 2;
        _loading = false;
      });
    } catch (error, stack) {
      AppLogger.e('Activation code validation failed', error, stack);
      if (!mounted) return;
      setState(() {
        _error = userFacingErrorMessage(
          error,
          fallback: S.tr(
            'Impossible de valider le code pour le moment. Vérifiez Internet puis réessayez.',
            'Unable to validate the code right now. Check your connection and try again.',
          ),
        );
        _loading = false;
      });
    } finally {
      cloud.dispose();
    }
  }

  Future<void> _create({bool demo = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(businessServiceProvider);
      if (demo) {
        await service.createBusiness(
          BusinessCreationInput(
            name: 'Boutique Démo Akwa',
            ownerName: 'Marie Essomba',
            phone: '690000000',
            password: 'demo1234',
            pin: '1234',
            city: 'Douala',
            neighborhood: 'Akwa',
            sector: 'boutique',
            isDemo: true,
            modules: SectorModules.forSector('boutique'),
          ),
        );
        final businessId = (await ref
            .read(secureStorageProvider)
            .getCurrentBusinessId())!;
        final userId = await ref.read(secureStorageProvider).getCurrentUserId();
        await ref.read(demoSeederProvider).seed(businessId, userId: userId);
      } else {
        if (_nameCtrl.text.trim().isEmpty ||
            _ownerCtrl.text.trim().isEmpty ||
            _phoneCtrl.text.trim().isEmpty ||
            _passwordCtrl.text.length < 8 ||
            _passwordCtrl.text != _passwordConfirmCtrl.text ||
            _pinCtrl.text.length != 4 ||
            _pinCtrl.text != _pinConfirmCtrl.text) {
          throw Exception(
            S.tr(
              'Vérifiez les informations, le mot de passe (8+ caractères) et la confirmation du PIN.',
              'Check the information, password (8+ characters) and PIN confirmation.',
            ),
          );
        }
        String? code;
        if (_needsActivationCode) {
          code = _activationCodeCtrl.text.trim().toUpperCase();
          if (code.isEmpty || code != _validatedCode) {
            throw Exception(
              S.tr(
                'Le code a été modifié depuis sa validation. Revenez à la première étape pour le vérifier.',
                'The code was changed after validation. Return to the first step to verify it.',
              ),
            );
          }
        }
        await service.createBusiness(
          BusinessCreationInput(
            name: _nameCtrl.text,
            ownerName: _ownerCtrl.text,
            phone: _phoneCtrl.text,
            password: _passwordCtrl.text,
            pin: _pinCtrl.text,
            city: _cityCtrl.text.isEmpty ? null : _cityCtrl.text,
            neighborhood: _neighborhoodCtrl.text.isEmpty
                ? null
                : _neighborhoodCtrl.text,
            sector: _sector,
            modules: SectorModules.forSector(_sector),
            activationCode: code,
          ),
        );
      }
      // Restaure sync cloud si présente (après create cloud)
      final secure = ref.read(secureStorageProvider);
      final endpoint = await secure.getCloudSyncEndpoint();
      final token = await secure.getCloudSyncToken();
      final businessId = await secure.getCurrentBusinessId();
      final deviceId = await secure.getDeviceId();
      if (endpoint != null && token != null) {
        await ref
            .read(syncEngineProvider)
            .start(
              endpoint: endpoint,
              authToken: token,
              businessId: businessId,
              deviceId: deviceId,
            );
      }
      await ref.read(sessionProvider.notifier).refresh();
    } catch (error, stack) {
      AppLogger.e('Business onboarding failed', error, stack);
      if (!mounted) return;
      setState(
        () => _error = userFacingErrorMessage(
          error,
          fallback: S.tr(
            'La création du commerce n’a pas pu être terminée. Vos données restent intactes ; réessayez.',
            'The business could not be created. Your data is safe; please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 0) return _home();
    return _wizard();
  }

  Widget _home() {
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.48)
        .clamp(380.0, 470.0)
        .toDouble();

    return KumbaAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: heroHeight,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppSpacing.radiusXxl),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/onboarding_merchant.webp',
                        fit: BoxFit.cover,
                        alignment: const Alignment(0.08, -0.2),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(color: Color(0xCC0A5CF6)),
                      ),
                      SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusMd,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.78,
                                        ),
                                        width: 1.2,
                                      ),
                                      image: const DecorationImage(
                                        image: AssetImage(
                                          'assets/images/ic_launcher.png',
                                        ),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Text(
                                      S.appName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      iconTheme: const IconThemeData(
                                        color: Colors.white,
                                      ),
                                    ),
                                    child: _languageSelector(dark: true),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                S.tr(
                                  'Votre commerce,\nmaîtrisé au quotidien.',
                                  'Your business,\nunder control every day.',
                                ),
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      height: 1.04,
                                      letterSpacing: -1,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.turquoise,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusCapsule,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 330,
                                ),
                                child: Text(
                                  S.tr(
                                    'Caisse, stock et équipe réunis dans un outil pensé pour les commerces africains.',
                                    'Checkout, stock and team management in one tool designed for African businesses.',
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.88,
                                        ),
                                        height: 1.45,
                                      ),
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
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    S.tr('Commencer', 'Get started'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.tr(
                      'Choisissez la situation qui vous correspond.',
                      'Choose the option that matches your situation.',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _lynkIntro(context),
                  const SizedBox(height: 16),
                  _entryCard(
                    icon: Icons.storefront_rounded,
                    color: AppColors.primary,
                    title: _needsActivationCode
                        ? S.tr('Activer mon commerce', 'Activate my business')
                        : S.tr('Créer mon commerce', 'Create my business'),
                    subtitle: _needsActivationCode
                        ? S.tr(
                            'J’ai reçu un code Lynkstor',
                            'I received a Lynkstor code',
                          )
                        : S.tr(
                            'Inscription libre, sans code agent',
                            'Open signup, no agent code',
                          ),
                    badge: S.tr('Conseillé', 'Suggested'),
                    highlight: true,
                    onTap: () => setState(() {
                      _step = 1;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  _entryCard(
                    icon: Icons.group_add_outlined,
                    color: AppColors.clay,
                    title: S.tr('Rejoindre une équipe', 'Join a team'),
                    subtitle: S.tr(
                      'Utiliser une invitation employé',
                      'Use an employee invitation',
                    ),
                    onTap: () => context.push('/join'),
                  ),
                  const SizedBox(height: 10),
                  _entryCard(
                    icon: Icons.restore_rounded,
                    color: AppColors.sahelGold,
                    title: S.tr('Restaurer une sauvegarde', 'Restore a backup'),
                    subtitle: S.tr(
                      'Récupérer un commerce existant',
                      'Recover an existing business',
                    ),
                    onTap: () => context.push('/restore'),
                  ),
                  if (AppConfig.allowDemoMode) ...[
                    const SizedBox(height: 10),
                    _entryCard(
                      icon: Icons.play_arrow_rounded,
                      color: AppColors.onSurfaceVariant,
                      title: S.tr(
                        'Voir la démonstration',
                        'View the demonstration',
                      ),
                      subtitle: S.tr(
                        'Données fictives, sans activation',
                        'Sample data, no activation',
                      ),
                      onTap: _loading ? null : () => _create(demo: true),
                    ),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 20),
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _errorBox(_error!),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.link_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          S.tr(
                            _needsActivationCode
                                ? 'Le code associe ce téléphone à votre commerce. Vos données restent ensuite disponibles hors ligne.'
                                : 'Créez votre commerce sans clé d’activation. Vos données restent sur cet appareil, disponibles hors ligne.',
                            _needsActivationCode
                                ? 'The code links this phone to your business. Your data then remains available offline.'
                                : 'Create your business without an activation key. Your data stays on this device, available offline.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                height: 1.45,
                              ),
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageSelector({bool dark = false}) {
    return PopupMenuButton<String>(
      tooltip: S.tr('Changer la langue', 'Change language'),
      onSelected: (language) =>
          ref.read(localeControllerProvider.notifier).setLanguage(language),
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
            color: dark
                ? Colors.black.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.34)
                  : AppColors.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.language_rounded,
                size: 18,
                color: dark ? Colors.white : AppColors.primary,
              ),
              const SizedBox(width: 5),
              Text(
                S.isEnglish ? 'EN' : 'FR',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: dark ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lynkIntro(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.creamCard,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.sky.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const LynkAvatar(size: 64, mood: LynkMood.idle),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.tr('Voici Lynk', 'Meet Lynk'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.tr(
                    'Ton assistant local. Il lit tes ventes et ton stock, sans envoyer tes données.',
                    'Your local assistant. It reads sales and stock, without sending your data.',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    String? badge,
    bool highlight = false,
    VoidCallback? onTap,
  }) {
    final card = KumbaCard(
      onTap: onTap,
      floating: false,
      padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
      borderColor: highlight ? AppColors.primary : color.withValues(alpha: 0.2),
      color: highlight
          ? AppColors.primary
          : AppColors.surfaceBright.withValues(alpha: 0.96),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: highlight ? AppColors.turquoise : color,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (highlight ? AppColors.turquoise : color).withValues(
                    alpha: 0.24,
                  ),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: highlight ? Colors.white : null,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (badge != null)
                      Text(
                        badge,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: highlight
                              ? AppColors.sahelSand
                              : AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: highlight
                        ? Colors.white.withValues(alpha: 0.72)
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: highlight
                  ? Colors.white.withValues(alpha: 0.13)
                  : color.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 17,
              color: highlight ? Colors.white : color,
            ),
          ),
        ],
      ),
    );

    return card;
  }

  String _sectorLabel(String sector) {
    switch (sector) {
      case 'superette':
        return S.tr('Supérette', 'Convenience store');
      case 'grossiste':
        return S.tr('Grossiste', 'Wholesaler');
      case 'quincaillerie':
        return S.tr('Quincaillerie', 'Hardware store');
      case 'imprimerie':
        return S.tr('Imprimerie', 'Print shop');
      case 'salon':
        return S.tr('Salon', 'Salon');
      case 'ambulant':
        return S.tr('Commerce ambulant', 'Mobile business');
      case 'services':
        return S.tr('Services et réparation', 'Services and repair');
      case 'boutique':
      default:
        return S.tr('Boutique générale', 'General store');
    }
  }

  IconData _sectorIcon(String sector) {
    switch (sector) {
      case 'superette':
        return Icons.local_grocery_store_outlined;
      case 'grossiste':
        return Icons.warehouse_outlined;
      case 'quincaillerie':
        return Icons.handyman_outlined;
      case 'imprimerie':
        return Icons.print_outlined;
      case 'salon':
        return Icons.content_cut_rounded;
      case 'ambulant':
        return Icons.store_mall_directory_outlined;
      case 'services':
        return Icons.build_outlined;
      case 'boutique':
      default:
        return Icons.storefront_outlined;
    }
  }

  String? _securityValidationError() {
    if (_passwordCtrl.text.length < 8) {
      return S.tr(
        'Le mot de passe doit contenir au moins 8 caractères.',
        'The password must contain at least 8 characters.',
      );
    }
    if (_passwordCtrl.text != _passwordConfirmCtrl.text) {
      return S.tr(
        'Les mots de passe ne correspondent pas.',
        'Passwords do not match.',
      );
    }
    if (_pinCtrl.text.length != 4) {
      return S.tr(
        'Le PIN doit contenir exactement 4 chiffres.',
        'The PIN must contain exactly 4 digits.',
      );
    }
    if (_pinCtrl.text != _pinConfirmCtrl.text) {
      return S.tr('Les PIN ne correspondent pas.', 'PINs do not match.');
    }
    return null;
  }

  Widget _wizard() {
    final titles = <int, String>{
      1: _needsActivationCode
          ? S.tr('Activation', 'Activation')
          : S.tr('Votre commerce', 'Your business'),
      2: _needsActivationCode
          ? S.tr('Votre commerce', 'Your business')
          : S.tr('Secteur d’activité', 'Business sector'),
      3: _needsActivationCode
          ? S.tr('Secteur d’activité', 'Business sector')
          : S.tr('Sécurité', 'Security'),
      if (_needsActivationCode) 4: S.tr('Sécurité', 'Security'),
    };

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _loading
              ? null
              : () {
                  if (_step <= 1) {
                    setState(() {
                      _step = 0;
                      _error = null;
                    });
                  } else {
                    setState(() {
                      _step--;
                      _error = null;
                    });
                  }
                },
        ),
        title: Text(S.tr('Configuration du commerce', 'Business setup')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Container(
              height: 126,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                image: DecorationImage(
                  image: AssetImage(
                    _isSecurityStep
                        ? 'assets/images/lock_ledger.webp'
                        : 'assets/images/onboarding_merchant.webp',
                  ),
                  fit: BoxFit.cover,
                  alignment: _isSecurityStep
                      ? const Alignment(0, 0.48)
                      : const Alignment(0, -0.12),
                ),
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xF00A5CF6)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusCapsule,
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${S.tr('Étape', 'Step')} $_step / $_totalSteps',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: Colors.white, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        titles[_step]!,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              label: S.tr(
                'Étape $_step sur $_totalSteps',
                'Step $_step of $_totalSteps',
              ),
              value: '${(_step / _totalSteps * 100).round()}%',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _step / _totalSteps,
                  minHeight: 4,
                  backgroundColor: AppColors.surfaceContainer,
                  color: AppColors.fab,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_isCodeStep) ...[
              Text(
                S.tr('Activez cet appareil', 'Activate this device'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.headerStart,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                S.tr(
                  'Saisissez le code Lynkstor reçu avec votre forfait. Une connexion Internet est nécessaire pour le vérifier.',
                  'Enter the Lynkstor code provided with your plan. An internet connection is required to verify it.',
                ),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              KumbaTextField(
                controller: _activationCodeCtrl,
                label: S.tr('Code d’activation', 'Activation code'),
                hint: 'Ex. KMB-AB12CD34',
                prefixIcon: Icons.key_rounded,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_validatedCode == null) return;
                  setState(() {
                    _validatedCode = null;
                    _validatedPlan = null;
                    _validatedExpiresAt = null;
                  });
                },
                inputFormatters: [
                  // Lettres, chiffres, tiret (-) et underscore (_) :
                  // les clés déployées sont du type KMB-XXXXXXXX.
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-_]')),
                  LengthLimitingTextInputFormatter(32),
                  _UpperCaseFormatter(),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        S.tr(
                          'Le code est vérifié maintenant, mais il n’est utilisé définitivement qu’à la création du commerce.',
                          'The code is checked now, but is only permanently used when the business is created.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_isIdentityStep) ...[
              if (_validatedPlan != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.forestSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: AppColors.emerald.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: AppColors.emerald,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          S.tr(
                            'Code vérifié · forfait $_validatedPlan'
                                '${_validatedExpiresAt == null ? '' : ' · expire le $_validatedExpiresAt'}',
                            'Code verified · $_validatedPlan plan'
                                '${_validatedExpiresAt == null ? '' : ' · expires $_validatedExpiresAt'}',
                          ),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppColors.emerald,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                S.tr('Présentez votre commerce', 'Tell us about your business'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _nameCtrl,
                label: 'Nom commercial',
                hint: 'Ex. Boutique Chez Marie',
                prefixIcon: Icons.storefront_outlined,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _ownerCtrl,
                label: 'Nom du propriétaire',
                prefixIcon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _phoneCtrl,
                label: 'Téléphone',
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                hint: '6XX XXX XXX',
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s()-]')),
                  LengthLimitingTextInputFormatter(24),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _cityCtrl,
                label: 'Ville',
                hint: 'Douala, Yaoundé, Abidjan…',
                prefixIcon: Icons.location_city_outlined,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _neighborhoodCtrl,
                label: 'Quartier',
                prefixIcon: Icons.place_outlined,
                textCapitalization: TextCapitalization.words,
              ),
            ] else if (_isSectorStep) ...[
              Text(
                S.tr(
                  'Choisissez votre activité',
                  'Choose your business activity',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                S.tr(
                  'Nous activerons les outils utiles à votre métier et proposerons plus de 1000 produits déjà enregistrés, à activer selon ce que vous vendez.',
                  'We will enable the tools suited to your business and offer more than 1,000 registered products to activate according to what you sell.',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ..._sectors.entries.map((e) {
                final selected = _sector == e.key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: ListTile(
                    selected: selected,
                    selectedTileColor: AppColors.kpiCollectBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      side: BorderSide(
                        color: selected
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                      ),
                    ),
                    leading: Icon(
                      _sectorIcon(e.key),
                      color: selected
                          ? AppColors.primary
                          : AppColors.onSurfaceVariant,
                    ),
                    title: Text(_sectorLabel(e.key)),
                    subtitle: Text(
                      S.tr(
                        '${SectorModules.forSector(e.key).length} modules inclus',
                        '${SectorModules.forSector(e.key).length} modules included',
                      ),
                    ),
                    trailing: selected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                    onTap: () => setState(() => _sector = e.key),
                  ),
                );
              }),
            ] else ...[
              Text(
                S.tr('Protégez votre accès', 'Protect your access'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                S.tr(
                  'Le PIN sert à ouvrir rapidement l’application. Le mot de passe protège les opérations sensibles et les transferts.',
                  'The PIN quickly unlocks the app. The password protects sensitive operations and transfers.',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _passwordCtrl,
                label: 'Mot de passe',
                obscureText: !_showPassword,
                hint: S.tr('Au moins 8 caractères', 'At least 8 characters'),
                prefixIcon: Icons.lock_outline_rounded,
                suffixIcon: _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                onSuffixTap: () =>
                    setState(() => _showPassword = !_showPassword),
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _passwordConfirmCtrl,
                label: S.tr('Confirmer le mot de passe', 'Confirm password'),
                obscureText: !_showPassword,
                prefixIcon: Icons.lock_reset_rounded,
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _pinCtrl,
                label: 'PIN (4 chiffres)',
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: !_showPin,
                prefixIcon: Icons.pin_outlined,
                suffixIcon: _showPin
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                onSuffixTap: () => setState(() => _showPin = !_showPin),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              KumbaTextField(
                controller: _pinConfirmCtrl,
                label: S.tr('Confirmer le PIN', 'Confirm PIN'),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: !_showPin,
                prefixIcon: Icons.pin_outlined,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                S.tr(
                  _needsActivationCode
                      ? 'La dernière étape active le forfait et enregistre ce téléphone. Vous pourrez ensuite travailler hors ligne.'
                      : 'La dernière étape enregistre ce téléphone. Vous pourrez ensuite travailler hors ligne.',
                  _needsActivationCode
                      ? 'The final step activates the plan and registers this phone. You can then work offline.'
                      : 'The final step registers this phone. You can then work offline.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              _errorBox(_error!),
            ],
            const SizedBox(height: AppSpacing.xxl),
            KumbaButton(
              label: _isCodeStep
                  ? S.tr('Vérifier le code', 'Verify code')
                  : !_isSecurityStep
                  ? S.continueLabel
                  : _needsActivationCode
                  ? S.tr(
                      'Activer et créer le commerce',
                      'Activate and create business',
                    )
                  : S.tr('Créer le commerce', 'Create the business'),
              isLoading: _loading,
              onPressed: _loading
                  ? null
                  : () {
                      if (_isCodeStep) {
                        _validateCodeAndContinue();
                      } else if (!_isSecurityStep) {
                        if (_isIdentityStep) {
                          if (_nameCtrl.text.trim().isEmpty ||
                              _ownerCtrl.text.trim().isEmpty ||
                              _phoneCtrl.text.trim().isEmpty) {
                            setState(
                              () => _error = S.tr(
                                'Nom du commerce, propriétaire et téléphone sont requis.',
                                'Business name, owner and phone are required.',
                              ),
                            );
                            return;
                          }
                        }
                        setState(() {
                          _error = null;
                          _step++;
                        });
                      } else {
                        final error = _securityValidationError();
                        if (error != null) {
                          setState(() => _error = error);
                          return;
                        }
                        _create();
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.error, fontSize: 13),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
