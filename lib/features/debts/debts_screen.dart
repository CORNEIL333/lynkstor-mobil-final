import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/lynk_context_bubble.dart';
import '../../features/ai_assistant/lynk_quick_sheet.dart';
import '../../l10n/app_strings.dart';

final _debtsProvider = FutureProvider.autoDispose<List<Customer>>((ref) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(customerServiceProvider).debtors(business.id);
});

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_debtsProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        surfaceTintColor: Colors.transparent,
        title: Text(S.tr('Carnet de dettes', 'Debt book')),
      ),
      body: async.when(
        loading: () => const KumbaSkeletonList(),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (debtors) {
          if (debtors.isEmpty) {
            return const KumbaEmptyState(
              title: 'Aucune dette en cours',
              subtitle:
                  'Les ventes à crédit apparaîtront ici avec le solde de chaque client.',
              icon: Icons.handshake_outlined,
            );
          }
          final total = debtors.fold<double>(0, (s, c) => s + c.balance);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LynkContextBubble(
                message: S.tr(
                  '${debtors.length} client(s) te doivent ${MoneyFormat.format(total)}. Je peux te dire qui relancer.',
                  '${debtors.length} customer(s) owe ${MoneyFormat.format(total)}. I can tell you who to follow up.',
                ),
                actionLabel: S.tr('Demander à Lynk', 'Ask Lynk'),
                onAction: () {
                  ref.read(pendingAiPromptProvider.notifier).state = S.tr(
                    'Qui me doit le plus en ce moment ?',
                    'Who owes me the most right now?',
                  );
                  showLynkQuickSheet(context);
                },
              ),
              const SizedBox(height: 12),
              KumbaCard(
                color: AppColors.ice,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total à encaisser',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      MoneyFormat.format(total),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: AppColors.debt,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    Text(
                      S.isEnglish
                          ? '${debtors.length} customer(s)'
                          : '${debtors.length} client(s)',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...debtors.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    title: Text(c.name),
                    subtitle: Text(c.phone ?? c.neighborhood ?? ''),
                    trailing: Text(
                      MoneyFormat.format(c.balance),
                      style: const TextStyle(
                        color: AppColors.debt,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => context.push('/customers/${c.id}'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
