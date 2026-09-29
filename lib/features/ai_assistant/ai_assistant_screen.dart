import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../design_system/components/kumba_ai_badge.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../design_system/motion/lynk_avatar.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/analytics_service.dart';
import 'data/lynk_brain_service.dart';
import 'domain/business_ai_context.dart';
import 'domain/lynk_grounded_answers.dart';
import 'lynk_quick_sheet.dart';

class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
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
      _messages.add(_AiMessage(role: 'assistant', text: text, isWelcome: true));
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
      _messages.add(const _AiMessage(role: 'assistant', text: ''));
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

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    const bottomPad = 20.0;
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            LynkAvatar(
              size: 36,
              enabled: !reduce,
              mood: _lynkMood,
              showOnline: true,
            ),
            const SizedBox(width: 10),
            Text(
              S.tr('Lynk', 'Lynk'),
              style: const TextStyle(
                color: AppColors.lynkViolet,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: S.tr('Fonctionnement et confidentialité', 'How it works and privacy'),
            onPressed: _showAbout,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: AiAurora())),
          Positioned.fill(
            child: Column(
              children: [
                Text(
                  _statusLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.lynkViolet,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  S.tr(
                    'Chiffres du jour : calcul local hors ligne · '
                    'questions libres : ${AppConfig.aiModelLabel}',
                    'Daily figures: local offline math · '
                    'free questions: ${AppConfig.aiModelLabel}',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Material(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!)),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _chip(
                        S.tr(
                          'Quel est mon chiffre d’affaires aujourd’hui ?',
                          'What is my revenue today?',
                        ),
                      ),
                      _chip(
                        S.tr(
                          'Qui me doit le plus en ce moment ?',
                          'Who owes me the most right now?',
                        ),
                      ),
                      _chip(
                        S.tr(
                          'Que dois-je réapprovisionner en priorité ?',
                          'What should I restock first?',
                        ),
                      ),
                      _chip(
                        S.tr(
                          'Mon bénéfice du jour est-il correct ?',
                          'Is today’s profit looking healthy?',
                        ),
                      ),
                      _chip(
                        S.tr(
                          'Comment améliorer mes marges ce mois-ci ?',
                          'How can I improve my margins this month?',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _messageBubble(_messages[index]),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
                  child: Row(
                    children: [
                      Expanded(
                        child: KumbaTextField(
                          controller: _input,
                          enabled: !_generating,
                          hint: S.tr(
                            'Posez une question sur votre activité…',
                            'Ask a question about your business…',
                          ),
                          onSubmitted: (_) => _ask(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: S.tr('Envoyer', 'Send'),
                        onPressed: _generating ? null : () => _ask(),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(_AiMessage message) {
    final mine = message.role == 'user';
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.82,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: mine ? AppColors.fab : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: mine
            ? null
            : Border.all(color: AppColors.lynkViolet.withValues(alpha: 0.10)),
      ),
      child: message.text.isEmpty
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: mine ? Colors.white : AppColors.lynkViolet,
              ),
            )
          : SelectableText(
              message.text,
              style: TextStyle(
                color: mine ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
    );
    if (mine) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8, bottom: 10),
            child: LynkAvatar(size: 28, mood: LynkMood.idle, enabled: false),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.source != null && !message.isWelcome)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _sourceTag(message.source!),
                  ),
                KumbaAiFrame(radius: 20, child: bubble),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Honnêteté de source : chaque réponse dit d'où elle vient.
  Widget _sourceTag(String source) {
    final local = source == 'local';
    final label = local
        ? S.tr('Calcul local · hors ligne', 'Local math · offline')
        : S.tr('${AppConfig.aiModelLabel} · en ligne', '${AppConfig.aiModelLabel} · online');
    final color = local ? AppColors.success : AppColors.lynkViolet;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
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

  Widget _chip(String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      backgroundColor: AppColors.lynkVioletSoft,
      side: BorderSide.none,
      label: Text(
        label,
        style: const TextStyle(
          color: AppColors.lynkViolet,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: _generating ? null : () => _ask(label),
    ),
  );

  LynkMood get _lynkMood {
    if (_error != null) return LynkMood.sorry;
    if (_generating) return LynkMood.thinking;
    return LynkMood.idle;
  }

  String get _statusLabel {
    if (_generating) {
      return S.tr(
        'Lynk réfléchit…',
        'Lynk is thinking…',
      );
    }
    if (_error != null) {
      return S.tr('Une erreur est survenue', 'An error occurred');
    }
    return S.tr('Assistant hybride prêt', 'Hybrid assistant ready');
  }

  bool _looksFactual(String text) {
    return RegExp(r'\d').hasMatch(text) && text.trim().length >= 12;
  }

  String _cleanAnswer(String value, {required String languageCode}) {
    var cleaned = value
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
        .replaceAll(RegExp(r'</?think>'), '')
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

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          S.tr('Fonctionnement et confidentialité', 'How it works and privacy'),
        ),
        content: Text(
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.tr('Compris', 'Got it')),
          ),
        ],
      ),
    );
  }
}

class _AiMessage {
  const _AiMessage({
    required this.role,
    required this.text,
    this.isWelcome = false,
    this.source,
  });

  final String role;
  final String text;

  /// Message UI d'accueil : exclu de l'historique envoyé au modèle.
  final bool isWelcome;

  /// 'local' = calcul déterministe sur l'appareil, 'cloud' = Llama 3.2-3B.
  final String? source;
}
