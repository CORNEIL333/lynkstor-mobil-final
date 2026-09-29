import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_chips.dart';
import '../../design_system/components/kumba_pressable.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/motion/kumba_reveal.dart';
import '../../l10n/app_strings.dart';

final _productsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(productServiceProvider).list(business.id);
});

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_productsProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(S.tr('Catalogue', 'Catalog')),
        actions: [
          IconButton(
            tooltip: S.tr('Produits du secteur', 'Sector products'),
            onPressed: () async {
              await context.push('/products/catalog');
              ref.invalidate(_productsProvider);
            },
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: KumbaCircleIcon(
              icon: Icons.add_rounded,
              filled: true,
              onTap: () => context.push('/products/new'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: KumbaSearchPill(
              hint: 'Nom, code-barres, SKU…',
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: KumbaPressable(
              onTap: () async {
                await context.push('/products/catalog');
                ref.invalidate(_productsProvider);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        S.tr(
                          'Plus de 1000 produits du secteur, déjà enregistrés. Activez ceux que vous vendez.',
                          'More than 1,000 sector products already registered. Activate the ones you sell.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const KumbaSkeletonList(),
              error: (e, _) => KumbaErrorState(message: e.toString()),
              data: (products) {
                final q = _query.toLowerCase();
                final list = q.isEmpty
                    ? products
                    : products
                          .where(
                            (p) =>
                                p.name.toLowerCase().contains(q) ||
                                (p.barcode?.contains(_query) ?? false),
                          )
                          .toList();
                if (list.isEmpty) {
                  return KumbaEmptyState(
                    title: S.tr('Aucun produit activé', 'No activated product'),
                    subtitle: S.tr(
                      'Plus de 1000 références de votre secteur sont déjà enregistrées. Activez celles que vous vendez.',
                      'More than 1,000 items for your sector are already registered. Activate the ones you sell.',
                    ),
                    actionLabel: S.tr(
                      'Voir les produits du secteur',
                      'Browse sector products',
                    ),
                    onAction: () async {
                      await context.push('/products/catalog');
                      ref.invalidate(_productsProvider);
                    },
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final block = AppColors.catalogBlock(i);
                    return KumbaReveal(
                      order: i % 8,
                      child: KumbaPressable(
                        onTap: () => context.push('/products/${p.id}'),
                        child: Container(
                          decoration: BoxDecoration(
                            color: block,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusXl,
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Center(
                                  child: _ProductPhoto(
                                    path: p.photoPath,
                                    name: p.name,
                                    large: true,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.secondary,
                                      height: 1.15,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                MoneyFormat.format(p.salePrice),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.secondary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                              Text(
                                p.isService
                                    ? 'Service'
                                    : '${p.stockQty.toStringAsFixed(0)} ${p.unit}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppColors.secondary.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPhoto extends StatelessWidget {
  const _ProductPhoto({
    required this.path,
    required this.name,
    this.large = false,
  });

  final String? path;
  final String name;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final size = large ? 96.0 : 52.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(large ? 20 : 12),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null && file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: large ? 280 : 156,
                errorBuilder: (_, __, ___) => _placeholder(context),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}
