import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/expense_service.dart';

final _expensesProvider = FutureProvider.autoDispose<List<Expense>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(expenseServiceProvider).list(business.id);
});

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final cats = await ref
        .read(expenseServiceProvider)
        .categories(ref.read(sessionProvider).business!.id);
    if (!context.mounted) return;
    String? catId = cats.isNotEmpty ? cats.first.id : null;
    String? catName = cats.isNotEmpty ? cats.first.name : null;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nouvelle dépense',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              KumbaAmountField(
                controller: amountCtrl,
                label: 'Montant',
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Text(
                S.tr('Catégorie', 'Category'),
                style: Theme.of(ctx).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: cats
                    .map(
                      (c) => ChoiceChip(
                        label: Text(c.name),
                        selected: catId == c.id,
                        onSelected: (_) => setModal(() {
                          catId = c.id;
                          catName = c.name;
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              KumbaTextField(
                controller: descCtrl,
                label: 'Description (optionnel)',
              ),
              const SizedBox(height: 20),
              KumbaButton(
                label: 'Enregistrer',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;
    final amount = MoneyFormat.parse(amountCtrl.text);
    if (amount == null) return;

    try {
      final session = ref.read(sessionProvider);
      await ref
          .read(expenseServiceProvider)
          .create(
            session.business!.id,
            ExpenseInput(
              amount: amount,
              categoryId: catId,
              categoryName: catName,
              description: descCtrl.text.isEmpty ? null : descCtrl.text,
            ),
            userId: session.user?.id,
            userRole: session.role,
          );
      ref.invalidate(_expensesProvider);
    } on AppException catch (e) {
      if (context.mounted) {
        showLkToast(context, e.message, tone: LkToastTone.danger, icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_expensesProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Dépenses', 'Expenses'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const KumbaSkeletonList(),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (expenses) {
          if (expenses.isEmpty) {
            return KumbaEmptyState(
              title: 'Aucune dépense',
              subtitle: 'Enregistrez loyers, transport, salaires…',
              actionLabel: 'Ajouter',
              onAction: () => _add(context, ref),
            );
          }
          final total = expenses.fold<double>(0, (s, e) => s + e.amount);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Total : ${MoneyFormat.format(total)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.kpiDeposit,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              ...expenses.map(
                (e) => ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  title: Text(e.categoryName ?? 'Dépense'),
                  subtitle: Text(
                    '${DateFormat('dd/MM/yyyy').format(e.expenseDate)}'
                    '${e.description != null ? ' · ${e.description}' : ''}',
                  ),
                  trailing: Text(
                    MoneyFormat.format(e.amount),
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
