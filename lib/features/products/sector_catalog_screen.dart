import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/catalog/sector_catalog.dart';
import '../../core/errors/user_error_message.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_chips.dart';
import '../../design_system/components/kumba_pressable.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/sector_catalog_service.dart';

final _catalogOffersProvider =
    FutureProvider.autoDispose<List<SectorCatalogOffer>>((ref) async {
      final session = ref.watch(sessionProvider);
      final business = session.business;
      if (business == null) return const [];
      final query = ref.watch(_catalogQueryProvider);
      final category = ref.watch(_catalogCategoryProvider);
      final filter = ref.watch(_catalogFilterProvider);
      return ref
          .watch(sectorCatalogServiceProvider)
          .offers(
            sector: business.sector,
            businessId: business.id,
            query: query,
            category: category,
            filter: filter,
          );
    });

final _catalogQueryProvider = StateProvider.autoDispose<String>((_) => '');
final _catalogCategoryProvider = StateProvider.autoDispose<String?>(
  (_) => null,
);
final _catalogFilterProvider = StateProvider.autoDispose<CatalogOfferFilter>(
  (_) => CatalogOfferFilter.inactive,
);

class SectorCatalogScreen extends ConsumerStatefulWidget {
  const SectorCatalogScreen({super.key});

  @override
  ConsumerState<SectorCatalogScreen> createState() =>
      _SectorCatalogScreenState();
}

class _SectorCatalogScreenState extends ConsumerState<SectorCatalogScreen> {
  final _searchCtrl = TextEditingController();
  final _selected = <String>{};
  bool _activating = false;

  @override
  void initState() {
    super.initState();
    AppAnalytics.track('catalog.opened');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate(List<SectorCatalogProduct> items) async {
    if (_activating || items.isEmpty) return;
    final session = ref.read(sessionProvider);
    final business = session.business;
    if (business == null) return;
    setState(() => _activating = true);
    try {
      final count = await ref
          .read(sectorCatalogServiceProvider)
          .activateMany(
            business.id,
            items,
            userId: session.user?.id,
            userRole: session.role,
          );
      ref.invalidate(_catalogOffersProvider);
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _activating = false;
      });
      showLkToast(
        context,
        S.tr(
          count == 1
              ? '1 produit activé dans votre catalogue.'
              : '$count produits activés dans votre catalogue.',
          count == 1
              ? '1 product activated in your catalog.'
              : '$count products activated in your catalog.',
        ),
        tone: LkToastTone.success,
        icon: Icons.check_circle_outline,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _activating = false);
      showLkToast(
        context,
        userFacingErrorMessage(
          error,
          fallback: S.tr(
            'Impossible d’activer ces produits pour le moment.',
            'Unable to activate these products right now.',
          ),
        ),
        tone: LkToastTone.danger,
        icon: Icons.error_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final business = session.business;
    final sector = business?.sector ?? 'boutique';
    final totalRegistered = SectorCatalog.forSector(sector).length;
    final categories = [
      S.tr('Toutes', 'All'),
      ...SectorCatalog.categoriesFor(sector),
    ];
    final selectedCategory = ref.watch(_catalogCategoryProvider);
    final filter = ref.watch(_catalogFilterProvider);
    final async = ref.watch(_catalogOffersProvider);
    final filterId = switch (filter) {
      CatalogOfferFilter.inactive => 'inactive',
      CatalogOfferFilter.activated => 'activated',
      CatalogOfferFilter.all => 'all',
    };

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(S.tr('Produits du secteur', 'Sector products')),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _activating ? null : () => setState(_selected.clear),
              child: Text(S.tr('Annuler', 'Cancel')),
            ),
        ],
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _activating
                  ? null
                  : () {
                      final offers = async.valueOrNull ?? const [];
                      final items = [
                        for (final offer in offers)
                          if (_selected.contains(offer.product.id))
                            offer.product,
                      ];
                      _activate(items);
                    },
              icon: _activating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                S.tr(
                  'Activer ${_selected.length}',
                  'Activate ${_selected.length}',
                ),
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(S.tr('Catalogues fournisseurs', 'Supplier catalogues')),
            subtitle: Text(
              S.tr(
                'Boulangerie, parfumerie, téléphonie',
                'Bakery, perfumery, electronics',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/products/supplier-catalogues'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              S.tr(
                '$totalRegistered références enregistrées — activez celles que vous vendez. Stock initial : 0.',
                '$totalRegistered registered items — activate the ones you sell. Starting stock: 0.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: KumbaSearchPill(
              hint: S.tr(
                'Nom, catégorie, code-barres…',
                'Name, category, barcode…',
              ),
              controller: _searchCtrl,
              onChanged: (v) =>
                  ref.read(_catalogQueryProvider.notifier).state = v,
            ),
          ),
          KumbaChipBar(
            items: [
              KumbaFilterChipData(
                id: 'inactive',
                label: S.tr('Non activés', 'Not activated'),
              ),
              KumbaFilterChipData(
                id: 'activated',
                label: S.tr('Activés', 'Activated'),
              ),
              KumbaFilterChipData(id: 'all', label: S.tr('Tous', 'All')),
            ],
            selectedId: filterId,
            onSelected: (id) {
              ref.read(_catalogFilterProvider.notifier).state = switch (id) {
                'activated' => CatalogOfferFilter.activated,
                'all' => CatalogOfferFilter.all,
                _ => CatalogOfferFilter.inactive,
              };
              setState(_selected.clear);
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final label = categories[i];
                final id = i == 0 ? null : label;
                final selected = selectedCategory == id;
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    ref.read(_catalogCategoryProvider.notifier).state = id;
                    HapticFeedback.selectionClick();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () => const KumbaSkeletonList(),
              error: (e, _) => KumbaErrorState(message: e.toString()),
              data: (offers) {
                if (offers.isEmpty) {
                  return KumbaEmptyState(
                    title: S.tr('Aucune référence', 'No items'),
                    subtitle: S.tr(
                      'Essayez un autre filtre ou une autre catégorie.',
                      'Try another filter or category.',
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: offers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final offer = offers[i];
                    final product = offer.product;
                    final picked = _selected.contains(product.id);
                    return KumbaPressable(
                      onTap: offer.activated
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (picked) {
                                  _selected.remove(product.id);
                                } else {
                                  _selected.add(product.id);
                                }
                              });
                            },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        decoration: BoxDecoration(
                          color: AppColors.card(context),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusLg,
                          ),
                          border: Border.all(
                            color: picked
                                ? AppColors.primary
                                : AppColors.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.catalogBlock(
                                product.name.hashCode,
                              ),
                              child: Text(
                                product.name.isEmpty
                                    ? '?'
                                    : product.name[0].toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.secondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${product.category} · ${product.unit} · ${MoneyFormat.format(product.salePrice)}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (offer.activated)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  S.tr('Activé', 'Active'),
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: AppColors.emerald,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              )
                            else
                              IconButton(
                                tooltip: S.tr('Activer', 'Activate'),
                                onPressed: _activating
                                    ? null
                                    : () => _activate([product]),
                                icon: Icon(
                                  picked
                                      ? Icons.check_circle_rounded
                                      : Icons.add_circle_outline_rounded,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
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
