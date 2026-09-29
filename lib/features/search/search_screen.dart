import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_ai_badge.dart';
import '../../design_system/components/kumba_chips.dart';
import '../../design_system/components/kumba_ios.dart';
import '../../design_system/motion/kumba_reveal.dart';
import '../../l10n/app_strings.dart';

/// Recherche globale : produits, clients, puis suggestion IA si question.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _looksLikeQuestion {
    final q = _q.trim().toLowerCase();
    if (q.length < 8) return false;
    return q.contains('?') ||
        q.startsWith('combien') ||
        q.startsWith('quel') ||
        q.startsWith('who') ||
        q.startsWith('what') ||
        q.startsWith('how');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final business = session.business;
    final bottom = 28.0;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(S.search),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: KumbaSearchPill(
              controller: _ctrl,
              hint: S.tr('Produits, clients, une question…',
                  'Products, customers, a question…'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (_looksLikeQuestion)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: KumbaReveal(
                child: KumbaAiFrame(
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome_rounded,
                        color: AppColors.aiViolet),
                    title: Text(
                      S.tr('Demander à Lynk', 'Ask Lynk'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(_q.trim()),
                    trailing: const KumbaAiBadge(compact: true),
                    onTap: () => context.go('/ai'),
                  ),
                ),
              ),
            ),
          Expanded(
            child: business == null
                ? const SizedBox.shrink()
                : FutureBuilder(
                    future: Future.wait([
                      ref.read(productServiceProvider).list(business.id),
                      ref.read(customerServiceProvider).list(business.id),
                    ]),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final q = _q.toLowerCase();
                      final products = (snap.data![0] as List<Product>)
                          .where((p) {
                            if (q.isEmpty) return false;
                            return p.name.toLowerCase().contains(q);
                          })
                          .take(8)
                          .toList();
                      final customers = (snap.data![1] as List<Customer>)
                          .where((c) {
                            if (q.isEmpty) return false;
                            return c.name.toLowerCase().contains(q);
                          })
                          .take(8)
                          .toList();
                      if (q.isEmpty) {
                        return Center(
                          child: Text(
                            S.tr(
                              'Tapez un nom, un client ou une question.',
                              'Type a name, a customer or a question.',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }
                      return ListView(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
                        children: [
                          if (products.isNotEmpty) ...[
                            KumbaSectionTitle(S.tr('Produits', 'Products')),
                            for (final p in products)
                              ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: Text(p.name),
                                trailing: Text(
                                  MoneyFormat.format(p.salePrice),
                                  style: const TextStyle(
                                    fontFeatures: [FontFeature.tabularFigures()],
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                onTap: () => context.push('/products/${p.id}'),
                              ),
                          ],
                          if (customers.isNotEmpty) ...[
                            KumbaSectionTitle(S.tr('Clients', 'Customers')),
                            for (final c in customers)
                              ListTile(
                                title: Text(c.name),
                                onTap: () =>
                                    context.push('/customers/${c.id}'),
                              ),
                          ],
                          if (products.isEmpty &&
                              customers.isEmpty &&
                              !_looksLikeQuestion)
                            Padding(
                              padding: const EdgeInsets.only(top: 32),
                              child: Text(
                                S.tr('Aucun résultat', 'No results'),
                                textAlign: TextAlign.center,
                              ),
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
