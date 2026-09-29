import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/config/runtime_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/subscription_info.dart';
import '../../shared/services/subscription_payment_service.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    final previous = ref.read(sessionProvider).subscription;
    setState(() => _refreshing = true);
    final updated = await ref
        .read(sessionProvider.notifier)
        .refreshSubscription();
    if (!mounted) return;
    setState(() => _refreshing = false);

    final wasConfirmed =
        updated.checkedAt != null && updated.checkedAt != previous.checkedAt;
    final ok = wasConfirmed || updated.isDemo;
    showLkToast(
      context,
      ok
          ? S.tr(
              'Abonnement vérifié et enregistré sur cet appareil.',
              'Subscription verified and saved on this device.',
            )
          : S.tr(
              'État local conservé. Vérifiez votre connexion pour une confirmation cloud.',
              'Local status kept. Check your connection for cloud confirmation.',
            ),
      tone: ok ? LkToastTone.success : LkToastTone.warning,
      icon: ok ? Icons.verified_outlined : Icons.cloud_off_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final subscription = session.subscription;
    final business = session.business;
    final presentation = _SubscriptionPresentation(subscription);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(
          S.tr('Activation et abonnement', 'Activation and subscription'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                children: [
                  _statusCard(
                    context,
                    subscription: subscription,
                    presentation: presentation,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    S.tr('Détails du forfait', 'Plan details'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  KumbaCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _detailRow(
                          context,
                          icon: Icons.layers_outlined,
                          label: S.tr('Forfait', 'Plan'),
                          value: subscription.planName,
                        ),
                        const Divider(height: 1, indent: 56),
                        _detailRow(
                          context,
                          icon: Icons.event_available_outlined,
                          label: S.tr('Expiration', 'Expiration'),
                          value: _date(subscription.expiresAt),
                        ),
                        const Divider(height: 1, indent: 56),
                        _detailRow(
                          context,
                          icon: Icons.cloud_done_outlined,
                          label: S.tr(
                            'Dernière vérification',
                            'Last verification',
                          ),
                          value: _dateTime(subscription.checkedAt),
                        ),
                        const Divider(height: 1, indent: 56),
                        _detailRow(
                          context,
                          icon: Icons.point_of_sale_outlined,
                          label: S.tr('Ventes', 'Sales'),
                          value: subscription.allowsSales
                              ? S.tr('Autorisées', 'Allowed')
                              : S.tr('Bloquées', 'Blocked'),
                          valueColor: subscription.allowsSales
                              ? AppColors.kpiSales
                              : AppColors.kpiDeposit,
                        ),
                      ],
                    ),
                  ),
                  if (subscription.isCloudLinked) ...[
                    const SizedBox(height: AppSpacing.md),
                    KumbaButton(
                      label: S.tr('Vérifier maintenant', 'Verify now'),
                      icon: Icons.sync_rounded,
                      isLoading: _refreshing,
                      onPressed: _refreshing ? null : _refresh,
                    ),
                  ],
                  if (!subscription.isDemo && subscription.isCloudLinked) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const _MobileMoneyPaymentSection(),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  _explanationCard(
                    context,
                    icon: subscription.isDemo
                        ? Icons.science_outlined
                        : Icons.key_outlined,
                    title: subscription.isDemo
                        ? S.tr('Mode démonstration', 'Demonstration mode')
                        : ActivationPolicy.requireAgentActivationCode
                        ? S.tr(
                            'Comment fonctionne l’activation',
                            'How activation works',
                          )
                        : S.tr('Panel boutiques test', 'Test shop panel'),
                    body: subscription.isDemo
                        ? S.tr(
                            'Ce commerce reste uniquement sur cet appareil et ne correspond pas à un abonnement facturé.',
                            'This business stays on this device and is not a paid subscription.',
                          )
                        : ActivationPolicy.requireAgentActivationCode
                        ? S.tr(
                            'Le code remis par votre commercial est vérifié lors de la création du commerce. '
                                'Il associe cet appareil au forfait et au compte Lynkstor.',
                            'The code provided by your agent is verified when the business is created. '
                                'It links this device to the Lynkstor account and plan.',
                          )
                        : S.tr(
                            'Aucune clé d’activation n’est demandée. Le commerce est créé directement sur cet appareil.',
                            'No activation key is required. The business is created directly on this device.',
                          ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _explanationCard(
                    context,
                    icon: Icons.wifi_off_outlined,
                    title: S.tr('Continuité hors ligne', 'Offline continuity'),
                    body: S.tr(
                      'Après une vérification réussie, l’application conserve localement le dernier état connu. '
                          'Les ventes restent disponibles hors ligne pendant la période de grâce prévue.',
                      'After a successful verification, the app keeps the latest known status locally. '
                          'Sales remain available offline during the configured grace period.',
                    ),
                  ),
                  if (!subscription.isDemo) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      S.tr(
                        'Renouvellement ou assistance',
                        'Renewal or support',
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    KumbaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            S.tr(
                              'Contactez votre commercial Lynkstor en indiquant le nom du commerce et sa référence.',
                              'Contact your Lynkstor agent and provide the business name and reference.',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SelectableText(
                            business == null
                                ? '—'
                                : '${business.name}\n${business.id}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          if (business != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: '${business.name}\n${business.id}',
                                  ),
                                );
                                if (!context.mounted) return;
                                showLkToast(
                                  context,
                                  S.tr(
                                    'Référence copiée.',
                                    'Reference copied.',
                                  ),
                                  tone: LkToastTone.info,
                                  icon: Icons.copy_all_rounded,
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: Text(
                                S.tr('Copier la référence', 'Copy reference'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(
    BuildContext context, {
    required SubscriptionInfo subscription,
    required _SubscriptionPresentation presentation,
  }) {
    return Semantics(
      container: true,
      label: '${presentation.statusLabel}, ${subscription.planName}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: presentation.background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: presentation.color.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: presentation.color.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: presentation.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                presentation.icon,
                color: presentation.color,
                size: 28,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.statusLabel,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: presentation.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    presentation.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 21),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: valueColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _explanationCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return KumbaCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _date(String? raw) {
    if (raw == null || raw.isEmpty) return S.tr('Non renseignée', 'Not set');
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _dateTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return S.tr('Jamais', 'Never');
    }
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return DateFormat('dd/MM/yyyy · HH:mm').format(date);
  }
}

class _SubscriptionPresentation {
  _SubscriptionPresentation(this.subscription);

  final SubscriptionInfo subscription;

  Color get color {
    if (subscription.isDemo) return AppColors.kpiDebt;
    if (!subscription.allowsSales || subscription.isExpired) {
      return AppColors.kpiDeposit;
    }
    if (subscription.isCloudLinked) return AppColors.kpiSales;
    return AppColors.fab;
  }

  Color get background {
    if (subscription.isDemo) return AppColors.kpiDebtBg;
    if (!subscription.allowsSales || subscription.isExpired) {
      return AppColors.kpiDepositBg;
    }
    if (subscription.isCloudLinked) return AppColors.kpiSalesBg;
    return AppColors.kpiCollectBg;
  }

  IconData get icon {
    if (subscription.isDemo) return Icons.science_outlined;
    if (!subscription.allowsSales) return Icons.lock_clock_outlined;
    if (subscription.isCloudLinked) return Icons.verified_user_outlined;
    return Icons.cloud_off_outlined;
  }

  String get statusLabel {
    if (subscription.isDemo) {
      return S.tr('Démonstration locale', 'Local demonstration');
    }
    if (subscription.isVerificationStale && subscription.status == 'active') {
      return S.tr('Vérification requise', 'Verification required');
    }
    switch (subscription.status) {
      case 'active':
        return subscription.isExpired
            ? S.tr('Abonnement expiré', 'Subscription expired')
            : S.tr('Abonnement actif', 'Subscription active');
      case 'expired':
        return S.tr('Abonnement expiré', 'Subscription expired');
      case 'suspended':
        return S.tr('Abonnement suspendu', 'Subscription suspended');
      case 'missing':
        return S.tr('Aucun forfait', 'No active plan');
      default:
        return subscription.isCloudLinked
            ? S.tr('État à vérifier', 'Status needs verification')
            : S.tr('Mode local', 'Local mode');
    }
  }

  String get description {
    if (subscription.isDemo) {
      return S.tr(
        'Données de démonstration, sans synchronisation cloud.',
        'Demonstration data without cloud synchronization.',
      );
    }
    if (subscription.isVerificationStale && subscription.status == 'active') {
      return S.tr(
        'La dernière confirmation cloud date de plus de 7 jours. Connectez cet appareil puis vérifiez le forfait.',
        'The last cloud confirmation is over 7 days old. Connect this device and verify the plan.',
      );
    }
    if (!subscription.allowsSales) {
      return S.tr(
        'Les nouvelles ventes sont bloquées. Contactez votre commercial pour régulariser le forfait.',
        'New sales are blocked. Contact your agent to restore the plan.',
      );
    }
    if (subscription.isCloudLinked) {
      return S.tr(
        'Cet appareil est activé et lié au cloud Lynkstor.',
        'This device is activated and linked to Lynkstor cloud.',
      );
    }
    return S.tr(
      'L’application fonctionne localement, sans liaison cloud confirmée.',
      'The app is running locally without a confirmed cloud connection.',
    );
  }
}


// ————————————————————————————————————————————— Paiement abonnement Mobile Money ———
enum _PayPhase { form, submitting, awaitingApproval, success, error }

class _MobileMoneyPaymentSection extends ConsumerStatefulWidget {
  const _MobileMoneyPaymentSection();

  @override
  ConsumerState<_MobileMoneyPaymentSection> createState() =>
      _MobileMoneyPaymentSectionState();
}

class _MobileMoneyPaymentSectionState
    extends ConsumerState<_MobileMoneyPaymentSection> {
  static const _mtn = 'mtn_momo';
  static const _orange = 'orange_money';

  late final TextEditingController _phone;
  String _channel = _mtn;
  _PayPhase _phase = _PayPhase.form;
  String? _message;
  String _intentId = '';
  bool _active = true;
  SubscriptionPaymentService? _service;

  @override
  void initState() {
    super.initState();
    final biz = ref.read(sessionProvider).business;
    _phone = TextEditingController(text: biz?.phone ?? '');
    if (_phone.text.trim().isEmpty) {
      _channel = _mtn;
    }
  }

  @override
  void dispose() {
    _active = false;
    _phone.dispose();
    _service?.dispose();
    _service = null;
    super.dispose();
  }

  num? get _amount => ref.read(sessionProvider).subscription.priceFcfa;

  Future<void> _pay() async {
    FocusScope.of(context).unfocus();
    final phone = _phone.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 8) {
      setState(() {
        _phase = _PayPhase.error;
        _message = S.tr(
          'Numéro invalide. Saisissez le numéro Mobile Money du payeur.',
          'Invalid number. Enter the payer Mobile Money number.',
        );
      });
      return;
    }

    setState(() {
      _phase = _PayPhase.submitting;
      _message = null;
    });

    final token = await ref.read(sessionProvider.notifier).cloudSyncToken();
    if (!_active) return;
    if (token == null || token.isEmpty) {
      setState(() {
        _phase = _PayPhase.error;
        _message = S.tr(
          'Cet appareil n’est pas lié au cloud Lynkstor. Vérifiez votre connexion puis réessayez.',
          'This device is not linked to Lynkstor cloud. Check your connection and retry.',
        );
      });
      return;
    }

    final service = SubscriptionPaymentService();
    _service?.dispose();
    _service = service;
    try {
      final res = await service.initiate(
        syncToken: token,
        channel: _channel,
        phone: phone,
      );
      if (!_active) return;

      if (res.isFailed || res.intentId.isEmpty) {
        setState(() {
          _phase = _PayPhase.error;
          _message = res.message;
        });
        return;
      }

      setState(() {
        _intentId = res.intentId;
        _phase = _PayPhase.awaitingApproval;
        _message = res.message;
      });

      final outcome = await service.pollUntilFinal(
        syncToken: token,
        intentId: res.intentId,
        isCancelled: () => !_active,
      );
      if (!_active) return;

      if (outcome == PaymentOutcome.succeeded) {
        await ref.read(sessionProvider.notifier).refreshSubscription();
        if (!_active) return;
        setState(() {
          _phase = _PayPhase.success;
          _message = S.tr(
            'Paiement confirmé. Votre abonnement est actif et prolongé.',
            'Payment confirmed. Your subscription is active and renewed.',
          );
        });
      } else if (outcome == PaymentOutcome.failed) {
        setState(() {
          _phase = _PayPhase.error;
          _message = S.tr(
            'Le paiement a échoué ou a expiré. Vous n’avez pas été débité. Réessayez.',
            'The payment failed or expired. You were not charged. Please try again.',
          );
        });
      } else {
        setState(() {
          _phase = _PayPhase.error;
          _message = S.tr(
            'Paiement toujours en attente. Si vous avez confirmé sur votre téléphone, touchez « Vérifier » dans quelques instants.',
            'Payment still pending. If you approved it on your phone, tap “Verify” in a moment.',
          );
        });
      }
    } catch (e) {
      if (!_active) return;
      setState(() {
        _phase = _PayPhase.error;
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _recheck() async {
    final token = await ref.read(sessionProvider.notifier).cloudSyncToken();
    if (!_active || token == null || _intentId.isEmpty) return;
    setState(() {
      _phase = _PayPhase.submitting;
      _message = null;
    });
    final service = _service ??= SubscriptionPaymentService();
    final outcome = await service.checkStatus(
      syncToken: token,
      intentId: _intentId,
    );
    if (!_active) return;
    if (outcome == PaymentOutcome.succeeded) {
      await ref.read(sessionProvider.notifier).refreshSubscription();
      if (!_active) return;
      setState(() {
        _phase = _PayPhase.success;
        _message = S.tr(
          'Paiement confirmé. Merci !',
          'Payment confirmed. Thank you!',
        );
      });
    } else if (outcome == PaymentOutcome.failed) {
      setState(() {
        _phase = _PayPhase.error;
        _message = S.tr(
          'Le paiement a échoué. Réessayez.',
          'The payment failed. Try again.',
        );
      });
    } else {
      setState(() {
        _phase = _PayPhase.error;
        _message = S.tr(
          'Toujours en attente de confirmation sur votre téléphone.',
          'Still waiting for confirmation on your phone.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    final hasPrice = amount != null && amount > 0;

    return KumbaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android_rounded, color: AppColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  S.tr('Payer par Mobile Money', 'Pay with Mobile Money'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            hasPrice
                ? S.tr(
                    'Confirmez la demande envoyée sur le téléphone du payeur. Le montant est fixé par Lynkstor.',
                    'Approve the request sent to the payer’s phone. The amount is set by Lynkstor.',
                  )
                : S.tr(
                    'Aucun tarif en ligne n’est associé à ce compte. Contactez votre commercial Lynkstor.',
                    'No online price is linked to this account. Contact your Lynkstor agent.',
                  ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasPrice)
            _banner(
              context,
              icon: Icons.support_agent_rounded,
              color: AppColors.primary,
              text: S.tr(
                'Paiement mobile indisponible pour ce forfait.',
                'Mobile payment unavailable for this plan.',
              ),
            )
          else if (_phase == _PayPhase.success)
            _banner(
              context,
              icon: Icons.verified_rounded,
              color: AppColors.success,
              text: _message ?? '',
            )
          else if (_phase == _PayPhase.error)
            _banner(
              context,
              icon: Icons.error_outline_rounded,
              color: AppColors.error,
              text: _message ?? '',
            )
          else if (_phase == _PayPhase.awaitingApproval)
            _awaitingPanel(context)
          else
            _form(context, amount),
        ],
      ),
    );
  }

  Widget _form(BuildContext context, num amount) {
    final busy = _phase == _PayPhase.submitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.tr('Canal de paiement', 'Payment channel'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: _mtn,
              label: Text(S.tr('MTN MoMo', 'MTN MoMo')),
              icon: const Icon(Icons.network_cell_rounded, size: 18),
            ),
            ButtonSegment(
              value: _orange,
              label: Text(S.tr('Orange Money', 'Orange Money')),
              icon: const Icon(Icons.cell_wifi_rounded, size: 18),
            ),
          ],
          selected: {_channel},
          onSelectionChanged: busy
              ? null
              : (s) => setState(() => _channel = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _phone,
          enabled: !busy,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
          ],
          decoration: InputDecoration(
            labelText: S.tr('Numéro du payeur', 'Payer number'),
            hintText: '+237 6XXXXXXXX',
            prefixIcon: const Icon(Icons.dialpad_rounded),
            helperText: S.tr(
              'Format international, indicatif inclus.',
              'International format, country code included.',
            ),
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                S.tr('Montant', 'Amount'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              _formatFcfa(amount),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        KumbaButton(
          label: S.tr('Payer maintenant', 'Pay now'),
          icon: Icons.lock_rounded,
          isLoading: busy,
          onPressed: busy ? null : _pay,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          S.tr(
            'Sans danger : votre code secret Mobile Money n’est saisi que sur votre téléphone, jamais dans Lynkstor.',
            'Safe: your Mobile Money secret code is entered only on your phone, never in Lynkstor.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _awaitingPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                S.tr(
                  'En attente de confirmation',
                  'Waiting for confirmation',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _message ??
              S.tr(
                'Une demande de paiement a été envoyée sur le téléphone du payeur. Composez votre code secret pour confirmer.',
                'A payment request was sent to the payer’s phone. Enter your secret code to confirm.',
              ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        KumbaButton(
          label: S.tr('J’ai confirmé — vérifier', 'I approved — check now'),
          icon: Icons.refresh_rounded,
          variant: KumbaButtonVariant.outline,
          onPressed: _recheck,
        ),
      ],
    );
  }

  Widget _banner(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFcfa(num amount) {
    final formatted = NumberFormat.decimalPattern('fr_FR').format(amount);
    return '$formatted ${AppConfig.defaultCurrency}';
  }
}
