import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/davex_pressable.dart';
import '../../design_system/components/davex_sheet.dart';
import '../../design_system/motion/lynk_avatar.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/analytics_service.dart';
import 'data/lynk_brain_service.dart';
import 'domain/business_ai_context.dart';
import 'domain/lynk_grounded_answers.dart';
import 'lynk_quick_sheet.dart';

// ─── Assistant recréé depuis la maquette (AssistantScreen, App.tsx
// L4632–5069 + tokens components.css `.lk-assistant-*`) ───────────────────────
//
// Décision d'audit : RECRÉER. L'ancien `ai_assistant_screen.dart`
// (AiAssistantScreen) n'est PAS patché : il reste sur disque mais est
// déréférencé du router.
//
// LOGIQUE RÉUTILISÉE TELLE QUELLE (cœur hybride réellement en production) :
// - réponses ancrées locales `LynkGroundedAnswers.tryAnswer` sur le bundle
//   `BusinessAiContextBuilder` (ventes/stock/dettes/bénéfice calculés sur
//   l'appareil, hors ligne, quelques millisecondes) ;
// - questions libres → `LynkBrainService.ask` (LLM hébergé), historique
//   borné à 6 tours, nettoyage des balises de raisonnement et des réponses
//   « menu de capacités » sans chiffres ;
// - honnêteté de source : chaque réponse porte son étiquette (calcul local
//   hors ligne vs modèle en ligne) ; repli local si le cloud échoue ;
// - message d'accueil personnalisé (prénom réel), conso du prompt en
//   attente (`pendingAiPromptProvider`, fiche rapide Lynk / Accueil),
//   analytics `ai.used`, confidentialité (`_showAbout`).
//
// Mapping maquette → unité par unité (tokens CSS `.lk-assistant-*`, qui
// PRIME sur les classes Tailwind bleues du JSX) :
// - bandeau « Carnet de Dette Client » : dégradé navy 108° (#0B1C30 →
//   #16253A 56 % → #55370B), bordure orange 32 %, label #FFD58C, action
//   orange #FF9800 — DONNÉES RÉELLES (somme des soldes > 0,
//   `CustomerService.debtors`) ;
// - bulles : utilisateur #1D6BFF à droite (angle haut-droit coupé), IA
//   surface+bordure décorative+ombre card à gauche (angle haut-gauche
//   coupé), avatar bot dégradé #1D6BFF→#5446C7 28 px rounded-xl, horodatage
//   10 px aligné à droite (heure RÉELLE locale) ;
// - frappe : bulle IA à trois points rebondissants décalés de 150 ms ;
// - barre de saisie : surface + bordure supérieure, champ surélevé
//   rounded-2xl min-h 48, envoi orange #FF9800 glow, opacité réduite quand
//   vide ;
// - gras markdown `**…**` rendu dans les bulles (le modèle en ligne émet
//   du markdown ; les réponses ancrées aussi).
//
// Écarts maquette↔réel documentés (jamais tranchés en silence) :
// - le `aiReply` de la maquette EST UN FAUX BOT (chiffres codés en dur :
//   « 47 300 FCFA », stock du Sucre, top produits inventés) → NON REPRIS.
//   Les bulles affichent les VRAIES réponses ancrées + LLM, jamais une
//   réponse simulée ;
// - les 4 modales « Carnet de Dette » de la maquette (liste, détail,
//   remboursement, WhatsApp) ne sont PAS dupliquées ici : l'écran réel
//   `/debts` (detteurs Drift, remboursements, historique) est la source de
//   vérité unique — le bandeau « Ouvrir » y route (même décision que les
//   modales shell a11). Le rappel WhatsApp réel existe déjà
//   (`notifications_screen`, deep link `wa.me`) ;
// - bouton micro (dictée) : AUCUN modèle de reconnaissance vocale dans le
//   projet → non fabriqué, retiré (pas un bouton qui « fait semblant ») ;
// - le fond canvas et les puces de suggestions viennent des tokens du
//   shell (2 thèmes) ; l'« AiAurora » de l'ancien écran (décor violet) est
//   retiré : la maquette n'a pas d'aurora sur cet écran.

/// Fond du message chiffré du bandeau : total dû et comptes actifs.
class _DebtLedger {
  const _DebtLedger(this.total, this.count);

  final double total;
  final int count;
}

final _assistantDebtProvider = FutureProvider.autoDispose<_DebtLedger>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return const _DebtLedger(0, 0);
  final debtors = await ref.watch(customerServiceProvider).debtors(business.id);
  var total = 0.0;
  var count = 0;
  for (final c in debtors) {
    if (c.balance > 0) {
      total += c.balance;
      count++;
    }
  }
  return _DebtLedger(total, count);
});

// ─── Tokens maquette hors palette (dégradés spécifiques à cet écran) ─────────
const Color _userBubble = Color(0xFF1D6BFF);
const List<Color> _bannerColors = [Color(0xFF0B1C30), Color(0xFF16253A), Color(0xFF55370B)];
const Color _bannerBorder = Color(0x52FF9800);
const Color _bannerLabel = Color(0xFFFFD58C);
const Color _orange = Color(0xFFFF9800);
const LinearGradient _botAvatarGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1D6BFF), Color(0xFF5446C7)],
);

class DavexAssistantScreen extends ConsumerStatefulWidget {
  const DavexAssistantScreen({super.key});

  @override
  ConsumerState<DavexAssistantScreen> createState() =>
      _DavexAssistantScreenState();
}

class _DavexAssistantScreenState extends ConsumerState<DavexAssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_AiMessage> _messages = [];

  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Accueil personnalisé après le 1er frame (session + locale dispo),
    // puis consommation d'un prompt transmis (dashboard, fiche rapide Lynk).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _seedWelcomeIfNeeded();
      _flushPending();
    });
  }

  void _seedWelcomeIfNeeded() {
    if (_messages.isNotEmpty) return;
    final firstName = BusinessAiContextBuilder.firstNameOf(
      ref.read(sessionProvider).user?.fullName,
    );
    final isEn = ref.read(localeControllerProvider).languageCode == 'en';
    final text = _welcomeText(firstName: firstName, isEn: isEn);
    setState(() {
      _messages.add(
        _AiMessage(role: 'assistant', text: text, isWelcome: true),
      );
    });
  }

  static String _welcomeText({required String firstName, required bool isEn}) {
    if (isEn) {
      if (firstName.isEmpty) {
        return 'Ready when you are. Ask about today’s sales, stock, or customer debts — I answer instantly with your local figures, and think bigger online.';
      }
      return 'Hi $firstName — ready when you are. Sales, stock and debts: instant local numbers. Anything broader: ask, I’ll think it through online.';
    }
    if (firstName.isEmpty) {
      return 'Je suis prêt. Ventes, stock, dettes du jour : je réponds instantanément avec vos chiffres locaux. Pour le reste, posez votre question — je réfléchis en ligne.';
    }
    return 'Bonjour $firstName. Chiffres du jour : réponse locale instantanée. Conseils et questions libres : je réfléchis en ligne avec vous.';
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _flushPending() {
    final pending = ref.read(pendingAiPromptProvider);
    if (pending == null || pending.trim().isEmpty) return;
    ref.read(pendingAiPromptProvider.notifier).state = null;
    unawaited(_ask(pending));
  }

  Future<void> _ask([String? preset]) async {
    final question = (preset ?? _input.text).trim();
    final session = ref.read(sessionProvider);
    final business = session.business;
    final languageCode = ref.read(localeControllerProvider).languageCode;
    if (question.isEmpty || _generating) return;
    if (business == null) {
      setState(
        () => _error = S.tr('Aucun commerce actif.', 'No active business.'),
      );
      return;
    }

    final assistantIndex = _messages.length + 1;
    setState(() {
      _generating = true;
      _error = null;
      _messages.add(_AiMessage(role: 'user', text: question));
      _messages.add(_AiMessage(role: 'assistant', text: ''));
      _input.clear();
    });
    AppAnalytics.track('ai.used');
    _scrollToEnd();

    String? grounded;
    try {
      final bundle = await ref
          .read(businessAiContextProvider)
          .buildBundle(
            business,
            userDisplayName: session.user?.fullName,
            languageCode: languageCode,
          );
      grounded = LynkGroundedAnswers.tryAnswer(
        question,
        bundle.snapshot,
        isEn: languageCode == 'en',
      );

      // Cœur de l'hybride : les chiffres métier sont calculés ICI, localement,
      // instantanément et hors ligne. Le cloud n'intervient que pour le reste.
      if (grounded != null) {
        if (!mounted) return;
        setState(() {
          _messages[assistantIndex] = _AiMessage(
            role: 'assistant',
            text: grounded!,
            source: 'local',
          );
          _generating = false;
        });
        _scrollToEnd();
        return;
      }

      // Historique conversationnel seul (pas le message d'accueil UI).
      final conversational = _messages
          .where((m) => !m.isWelcome && m.text.trim().isNotEmpty)
          .toList();
      // Exclut la question courante (dernier user) et la bulle vide.
      final historySource = conversational.length > 1
          ? conversational.sublist(0, conversational.length - 1)
          : <_AiMessage>[];
      final recent = historySource.length > 6
          ? historySource.sublist(historySource.length - 6)
          : historySource;

      final answer = await ref
          .read(lynkBrainProvider)
          .ask(
            question: question,
            systemPrompt: bundle.systemPrompt,
            history: [
              for (final message in recent)
                LynkChatTurn(role: message.role, text: message.text),
            ],
          );
      if (!mounted) return;
      final cleaned = _cleanAnswer(answer.text, languageCode: languageCode);
      setState(() {
        _messages[assistantIndex] = _AiMessage(
          role: 'assistant',
          text: cleaned,
          source: 'cloud',
        );
        _generating = false;
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      final fallback = grounded;
      if (fallback != null) {
        setState(() {
          _messages[assistantIndex] = _AiMessage(
            role: 'assistant',
            text: fallback,
            source: 'local',
          );
          _generating = false;
        });
        return;
      }
      final isEn = languageCode == 'en';
      setState(() {
        _messages[assistantIndex] = _AiMessage(
          role: 'assistant',
          text: isEn
              ? 'I could not reach the online brain. Sales, stock and debt '
                    'questions still work offline — try one of the chips below.'
              : 'Je n’ai pas pu joindre le cerveau en ligne. Vos chiffres '
                    '(ventes, stock, dettes, bénéfice) répondent toujours '
                    'hors ligne — essayez une suggestion ci-dessous.',
          source: 'local',
        );
        _generating = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  bool _looksFactual(String text) {
    return RegExp(r'\d').hasMatch(text) && text.trim().length >= 12;
  }

  String _cleanAnswer(String value, {required String languageCode}) {
    var cleaned = value
        .replaceAll(RegExp(r'<think>[\s\S]*?<\/think>'), '')
        .replaceAll(RegExp(r'<\/?think>'), '')
        .trim();

    cleaned = _trimCapabilityMenu(cleaned);

    if (cleaned.isEmpty) {
      return languageCode == 'en'
          ? 'I could not form an answer. Try a more specific question about sales, stock, or debts.'
          : 'Je n’ai pas pu formuler une réponse. Essayez une question plus précise sur les ventes, le stock ou les dettes.';
    }
    return cleaned;
  }

  /// Réduit les réponses type « Bonjour, je peux faire A, B, C… » sans données.
  String _trimCapabilityMenu(String text) {
    final lower = text.toLowerCase();
    final looksLikeMenu =
        (lower.contains('je peux') ||
            lower.contains('i can help') ||
            lower.contains('i can analyze') ||
            lower.contains('voici ce que je peux')) &&
        (lower.contains('ventes') ||
            lower.contains('sales') ||
            lower.contains('stocks') ||
            lower.contains('dettes') ||
            lower.contains('debts')) &&
        !_looksFactual(text);

    if (!looksLikeMenu) return text;

    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length <= 2) return text;
    return sentences.take(2).join(' ').trim();
  }

  String _friendlyError(Object error) {
    if (error is LynkBrainRejectException) return error.message;
    if (error is LynkBrainOfflineException) return error.message;
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('SocketException') || text.contains('TimeoutException')) {
      return S.tr(
        'Connexion interrompue. Vérifiez le réseau puis réessayez.',
        'Connection interrupted. Check your network and try again.',
      );
    }
    return text;
  }

  LynkMood get _lynkMood {
    if (_error != null) return LynkMood.sorry;
    if (_generating) return LynkMood.thinking;
    return LynkMood.idle;
  }

  String get _statusLabel {
    if (_generating) {
      return S.tr('Lynk réfléchit…', 'Lynk is thinking…');
    }
    if (_error != null) {
      return S.tr('Une erreur est survenue', 'An error occurred');
    }
    return S.tr('Assistant hybride prêt', 'Hybrid assistant ready');
  }

  void _showAbout() {
    showDavexSheet<void>(
      context,
      title: S.tr('Fonctionnement et confidentialité', 'How it works and privacy'),
      initialChildSize: 0.55,
      builder: (sheetContext, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Text(
          S.tr(
            'Vos chiffres du jour (ventes, encaissements, dettes, stock, '
                'bénéfice) sont calculés uniquement sur cet appareil : ces '
                'réponses fonctionnent entièrement hors ligne. Vos questions '
                'libres sont réfléchies par ${AppConfig.aiModelLabel}, un '
                'grand modèle hébergé : seules vos questions et un résumé '
                'd’affaires chiffré (aucun nom de client, aucune donnée '
                'personnelle) quittent l’appareil, le temps de la réponse. '
                'Lecture seule : vérifiez toute recommandation importante.',
            'Your daily figures (sales, collections, debts, stock, profit) '
                'are computed only on this device: those answers work fully '
                'offline. Free-form questions are reasoned by '
                '${AppConfig.aiModelLabel}, a hosted large model: only your '
                'question and a numeric business summary (no customer names, '
                'no personal data) leave the device, just for the answer. '
                'Read-only: verify important recommendations.',
          ),
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final session = ref.watch(sessionProvider);
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final canDebtLedger = session.can(AppPermission.debtsView);

    return Scaffold(
      backgroundColor: p.canvas,
      body: Column(
        children: [
          if (canDebtLedger) const _DebtBanner(),
          // Bandeau modèle + statut (réel : hybride local/cloud, source
          // honnête). La maquette n'a pas d'équivalent → style discret.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                LynkAvatar(size: 32, enabled: !reduce, mood: _lynkMood, showOnline: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _statusLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        S.tr(
                          'Chiffres du jour : calcul local hors ligne · '
                          'questions libres : ${AppConfig.aiModelLabel}',
                          'Daily figures: local offline math · '
                          'free questions: ${AppConfig.aiModelLabel}',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: p.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: S.tr(
                    'Fonctionnement et confidentialité',
                    'How it works and privacy',
                  ),
                  onPressed: _showAbout,
                  icon: Icon(Icons.info_outline_rounded, size: 20, color: p.textSecondary),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.dangerBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.danger.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 17, color: p.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.dangerFg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _SuggestionChips(onPick: _ask, disabled: _generating),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) =>
                  _MessageBubble(message: _messages[index], generating: _generating),
            ),
          ),
          _InputBar(
            controller: _input,
            disabled: _generating,
            onSend: () => unawaited(_ask()),
          ),
        ],
      ),
    );
  }
}

// ─── Bandeau Carnet de Dette (données RÉELLES ; « Ouvrir » → /debts) ─────────
class _DebtBanner extends ConsumerWidget {
  const _DebtBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(_assistantDebtProvider);
    final data = ledger.valueOrNull;
    final totalLabel = MoneyFormat.format(
      data?.total ?? 0,
      showCurrency: false,
    );
    final count = data?.count ?? 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-1.0, 0.2),
          end: Alignment(1.0, -0.2),
          colors: _bannerColors,
          stops: [0, 0.56, 1],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bannerBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.menu_book_rounded, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.tr('Carnet de Dette Client', 'Customer Credit Ledger'),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: _bannerLabel,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  ledger.isLoading && data == null
                      ? '…'
                      : S.tr(
                          '$totalLabel FCFA en cours • $count comptes',
                          '$totalLabel FCFA outstanding • $count accounts',
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DavexPressable(
            semanticLabel: S.tr('Ouvrir le carnet de dette', 'Open credit ledger'),
            onTap: () {
              HapticFeedback.selectionClick();
              context.push('/debts');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: _orange,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24FF9800),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                S.tr('Ouvrir', 'Open'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3A2500), // encre AA sur orange (6,7:1)
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Puces de suggestions (questions RÉELLES prises en charge par les
// réponses ancrées) ───────────────────────────────────────────────────────────
class _SuggestionChips extends ConsumerWidget {
  const _SuggestionChips({required this.onPick, required this.disabled});

  final ValueChanged<String> onPick;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final labels = <String>[
      S.tr(
        'Quel est mon chiffre d’affaires aujourd’hui ?',
        'What is my revenue today?',
      ),
      S.tr(
        'Qui me doit le plus en ce moment ?',
        'Who owes me the most right now?',
      ),
      S.tr(
        'Que dois-je réapprovisionner en priorité ?',
        'What should I restock first?',
      ),
      S.tr(
        'Mon bénéfice du jour est-il correct ?',
        'Is today’s profit looking healthy?',
      ),
      S.tr(
        'Comment améliorer mes marges ce mois-ci ?',
        'How can I improve my margins this month?',
      ),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final label in labels)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Opacity(
                opacity: disabled ? 0.5 : 1,
                child: DavexPressable(
                  minTouchTarget: 32,
                  semanticLabel: label,
                  onTap: disabled ? null : () => onPick(label),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: p.surfaceElevated,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: p.borderControl),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Bulle de message (maquette : angles coupés, avatar dégradé, horodatage) ─
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.generating});

  final _AiMessage message;
  final bool generating;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final mine = message.role == 'user';

    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(15, 11, 15, 9),
      decoration: BoxDecoration(
        color: mine ? _userBubble : p.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: Radius.circular(mine ? 4 : 18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: const Radius.circular(18),
        ),
        border: mine
            ? null
            : Border.all(color: p.borderDecorative),
        boxShadow: [
          mine
              ? BoxShadow(
                  color: _userBubble.withValues(alpha: 0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                )
              : p.shadowCard,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.text.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _TypingDots(color: p.textSecondary),
                )
              else
                _MarkdownText(
                  text: message.text,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.42,
                    color: mine ? Colors.white : p.text,
                  ),
                ),
              const SizedBox(height: 3),
              Text(
                _formatTime(message.time),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: mine
                      ? Colors.white.withValues(alpha: 0.7)
                      : p.textSecondary,
                ),
              ),
        ],
      ),
    );

    if (mine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
            ),
            child: bubble,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: BoxDecoration(
              gradient: _botAvatarGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x381D6BFF),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.smart_toy_outlined, size: 15, color: Colors.white),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.source != null && !message.isWelcome)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SourceTag(source: message.source!),
                  ),
                bubble,
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Étiquette de source honnête (logique RÉELLE conservée) : chaque réponse
/// dit d'où elle vient.
class _SourceTag extends StatelessWidget {
  const _SourceTag({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final local = source == 'local';
    final label = local
        ? S.tr('Calcul local · hors ligne', 'Local math · offline')
        : S.tr(
            '${AppConfig.aiModelLabel} · en ligne',
            '${AppConfig.aiModelLabel} · online',
          );
    final color = local ? p.success : p.action;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            local ? Icons.memory_rounded : Icons.cloud_done_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rendu du gras markdown `**…**` émis par le modèle en ligne (et某些
/// réponses ancrées) — purement typographique, aucune donnée inventée.
class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final children = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) children.add(const TextSpan(text: '\n'));
      children.addAll(_boldSpans(lines[i]));
    }
    return SelectableText.rich(TextSpan(style: style, children: children));
  }

  static List<InlineSpan> _boldSpans(String line) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var last = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > last) {
        spans.add(TextSpan(text: line.substring(last, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
      last = match.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    if (spans.isEmpty) spans.add(TextSpan(text: line));
    return spans;
  }
}

/// Trois points rebondissants de la maquette (décalage 150 ms) ; statiques
/// si l'utilisateur a demandé la réduction des animations (HIG).
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (!reduce) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                _dot(t, i),
            ],
          );
        },
      ),
    );
  }

  Widget _dot(double t, int index) {
    // Même courbe que `animate-bounce` avec animation-delay de 150 ms.
    final phase = _controller.isAnimating
        ? ((t + index * (150 / 900)) % 1.0)
        : 0.0;
    final lift = (5.5 * (1 - (phase - 0.5).abs() * 2)).clamp(0.0, 5.5);
    return Transform.translate(
      offset: Offset(0, -lift),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.6 + lift / 11),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── Barre de saisie maquette (champ surélevé + envoi orange) ───────────────
class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.disabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool disabled;
  final VoidCallback onSend;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final canSend =
        !widget.disabled && widget.controller.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.borderDecorative)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).padding.bottom > 0 ? 10 : 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: p.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.borderControl),
              ),
              child: TextField(
                controller: widget.controller,
                enabled: !widget.disabled,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(fontSize: 14, color: p.text),
                onSubmitted: (_) => widget.onSend(),
                decoration: InputDecoration(
                  hintText: S.tr(
                    'Posez une question sur votre activité…',
                    'Ask a question about your business…',
                  ),
                  hintStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: p.textSecondary,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: canSend ? 1 : 0.4,
            child: DavexPressable(
              minTouchTarget: 48,
              semanticLabel: S.tr('Envoyer', 'Send'),
              onTap: canSend ? widget.onSend : null,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _orange,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26FF9800),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.send_rounded,
                  size: 19,
                  color: Color(0xFF3A2500), // encre AA sur orange (6,7:1)
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiMessage {
  _AiMessage({
    required this.role,
    required this.text,
    this.isWelcome = false,
    this.source,
  }) : time = DateTime.now();

  final String role;
  final String text;

  /// Message UI d'accueil : exclu de l'historique envoyé au modèle.
  final bool isWelcome;

  /// 'local' = calcul déterministe sur l'appareil, 'cloud' = LLM hébergé.
  final String? source;

  /// Heure RÉELLE d'affichage (la maquette affichait une horloge figée).
  final DateTime time;
}
