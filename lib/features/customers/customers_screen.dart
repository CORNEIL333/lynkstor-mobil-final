import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_chips.dart';
import '../../design_system/components/kumba_ios.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/customer_service.dart';

final _customersProvider = FutureProvider.autoDispose<List<Customer>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(customerServiceProvider).list(business.id);
});

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showCreate() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final neighborhood = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
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
              S.tr('Nouveau client', 'New customer'),
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            KumbaTextField(
              controller: name,
              label: 'Nom',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            KumbaTextField(
              controller: phone,
              label: 'Téléphone',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            KumbaTextField(controller: neighborhood, label: 'Quartier'),
            const SizedBox(height: 20),
            KumbaButton(
              label: 'Enregistrer',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    await ref
        .read(customerServiceProvider)
        .create(
          session.business!.id,
          CustomerInput(
            name: name.text,
            phone: phone.text.isEmpty ? null : phone.text,
            neighborhood: neighborhood.text.isEmpty ? null : neighborhood.text,
          ),
          userId: session.user?.id,
          userRole: session.role,
        );
    ref.invalidate(_customersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_customersProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.tr('Carnet', 'Book'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        Text(
                          S.tr('Clients', 'Customers'),
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                height: 1.05,
                              ),
                        ),
                      ],
                    ),
                  ),
                  KumbaChromeButton(
                    icon: Icons.person_add_alt_1_rounded,
                    onTap: _showCreate,
                    tooltip: S.tr('Nouveau client', 'New customer'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: KumbaSearchPill(
              controller: _searchCtrl,
              hint: 'Rechercher un client…',
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const KumbaSkeletonList(),
              error: (e, _) => KumbaErrorState(message: e.toString()),
              data: (customers) {
                final list = _query.isEmpty
                    ? customers
                    : customers
                          .where(
                            (c) =>
                                c.name.toLowerCase().contains(_query) ||
                                (c.phone?.contains(_query) ?? false),
                          )
                          .toList();
                if (list.isEmpty) {
                  return KumbaEmptyState(
                    title: 'Aucun client',
                    subtitle:
                        'Enregistrez vos clients pour le crédit et le suivi.',
                    actionLabel: 'Ajouter',
                    onAction: _showCreate,
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [
                    KumbaInsetGroup(
                      children: [
                        for (final c in list)
                          KumbaInsetRow(
                            icon: Icons.person_outline_rounded,
                            iconColor: AppColors.ocean,
                            title: c.name,
                            subtitle: [
                              c.phone,
                              c.neighborhood,
                            ].whereType<String>().join(' · '),
                            value: c.balance > 0
                                ? MoneyFormat.format(c.balance)
                                : null,
                            onTap: () => context.push('/customers/${c.id}'),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
