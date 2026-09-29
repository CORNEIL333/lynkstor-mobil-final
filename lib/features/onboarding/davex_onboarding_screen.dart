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
import '../../design_system/components/davex_pressable.dart';
import '../../design_system/motion/lynk_avatar.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/business_service.dart';
import '../../shared/services/cloud_registration_service.dart';

// ─── Onboarding recréé depuis la maquette (OnboardingFlow, App.tsx L466–837) ─
//
// Décision d'audit : RECRÉER. L'ancien `onboarding_shell.dart`
// (OnboardingShell) n'est PAS patché : il reste sur disque mais est
// déréférencé du router.
//
// LOGIQUE RÉUTILISÉE TELLE QUELLE (justification : c'est le contrat réel de
// création d'un commerce — pas de substitut possible) :
// - politique d'activation pilotée par la config runtime
//   (`ActivationPolicy.requireAgentActivationCode` + `listenManual` qui
//   re-construit la wizard quand la config serveur arrive) ;
// - validation du code via `CloudRegistrationService.validateCode`
//   (normalisation KMB-XXXXXXXX, plan + expiration affichés) ;
// - `BusinessCreationInput` complet via `businessServiceProvider`
//   (mot de passe ≥ 8 + PIN 4 chiffres : indispensables à la dérivation de
//   clé SQLCipher et à l'écran de verrouillage) ;
// - mode démo (`Boutique Démo Akwa` + `demoSeederProvider`), entrées
//   « Rejoindre une équipe » (/join) et « Restaurer une sauvegarde »
//   (/restore), restauration de la sync cloud post-création, refresh
//   session → le router redirige ;
// - toutes les validations et messages d'erreur (`userFacingErrorMessage`).
//
// Mapping maquette → unité par unité :
// - fond slate-50 (#F8FAFC), titres 20 px w800 slate-900, descriptions
//   12 px slate-500 ;
// - en-tête d'étape : bouton retour carré blanc bordé (36 × 36, radius 16,
//   chevron) + pill « Étape X sur Y » indigo (fond #EEF2FF, bordure
//   #E0E7FF, texte #4F46E5) ;
// - champs = cartes blanches rounded-2xl avec icône leading indigo, label
//   12 px bold + astérisque rose pour le requis, focus border indigo ;
// - CTA dégradé indigo → purple (#4F46E5 → #9333EA), rounded-2xl, halo
//   lumineux, flèche à droite, opacité réduite quand désactivé ;
// - secteur : grille 3 colonnes de cartes bordées 2 px, sélectionnée =
//   bordure indigo + fond indigo-50 + léger scale ;
// - bannière émeraude « catalogue » sous la grille ;
// - bannière erreur rose-50 / rouge.
//
// Écarts maquette↔réel documentés (jamais tranchés en silence) :
// - « Connexion par téléphone seul, aucun mot de passe » (écran 2 de la
//   maquette) NON FABRIQUÉ : le mot de passe et le PIN sont requis par
//   l'architecture (clé SQLCipher, lock screen). La première étape réelle
//   est le code d'activation (si politique serveur) ou l'identité du
//   commerce ;
// - « Étape 1 sur 3 » fixe → compteur dynamique X/Y : le nombre d'étapes
//   dépend de la politique d'activation runtime (3 ou 4) ;
// - checklist « Catégories initiales » (écran 5) : aucun modèle de
//   persistance pour un choix de catégories dans `BusinessCreationInput` →
//   RECRÉÉE en résumé informatif réel : les modules métier activés par le
//   secteur (`SectorModules.forSector`) listés en pastilles lecture seule.
//   Cocher/décocher serait un faux succès (rien ne serait enregistré) ;
// - `CatalogueSelector` (écran 6 de la maquette) : existe déjà en réel
//   (`/products/catalog`, secteur) → reste accessible APRÈS l'onboarding,
//   non fusionné dans la wizard (zéro régression) ; bannière émeraude
//   conservée (le texte réel « plus de 1000 produits déjà enregistrés »
//   est vrai : catalogue secteurs embarqué) ;
// - emojis du secteur (🛒💇…) → icônes Material (même décision que les
//   autres écrans : cohérence design system, rendu fiable hors web) ;
// - 9 secteurs dans la maquette → 8 secteurs réels supportés par
//   `SectorModules` ;
// - frame téléphone + status bar 9:41 : chrome de démo web, non reproduit ;
// - l'accueil réel (bienvenue + 4 entrées) n'a pas d'équivalent maquette →
//   restylé dans le langage visuel de la maquette, logique inchangée.

// ─── Palette maquette (constantes locales, hors LkPalette : thème indigo
// specific à l'onboarding, éphémère par nature) ──────────────────────────────
const Color _bg = Color(0xFFF8FAFC); // slate-50
const Color _ink = Color(0xFF0F172A); // slate-900
const Color _inkSoft = Color(0xFF334155); // slate-700
const Color _muted = Color(0xFF64748B); // slate-500
const Color _faint = Color(0xFF94A3B8); // slate-400
const Color _line = Color(0xFFE2E8F0); // slate-200
const Color _indigo = Color(0xFF4F46E5); // indigo-600
const Color _indigoDeep = Color(0xFF4338CA); // indigo-700
const Color _indigoSoft = Color(0xFFEEF2FF); // indigo-50
const Color _indigoLine = Color(0xFFE0E7FF); // indigo-100
const Color _purple = Color(0xFF9333EA); // purple-600
const Color _purpleSoft = Color(0xFFF5F3FF); // purple-50
const Color _rose = Color(0xFFF43F5E); // rose-500 (astérisque requis)
const Color _errBg = Color(0xFFFEF2F2); // red-50
const Color _errLine = Color(0xFFFECACA); // red-200
const Color _errFg = Color(0xFFB91C1C); // red-700
const Color _okBg = Color(0xFFECFDF5); // emerald-50
const Color _okLine = Color(0xFFA7F3D0); // emerald-200
const Color _okFg = Color(0xFF047857); // emerald-700
const Color _amberFg = Color(0xFFB45309); // amber-700

const LinearGradient _ctaGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [_indigo, _purple],
);

/// Libellés FR des modules métier réels (`SectorModules`) — pure affichage,
/// jamais une source de vérité (les codes restent la clé).
String _moduleLabel(String module) {
  switch (module) {
    case 'pos':
      return S.tr('Caisse', 'POS');
    case 'stock':
      return S.tr('Stock', 'Stock');
    case 'clients':
      return S.tr('Clients', 'Customers');
    case 'dettes':
      return S.tr('Dettes', 'Debts');
    case 'depenses':
      return S.tr('Dépenses', 'Expenses');
    case 'fournisseurs':
      return S.tr('Fournisseurs', 'Suppliers');
    case 'achats':
      return S.tr('Achats', 'Purchases');
    case 'inventaire':
      return S.tr('Inventaires', 'Inventory');
    case 'devis':
      return S.tr('Devis', 'Quotes');
    case 'commandes':
      return S.tr('Commandes', 'Orders');
    case 'factures':
      return S.tr('Factures', 'Invoices');
    case 'livraisons':
      return S.tr('Livraisons', 'Deliveries');
    case 'employes':
      return S.tr('Employés', 'Employees');
    case 'pointage':
      return S.tr('Pointage', 'Attendance');
    case 'rapports':
      return S.tr('Rapports', 'Reports');
    case 'sauvegardes':
      return S.tr('Sauvegardes', 'Backups');
    case 'ia':
      return S.tr('Assistant IA', 'AI assistant');
    default:
      return module;
  }
}

/// Onboarding Lynkstor aux couleurs de la maquette : création du commerce
/// (panel test sans clé) ou activation cloud si
/// [ActivationPolicy.requireAgentActivationCode] est actif (politique
/// pilotée par la config runtime du serveur). Toute la logique métier est
/// identique à l'ancien `OnboardingShell`.
class DavexOnboardingScreen extends ConsumerStatefulWidget {
  const DavexOnboardingScreen({super.key});

  @override
  ConsumerState<DavexOnboardingScreen> createState() =>
      _DavexOnboardingScreenState();
}

class _DavexOnboardingScreenState extends ConsumerState<DavexOnboardingScreen> {
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
  bool get _needsActivationCode => ActivationPolicy.requireAgentActivationCode;
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
    // pendant un Builder. Il démare le fetch s'il n'a pas encore eu lieu.
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

  // ─── Accueil (étape 0) — restylé maquette, entrées réelles inchangées ────
  Widget _home() {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _indigoSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _indigoLine),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/ic_launcher.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.storefront_rounded,
                      color: _indigo,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    S.appName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const _DavexLangChip(),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              S.tr(
                'Votre commerce,\nmaîtrisé au quotidien.',
                'Your business,\nunder control every day.',
              ),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _ink,
                height: 1.08,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                gradient: _ctaGradient,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              S.tr(
                'Caisse, stock et équipe réunis dans un outil pensé pour les commerces africains.',
                'Checkout, stock and team management in one tool designed for African businesses.',
              ),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            _lynkIntro(context),
            const SizedBox(height: 18),
            Text(
              S.tr('Commencer', 'Get started'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              S.tr(
                'Choisissez la situation qui vous correspond.',
                'Choose the option that matches your situation.',
              ),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _muted),
            ),
            const SizedBox(height: 14),
            _entryCard(
              icon: Icons.storefront_rounded,
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
              iconColor: _purple,
              iconBg: _purpleSoft,
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
              iconColor: _amberFg,
              iconBg: const Color(0xFFFFFBEB),
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
                iconColor: _muted,
                iconBg: const Color(0xFFF1F5F9),
                title: S.tr('Voir la démonstration', 'View the demonstration'),
                subtitle: S.tr(
                  'Données fictives, sans activation',
                  'Sample data, no activation',
                ),
                onTap: _loading ? null : () => _create(demo: true),
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 22),
              const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: _indigo,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.link_rounded,
                  color: _indigo,
                  size: 19,
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lynkIntro(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _indigoLine),
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.tr(
                    'Ton assistant local. Il lit tes ventes et ton stock, sans envoyer tes données.',
                    'Your local assistant. It reads sales and stock, without sending your data.',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                    height: 1.35,
                  ),
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
    required String title,
    required String subtitle,
    Color iconColor = _indigo,
    Color iconBg = _indigoSoft,
    String? badge,
    bool highlight = false,
    VoidCallback? onTap,
  }) {
    return DavexPressable(
      onTap: onTap,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlight ? _indigo : _line,
            width: highlight ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: highlight
                  ? _indigo.withValues(alpha: 0.14)
                  : const Color(0x0F0F172A),
              blurRadius: highlight ? 22 : 10,
              offset: const Offset(0, 8),
              spreadRadius: highlight ? -4 : -4,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: highlight ? _ctaGradient : null,
                color: highlight ? null : iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: highlight ? Colors.white : iconColor, size: 23),
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
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _indigoSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _indigoLine),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _indigo,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: highlight ? _indigoSoft : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: highlight ? _indigo : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Wizard (étapes 1..N) — visuels maquette, validations réelles ────────
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

  String get _stepTitle {
    if (_isCodeStep) return S.tr('Activez cet appareil', 'Activate this device');
    if (_isIdentityStep) {
      return S.tr('Présentez votre commerce', 'Tell us about your business');
    }
    if (_isSectorStep) {
      return S.tr('Votre secteur d’activité', 'Your business sector');
    }
    return S.tr('Protégez votre accès', 'Protect your access');
  }

  Widget _wizard() {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                DavexPressable(
                  semanticLabel: S.tr('Retour', 'Back'),
                  onTap: _loading
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
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _line),
                    ),
                    child: const Icon(
                      Icons.chevron_left_rounded,
                      size: 18,
                      color: _inkSoft,
                    ),
                  ),
                ),
                Semantics(
                  label: S.tr(
                    'Étape $_step sur $_totalSteps',
                    'Step $_step of $_totalSteps',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _indigoSoft,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _indigoLine),
                    ),
                    child: Text(
                      S.tr(
                        'Étape $_step sur $_totalSteps',
                        'Step $_step of $_totalSteps',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _indigo,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              _stepTitle,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _stepDescription,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            if (_isCodeStep) ..._codeStep() else if (_isIdentityStep) ..._identityStep() else if (_isSectorStep) ..._sectorStep() else ..._securityStep(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 28),
            _GradientCta(
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
              busy: _loading,
              onTap: _loading
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

  String get _stepDescription {
    if (_isCodeStep) {
      return S.tr(
        'Saisissez le code Lynkstor reçu avec votre forfait. Une connexion Internet est nécessaire pour le vérifier.',
        'Enter the Lynkstor code provided with your plan. An internet connection is required to verify it.',
      );
    }
    if (_isIdentityStep) {
      return S.tr(
        'Indiquez le nom, le propriétaire et la ville de votre commerce.',
        'Provide the name, owner and city of your business.',
      );
    }
    if (_isSectorStep) {
      return S.tr(
        'Nous activerons les outils utiles à votre métier et proposerons plus de 1000 produits déjà enregistrés, à activer selon ce que vous vendez.',
        'We will enable the tools suited to your business and offer more than 1,000 registered products to activate according to what you sell.',
      );
    }
    return S.tr(
      'Le PIN sert à ouvrir rapidement l’application. Le mot de passe protège les opérations sensibles et les transferts.',
      'The PIN quickly unlocks the app. The password protects sensitive operations and transfers.',
    );
  }

  List<Widget> _codeStep() {
    return [
      _DavexField(
        label: S.tr('Code d’activation', 'Activation code'),
        controller: _activationCodeCtrl,
        hint: 'Ex. KMB-AB12CD34',
        icon: Icons.key_rounded,
        required: true,
        capitalization: TextCapitalization.characters,
        onChanged: (_) {
          if (_validatedCode == null) return;
          setState(() {
            _validatedCode = null;
            _validatedPlan = null;
            _validatedExpiresAt = null;
          });
        },
        formatters: [
          // Lettres, chiffres, tiret (-) et underscore (_) :
          // les clés déployées sont du type KMB-XXXXXXXX.
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-_]')),
          LengthLimitingTextInputFormatter(32),
          _UpperCaseFormatter(),
        ],
      ),
      const SizedBox(height: 16),
      _Banner(
        icon: Icons.badge_outlined,
        background: _indigoSoft,
        borderColor: _indigoLine,
        iconColor: Colors.white,
        iconBackground: _indigo,
        title: S.tr(
          'Vérification immédiate, activation à la fin',
          'Checked now, activated at the end',
        ),
        message: S.tr(
          'Le code est vérifié maintenant, mais il n’est utilisé définitivement qu’à la création du commerce.',
          'The code is checked now, but is only permanently used when the business is created.',
        ),
      ),
    ];
  }

  List<Widget> _identityStep() {
    return [
      if (_validatedPlan != null) ...[
        _Banner(
          icon: Icons.verified_rounded,
          background: _okBg,
          borderColor: _okLine,
          iconColor: _okFg,
          iconBackground: const Color(0xFFD1FAE5),
          title: S.tr('Code vérifié', 'Code verified'),
          message: S.tr(
            'Forfait $_validatedPlan'
                '${_validatedExpiresAt == null ? '' : ' · expire le $_validatedExpiresAt'}',
            '$_validatedPlan plan'
            '${_validatedExpiresAt == null ? '' : ' · expires $_validatedExpiresAt'}',
          ),
        ),
        const SizedBox(height: 16),
      ],
      _DavexField(
        label: S.tr('Nom de la boutique', 'Business name'),
        controller: _nameCtrl,
        hint: S.tr('Ex : Boutique Chez Marie', 'e.g. Marie’s Shop'),
        icon: Icons.storefront_outlined,
        required: true,
        capitalization: TextCapitalization.words,
      ),
      const SizedBox(height: 14),
      _DavexField(
        label: S.tr('Nom du propriétaire', 'Owner name'),
        controller: _ownerCtrl,
        icon: Icons.person_outline_rounded,
        required: true,
        capitalization: TextCapitalization.words,
      ),
      const SizedBox(height: 14),
      _DavexField(
        label: S.tr('Téléphone', 'Phone'),
        controller: _phoneCtrl,
        hint: '699 00 00 00',
        icon: Icons.phone_outlined,
        required: true,
        keyboardType: TextInputType.phone,
        formatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s()-]')),
          LengthLimitingTextInputFormatter(24),
        ],
      ),
      const SizedBox(height: 14),
      _DavexField(
        label: S.tr('Ville', 'City'),
        controller: _cityCtrl,
        hint: S.tr(
          'Ex : Douala, Yaoundé, Abidjan…',
          'e.g. Douala, Yaoundé, Abidjan…',
        ),
        icon: Icons.location_city_outlined,
        capitalization: TextCapitalization.words,
      ),
      const SizedBox(height: 14),
      _DavexField(
        label: S.tr('Quartier', 'Neighborhood'),
        controller: _neighborhoodCtrl,
        icon: Icons.place_outlined,
        capitalization: TextCapitalization.words,
      ),
    ];
  }

  List<Widget> _sectorStep() {
    final modules = SectorModules.forSector(_sector);
    return [
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.02,
        children: [
          for (final entry in _sectors.entries)
            _SectorTile(
              label: _sectorLabel(entry.key),
              icon: _sectorIcon(entry.key),
              moduleCount: SectorModules.forSector(entry.key).length,
              selected: _sector == entry.key,
              onTap: () => setState(() => _sector = entry.key),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _indigoSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _indigoLine),
            ),
            child: Text(
              S.tr(
                '${modules.length} modules inclus',
                '${modules.length} modules included',
              ),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _indigoDeep,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      // Checklist maquette → résumé informatif réel (voir en-tête : pas de
      // modèle de persistance pour un choix de catégories).
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final module in modules)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _line),
              ),
              child: Text(
                _moduleLabel(module),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _inkSoft,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      _Banner(
        icon: Icons.menu_book_rounded,
        background: _okBg,
        borderColor: _okLine,
        iconColor: _okFg,
        iconBackground: const Color(0xFFD1FAE5),
        title: S.tr(
          'Catalogue Lynkstor disponible',
          'Lynkstor catalogue available',
        ),
        message: S.tr(
          'Vous choisirez vos références pré-enregistrées depuis l’écran Catalogue, une fois le commerce créé. Le prix et le stock se règlent dans votre boutique.',
          'You will pick pre-loaded products from the Catalogue screen once your business is created. Price and stock are set in your shop.',
        ),
      ),
    ];
  }

  List<Widget> _securityStep() {
    return [
      _DavexField(
        label: S.tr('Mot de passe', 'Password'),
        controller: _passwordCtrl,
        hint: S.tr(
          'Au moins 8 caractères',
          'At least 8 characters',
        ),
        icon: Icons.lock_outline_rounded,
        required: true,
        obscure: !_showPassword,
        suffixIcon: _showPassword
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        onSuffixTap: () => setState(() => _showPassword = !_showPassword),
      ),
      const SizedBox(height: 14),
      _DavexField(
        label: S.tr('Confirmer le mot de passe', 'Confirm password'),
        controller: _passwordConfirmCtrl,
        icon: Icons.lock_reset_rounded,
        required: true,
        obscure: !_showPassword,
      ),
      const SizedBox(height: 14),
      _DavexField(
        label: S.tr('PIN (4 chiffres)', 'PIN (4 digits)'),
        controller: _pinCtrl,
        icon: Icons.pin_outlined,
        required: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscure: !_showPin,
        suffixIcon: _showPin
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        onSuffixTap: () => setState(() => _showPin = !_showPin),
        formatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
      ),
      const SizedBox(height: 14),
      _DavexField(
        label: S.tr('Confirmer le PIN', 'Confirm PIN'),
        controller: _pinConfirmCtrl,
        icon: Icons.pin_outlined,
        required: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscure: !_showPin,
        formatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        S.tr(
          _needsActivationCode
              ? 'La dernière étape active le forfait et enregistre ce téléphone. Vous pourrez ensuite travailler hors ligne.'
              : 'La dernière étape enregistre ce téléphone. Vous pourrez ensuite travailler hors ligne.',
          _needsActivationCode
              ? 'The final step activates the plan and registers this phone. You can then work offline.'
              : 'The final step registers this phone. You can then work offline.',
        ),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _muted, height: 1.4),
      ),
    ];
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
}

// ─── Unités visuelles maquette (privées à l'écran) ───────────────────────────

/// Carte secteur de la grille 3 × 3 (`border-indigo-600 bg-indigo-50/80
/// scale-[1.02]` quand sélectionnée). Émojis maquette → icônes Material.
class _SectorTile extends StatelessWidget {
  const _SectorTile({
    required this.label,
    required this.icon,
    required this.moduleCount,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int moduleCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DavexPressable(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedScale(
        scale: selected ? 1.02 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? _indigoSoft.withValues(alpha: 0.8)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _indigo : _line.withValues(alpha: 0.8),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? _indigo.withValues(alpha: 0.22)
                    : const Color(0x0A0F172A),
                blurRadius: selected ? 20 : 8,
                offset: const Offset(0, 6),
                spreadRadius: -4,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 26,
                color: selected ? _indigo : _inkSoft,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: selected ? _indigoDeep : _ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$moduleCount',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? _indigo.withValues(alpha: 0.8) : _faint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CTA dégradé indigo → purple (`.bg-gradient-to-r from-indigo-600
/// to-purple-600 shadow-glow-indigo active:scale-[0.98]`).
class _GradientCta extends StatelessWidget {
  const _GradientCta({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: DavexPressable(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: _ctaGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _indigo.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Champ maquette : carte blanche rounded-2xl, label 12 px bold + astérisque
/// rose si requis, icône leading indigo, focus bordure indigo.
class _DavexField extends StatelessWidget {
  const _DavexField({
    required this.label,
    this.controller,
    this.hint,
    this.icon,
    this.required = false,
    this.obscure = false,
    this.keyboardType,
    this.maxLength,
    this.capitalization = TextCapitalization.none,
    this.formatters,
    this.suffixIcon,
    this.onSuffixTap,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final bool required;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLength;
  final TextCapitalization capitalization;
  final List<TextInputFormatter>? formatters;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            children: [
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: _rose),
                ),
            ],
          ),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLength: maxLength,
          textCapitalization: capitalization,
          inputFormatters: formatters,
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _faint,
            ),
            filled: true,
            fillColor: Colors.white,
            counterText: '',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            prefixIcon: icon == null
                ? null
                : Icon(icon, size: 18, color: _indigo),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 0,
            ),
            suffixIcon: suffixIcon == null
                ? null
                : IconButton(
                    onPressed: onSuffixTap,
                    icon: Icon(suffixIcon, size: 18, color: _muted),
                    splashRadius: 20,
                    tooltip: S.tr('Afficher', 'Show'),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 0,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _indigo, width: 1.6),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _line),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bannière d'information (indigo « vérification », émeraude « code vérifié /
/// catalogue ») — `.rounded-2xl border flex items-start gap-3`.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.background,
    required this.borderColor,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color background;
  final Color borderColor;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloc erreur maquette (`bg-red-50 border-red-200 text-red-700 rounded-2xl`).
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _errBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _errLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: _errFg,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _errFg,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sélecteur de langue FR/EN (RÉUTILISER : logique réelle
/// `localeControllerProvider`, chrome light maquette).
class _DavexLangChip extends ConsumerWidget {
  const _DavexLangChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 16, color: _indigo),
            const SizedBox(width: 5),
            Text(
              S.isEnglish ? 'EN' : 'FR',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _indigo,
              ),
            ),
          ],
        ),
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
