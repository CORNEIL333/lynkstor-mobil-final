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
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  Customer? _customer;
  List<DebtMovement> _movements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ref.read(customerServiceProvider).byId(widget.customerId);
    final m = await ref
        .read(customerServiceProvider)
        .movements(widget.customerId);
    setState(() {
      _customer = c;
      _movements = m;
      _loading = false;
    });
  }

  Future<void> _collect() async {
    final amountCtrl = TextEditingController();
    String method = 'cash';
    final refCtrl = TextEditingController();

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
                'Encaisser une dette',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              Text(
                '${S.tr('Solde', 'Balance')} : '
                '${MoneyFormat.format(_customer!.balance)}',
              ),
              const SizedBox(height: 12),
              KumbaAmountField(
                controller: amountCtrl,
                label: 'Montant',
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(S.tr('Espèces', 'Cash')),
                    selected: method == 'cash',
                    onSelected: (_) => setModal(() => method = 'cash'),
                  ),
                  ChoiceChip(
                    label: const Text('MTN MoMo'),
                    selected: method == 'mtn_momo',
                    onSelected: (_) => setModal(() => method = 'mtn_momo'),
                  ),
                  ChoiceChip(
                    label: const Text('Orange Money'),
                    selected: method == 'orange_money',
                    onSelected: (_) => setModal(() => method = 'orange_money'),
                  ),
                ],
              ),
              if (method != 'cash') ...[
                const SizedBox(height: 12),
                KumbaTextField(
                  controller: refCtrl,
                  label: 'Référence (optionnel)',
                ),
              ],
              const SizedBox(height: 20),
              KumbaButton(
                label: 'Valider',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;
    final amount = MoneyFormat.parse(amountCtrl.text);
    if (amount == null || amount <= 0) return;

    try {
      final session = ref.read(sessionProvider);
      await ref
          .read(customerServiceProvider)
          .collectDebt(
            businessId: session.business!.id,
            customerId: widget.customerId,
            amount: amount,
            method: method,
            methodRef: refCtrl.text.isEmpty ? null : refCtrl.text,
            userId: session.user?.id,
            userRole: session.role,
          );
      await _load();
      if (mounted) {
        showLkToast(
          context,
          S.tr(
            'Paiement enregistré — solde mis à jour.',
            'Payment saved — balance updated.',
          ),
          tone: LkToastTone.success,
          icon: Icons.check_circle_outline,
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        showLkToast(context, e.message, tone: LkToastTone.danger, icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.pageBg,
        body: KumbaLoading(),
      );
    }
    final c = _customer;
    if (c == null) {
      return Scaffold(
        backgroundColor: AppColors.pageBg,
        appBar: AppBar(),
        body: const KumbaErrorState(message: 'Client introuvable'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          KumbaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.phone != null)
                  Text('${S.tr('Tél.', 'Phone')} ${c.phone}'),
                if (c.neighborhood != null) Text(c.neighborhood!),
                const SizedBox(height: 12),
                Text(
                  'Solde dû',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  MoneyFormat.format(c.balance),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: c.balance > 0 ? AppColors.debt : AppColors.forest,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (c.creditLimit > 0)
                  Text(
                    'Limite de crédit : ${MoneyFormat.format(c.creditLimit)}',
                  ),
              ],
            ),
          ),
          if (c.balance > 0) ...[
            const SizedBox(height: 16),
            KumbaButton(
              label: 'Encaisser',
              icon: Icons.payments_outlined,
              onPressed: _collect,
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Mouvements de dette',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_movements.isEmpty)
            const Text(
              'Aucun mouvement — le solde ne change jamais sans transaction.',
            )
          else
            ..._movements.map(
              (m) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  m.type == 'payment'
                      ? 'Paiement'
                      : m.type == 'credit_sale'
                      ? 'Vente à crédit'
                      : m.type,
                ),
                subtitle: Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(m.createdAt),
                ),
                trailing: Text(
                  '${m.amount > 0 ? '+' : ''}${MoneyFormat.format(m.amount)}',
                  style: TextStyle(
                    color: m.amount > 0 ? AppColors.debt : AppColors.forest,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
