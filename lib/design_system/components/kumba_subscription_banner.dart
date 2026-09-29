import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/config/runtime_config.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/subscription_info.dart';

/// Bannière abonnement (expiré / hors cloud / forfait).
class KumbaSubscriptionBanner extends ConsumerWidget {
  const KumbaSubscriptionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(sessionProvider).subscription;
    if (sub.isDemo) return const SizedBox.shrink();
    if (sub.allowsSales && sub.source == 'cloud' && sub.status == 'active') {
      return const SizedBox.shrink();
    }
    if (sub.source == 'local') {
      if (!ActivationPolicy.requireAgentActivationCode) {
        return const SizedBox.shrink();
      }
      return _bar(
        context,
        color: AppColors.amber,
        bg: AppColors.warningSoft,
        icon: Icons.cloud_off_outlined,
        title: S.tr('Hors abonnement cloud', 'Cloud subscription unavailable'),
        subtitle: S.tr(
          'Créez le commerce avec un code agent pour lier Lynkstor.',
          'Create the business with an agent code to link Lynkstor.',
        ),
      );
    }
    if (!sub.allowsSales || sub.isExpired) {
      return _bar(
        context,
        color: AppColors.error,
        bg: AppColors.errorSoft,
        icon: Icons.lock_clock_rounded,
        title: _localizedStatus(sub),
        subtitle: S.tr(
          'Forfait ${sub.planName}${sub.expiresAt != null ? ' · exp. ${sub.expiresAt}' : ''}. Contactez votre commercial.',
          'Plan ${sub.planName}${sub.expiresAt != null ? ' · exp. ${sub.expiresAt}' : ''}. Contact your agent.',
        ),
        action: TextButton(
          onPressed: () => context.push('/subscription'),
          child: Text(S.tr('Voir', 'View')),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _bar(
    BuildContext context, {
    required Color color,
    required Color bg,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) action,
          ],
        ),
      ),
    );
  }
}

/// Carte licence détaillée (Paramètres).
class KumbaLicenseCard extends ConsumerWidget {
  const KumbaLicenseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final sub = session.subscription;
    final isDemo = session.business?.isDemo == true || sub.isDemo;

    Color accent;
    Color bg;
    if (isDemo) {
      accent = AppColors.amber;
      bg = AppColors.warningSoft;
    } else if (!sub.allowsSales) {
      accent = AppColors.error;
      bg = AppColors.errorSoft;
    } else if (sub.source == 'cloud') {
      accent = AppColors.emerald;
      bg = AppColors.forestSoft;
    } else {
      accent = AppColors.tertiary;
      bg = AppColors.tertiaryFixed;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isDemo
                      ? S.tr('LICENCE DÉMO', 'DEMO LICENSE')
                      : S.tr('ABONNEMENT LYNKSTOR', 'LYNKSTOR SUBSCRIPTION'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.9,
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _localizedStatus(sub),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isDemo
                ? S.tr('Mode démonstration', 'Demonstration mode')
                : '${S.tr('Forfait', 'Plan')} ${sub.planName}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isDemo
                ? S.tr(
                    'Local uniquement · hors cloud · non facturé',
                    'Local only · no cloud · not billed',
                  )
                : sub.source == 'cloud'
                ? [
                    if (sub.expiresAt != null)
                      S.tr(
                        'Expire le ${sub.expiresAt}',
                        'Expires ${sub.expiresAt}',
                      ),
                    if (sub.checkedAt != null)
                      S.tr('Vérifié par le cloud', 'Cloud verified'),
                    sub.allowsSales
                        ? S.tr('Ventes autorisées', 'Sales allowed')
                        : S.tr('Ventes bloquées', 'Sales blocked'),
                  ].join(' · ')
                : ActivationPolicy.requireAgentActivationCode
                ? S.tr(
                    'Non lié au cloud — activation requise pour un vrai forfait',
                    'Not linked to cloud — activation required for a paid plan',
                  )
                : S.tr(
                    'Panel test — commerce actif sur cet appareil, sans clé d’activation.',
                    'Test panel — business is active on this device, no activation key.',
                  ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: accent.withValues(alpha: 0.85),
            ),
          ),
          if (!isDemo) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/subscription'),
                icon: Icon(
                  Icons.arrow_forward_rounded,
                  color: accent,
                  size: 18,
                ),
                label: Text(
                  S.tr(
                    ActivationPolicy.requireAgentActivationCode
                        ? 'Gérer l’activation et le forfait'
                        : 'Voir le forfait',
                    ActivationPolicy.requireAgentActivationCode
                        ? 'Manage activation and plan'
                        : 'View plan',
                  ),
                  style: TextStyle(color: accent, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _localizedStatus(SubscriptionInfo subscription) {
  if (subscription.isDemo) {
    return S.tr('Démo locale', 'Local demo');
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
      return S.tr('Aucun forfait', 'No plan');
    default:
      return subscription.isCloudLinked
          ? S.tr('À vérifier', 'Needs verification')
          : S.tr('Mode local', 'Local mode');
  }
}
